# Independent Validation Round — Brainstorming Output

## Problem Statement

review-loop 中 Claude 和 Codex 在迭代审查中达成一致（收敛），但事后独立审查仍能发现全新类别的问题。两个审查者在同一个 prompt 框架和共享上下文下，注意力分布趋同，存在共同盲区。

## Key Design Decisions

通过逐一澄清确定的设计选择：

1. **验证发现问题后的反馈机制** → 重新进入常规 loop 修复（不是 Claude 直接修，也不是只报告给用户）。修复本身也需要被审查。

2. **Validation cycle 上限** → 最多 2 个 cycle。每个 cycle = 独立验证 → 修复 loop → 再验证。

3. **修复 loop 轮次** → 独立计数，最多 2 轮。验证发现的问题通常是定向的，不需要太多轮。

4. **Design vs Code prompt** → 两个独立 prompt 模板（`independent-design-review.md` + `independent-code-review.md`），各自深度定制审查维度。

5. **代码修复 mode** → 新增 `validation-fix` mode，专门的 prompt 明确"这些是常规审查遗漏的问题"。

6. **修复 loop 是否能看到验证 review** → 能看到。验证 review 原文作为上下文注入修复 loop，让参与者知道之前遗漏了什么。

## Approach Selection

**选定方案：验证作为现有流程的新 sub-phase**（而非独立 stage）

理由：验证本质上是"收敛确认"而不是独立阶段，不产出新的主要产物。作为 sub-phase 更符合语义，state file 不需要新增 phase 值，改动更小。

## Architecture Summary

### New Modes (3)

| Mode | Purpose | Reviewer | Input | Output |
|------|---------|----------|-------|--------|
| `independent-design-review` | 独立验证设计文档 | Codex | design.md + task, zero review history | `specs/reviews/validation/design-round-<N>-review.md` |
| `independent-code-review` | 独立验证代码 | Codex | design.md + task + code diff, zero review history | `specs/reviews/validation/code-round-<N>-review.md` |
| `validation-fix` | 修复验证发现的代码问题 | Codex | design.md + validation review + code diff | `specs/reviews/validation/code-round-<N>-codex-response.md` |

### New Prompt Files (3)

- `review-loop/prompts/independent-design-review.md` — 设计盲区审查（隐含假设、被忽略的边界条件、跨模块一致性、隐式丢弃的需求）
- `review-loop/prompts/independent-code-review.md` — 代码盲区审查（未处理的 error path、安全问题、部署/回滚风险、spec 与实现偏差）
- `review-loop/prompts/validation-fix.md` — 针对性修复，包含"这些是常规审查遗漏的问题"的上下文

### Design Stage Validation Flow

```
常规 loop (max 5 rounds) → converge
  → validation cycle 1:
      independent-design-review → issues?
        → Yes: Claude updates design.md, writes response
               fix loop (max 2 rounds design-review, with validation findings injected)
               fix loop converges
        → No: validation passed → user gate
  → validation cycle 2: (only if cycle 1 had issues)
      same flow
  → still issues after 2 cycles → summarize to user
```

### Code Stage Validation Flow

```
常规 loop (max 5 rounds) → converge
  → validation cycle 1:
      independent-code-review → issues?
        → Yes: Claude writes review
               validation-fix (Codex fixes, sees validation review)
               fix loop (max 2 rounds: Claude review → validation-fix)
               fix loop converges
        → No: validation passed
  → validation cycle 2: (only if cycle 1 had issues)
      same flow
  → still issues after 2 cycles → summarize to user
```

### Shell Changes

- `common.sh`: `validate_mode()` +3 modes, `expected_output_path()` +3 cases, `build_prompt()` +3 cases, new `append_diff_section()` helper
- No changes to `run-review-bg.sh`, `check-review.sh`, `kill-review.sh`
- State file: no new fields
- Stage transition: `git add` includes `specs/reviews/validation/`

### File Change Summary

**New files (3):** 3 prompt templates

**Modified files (4):**
- `review-loop/scripts/common.sh`
- `review-loop/commands/review-loop.md`
- `review-loop/AGENTS.md`
- `tests/review-loop.test.sh`

### Tests (8 new)

- Prompt content isolation (no regular review history leaks into validation prompts)
- Prompt content inclusion (design.md, task, diff, validation review present where expected)
- Output path correctness for all 3 new modes
- End-to-end run-review-bg for independent-design-review and validation-fix modes
