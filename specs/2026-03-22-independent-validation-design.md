# Independent Validation Round Design

## Problem

review-loop 中 Claude 和 Codex 在迭代审查中会达成一致（收敛），但事后独立审查仍能发现 **全新类别的问题**——即 loop 内的审查者存在共同盲区。这不是审查执行质量的问题，而是两个审查者在同一个 prompt 框架和共享上下文下，注意力分布趋同，导致某些维度从头到尾都未被覆盖。

## Goal

在 review-loop 的现有收敛机制之后，引入一个 **独立验证轮次 (independent validation round)**，由一个全新的、无共享上下文的审查者重新审视产出物。如果验证发现了新问题，将其反馈回 loop 继续迭代，直到验证通过或达到上限。

## Design Principles

1. **上下文隔离** — 独立审查者不能看到任何前轮审查历史，只看产出物本身（设计文档或代码 diff）和原始任务描述
2. **视角差异** — 使用与常规审查完全不同的 prompt 模板，侧重于常规审查容易遗漏的维度
3. **最小架构改动** — 复用现有 shell 脚本基础设施（`run-review-bg.sh`, `check-review.sh`），只新增 prompt 模板和 mode

## Architecture

### New mode: `independent-review`

在 `common.sh` 中新增 mode `independent-review`，复用现有的 `run-review-bg.sh` 和 `check-review.sh` 流程。

### New prompt template: `review-loop/prompts/independent-review.md`

与现有 `design-review.md` 的关键差异：

| 维度 | 常规审查 (design-review) | 独立验证 (independent-review) |
|------|------------------------|------------------------------|
| 上下文 | 包含前轮审查历史 | 仅产出物 + 任务描述，零审查历史 |
| 审查目标 | 全面审计 | 专注于协作审查流程容易遗漏的盲区 |
| 审查维度 | 完整性、可行性、架构、安全、可测试性 | 隐含假设、未验证的边界条件、跨模块交互的一致性、真实使用场景下的 failure modes、被标记为"低优先级"但实际重要的问题 |
| 输出要求 | 按 severity 分类 | 按 severity 分类 + 标注"此问题是否可能在迭代审查中被系统性忽略"的判断 |

Prompt 核心指令：

```
You are an independent validator. You have NOT seen any prior review history.
Your job is to find problems that a collaborative, iterative review process
is likely to miss.

Collaborative reviews tend to develop shared assumptions over multiple rounds.
Focus specifically on:

- Assumptions stated as facts without validation
- Edge cases acknowledged but dismissed as "unlikely"
- Interfaces that are internally consistent but may break under real-world usage patterns
- Security and error handling paths that were likely not the focus of design discussion
- Requirements that may have been implicitly dropped during iterative refinement
- Cross-cutting concerns (observability, deployment, rollback) that nobody owns

You must NOT reference or assume knowledge of any prior review rounds.
Your review must stand completely on its own.
```

### Flow integration

#### Design stage

现有流程：

```
Claude writes design → Codex reviews (rounds 1-5) → converge → user gate
```

新流程：

```
Claude writes design → Codex reviews (rounds 1-5) → converge
  → independent validation (max 2 rounds)
  → user gate
```

具体步骤：

1. 现有 design loop 收敛后（常规审查不再发现 substantive issues），进入独立验证阶段
2. 执行 `run-review-bg.sh independent-review 1`
   - Prompt 只包含：`specs/design.md` + 任务描述 + independent-review 模板
   - 不包含 `specs/reviews/design/` 下的任何文件
   - 输出写入 `specs/reviews/validation/design-round-<N>-review.md`
3. Claude 阅读验证结果：
   - 如果无 substantive issues → 验证通过，进入 user gate
   - 如果有 substantive issues → Claude 更新 `specs/design.md`，写入 `specs/reviews/validation/design-round-<N>-response.md`
   - 回到步骤 2（第 2 轮验证），最多 2 轮
4. 如果 2 轮验证后仍有 issues，将剩余 issues 汇总呈现给用户，由用户决定是否继续

#### Code stage

现有流程：

```
Codex implements → Claude reviews (rounds 1-5) → converge
```

新流程：

```
Codex implements → Claude reviews (rounds 1-5) → converge
  → independent validation (max 2 rounds)
  → done
```

具体步骤：

1. 现有 code loop 收敛后，进入独立验证阶段
2. 执行 `run-review-bg.sh independent-review 1`
   - Prompt 包含：`specs/design.md` + 任务描述 + 代码 diff (`git diff $BASELINE_SHA`) + independent-review 模板
   - 不包含 `specs/reviews/code/` 下的任何文件
   - 输出写入 `specs/reviews/validation/code-round-<N>-review.md`
3. Claude 阅读验证结果：
   - 如果无 substantive issues → 验证通过
   - 如果有 substantive issues → 执行 `run-review-bg.sh code-fix <round>` 让 Codex 修复，然后回到步骤 2
   - 最多 2 轮
4. 如果 2 轮后仍有 issues，汇总呈现给用户

### File changes

#### New files

- `review-loop/prompts/independent-review.md` — 独立验证 prompt 模板

#### Modified files

- `review-loop/scripts/common.sh`
  - `validate_mode()`: 新增 `independent-review` mode
  - `expected_output_path()`: 新增 `independent-review` case
  - `build_prompt()`: 新增 `independent-review` case，只注入产出物和任务描述，不注入任何审查历史

- `review-loop/commands/review-loop.md`
  - Design stage: 在常规审查收敛后、user gate 前，新增独立验证步骤
  - Code stage: 在常规审查收敛后、final output 前，新增独立验证步骤
  - Stage transition: `git add` 中包含 `specs/reviews/validation/`

- `review-loop/AGENTS.md`
  - 新增 Independent Validation 阶段文档
  - 明确独立验证者的约束：零审查历史、不修改任何文件

- `tests/review-loop.test.sh`
  - 新增 `test_independent_review_prompt_no_review_history`: 验证 `build_prompt independent-review 1` 不包含任何 `specs/reviews/design/` 或 `specs/reviews/code/` 的内容
  - 新增 `test_independent_review_prompt_includes_design_and_task`: 验证 prompt 包含 design.md 内容和任务描述
  - 新增 `test_independent_review_output_path`: 验证输出路径为 `specs/reviews/validation/`

### Review artifact layout

```
specs/reviews/
  design/                          # existing
    round-1-codex-review.md
    round-1-claude-response.md
    ...
  code/                            # existing
    round-1-claude-review.md
    round-1-codex-response.md
    ...
  validation/                      # new
    design-round-1-review.md       # independent validation of design
    design-round-1-response.md     # Claude's response to validation
    design-round-2-review.md
    code-round-1-review.md         # independent validation of code
    code-round-1-response.md
    code-round-2-review.md
```

### Round and retry semantics

- 独立验证使用独立的轮次计数，与常规审查的轮次无关
- 最大 2 轮验证（硬上限），防止无限循环
- 超时和失败的重试机制复用现有逻辑（retry once on TIMEOUT or FAILED, skip on second failure）
- 验证轮次中的 worktree snapshot 和 rollback 机制与现有 design-review 轮次一致

### Protected paths

独立验证轮次中：
- 允许创建的文件：仅 `specs/reviews/validation/` 下的当前轮次文件
- 保护路径：与现有 design-review 轮次一致

### State file changes

不需要新增 state field。独立验证是收敛后的同步步骤，不需要跨中断恢复。phase 仍然是 `design` 或 `code`，独立验证在 phase 内部完成。

### Cancellation

独立验证期间的取消行为与现有行为一致——kill background process, restore branch, delete session branch。

## Limitations and future work

- 当前方案使用 Codex 作为独立审查者。虽然 prompt 和上下文完全不同，但模型层面的认知偏差仍可能存在。未来可考虑支持配置不同的模型作为独立审查者。
- 2 轮硬上限是保守选择。实际使用中如果发现 2 轮不够，可以调整。
- 独立验证的 prompt 维度是预设的，可能需要根据实际使用中观察到的盲区类型持续迭代优化。
