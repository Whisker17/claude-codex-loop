# Review Loop v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `review-loop` Claude Code plugin described in `specs/2026-03-20-review-loop-v2-design.md`, including runtime scripts, prompt templates, command docs, hook config, and a self-contained shell test suite.

**Architecture:** The plugin lives under `plugins/review-loop/` and uses Bash scripts for background Codex execution, polling, and cancellation. Prompt templates and command documents stay declarative in Markdown, while tests use temporary repositories and fake `codex` binaries to verify runtime behavior without external dependencies.

**Tech Stack:** Bash, Markdown, POSIX utilities, temporary git repositories for integration tests

---

### Task 1: Scaffold plugin and test boundaries

**Files:**
- Create: `README.md`
- Create: `plugins/review-loop/AGENTS.md`
- Create: `plugins/review-loop/prompts/design-review.md`
- Create: `plugins/review-loop/prompts/code-implement.md`
- Create: `plugins/review-loop/prompts/code-fix.md`
- Create: `plugins/review-loop/commands/review-loop.md`
- Create: `plugins/review-loop/commands/cancel-review.md`
- Create: `plugins/review-loop/hooks/hooks.json`
- Create: `tests/review-loop.test.sh`

- [ ] **Step 1: Write failing tests for the plugin surface**

```bash
bash tests/review-loop.test.sh
```

Expected: FAIL because plugin files and scripts do not exist yet.

- [ ] **Step 2: Add the declarative plugin files**

Create the prompt templates, command docs, hook config, and project README with the expected paths and documented behavior from the spec.

- [ ] **Step 3: Re-run the test suite**

```bash
bash tests/review-loop.test.sh
```

Expected: still FAIL because runtime scripts are not implemented.

### Task 2: Implement `run-review-bg.sh`

**Files:**
- Create: `plugins/review-loop/scripts/run-review-bg.sh`
- Modify: `tests/review-loop.test.sh`

- [ ] **Step 1: Add a failing integration test for background launch**

Test behavior:
- Reads `.claude/review-loop.local.md`
- Renders a mode-specific prompt with injected context
- Starts a background `codex exec`
- Writes session pid/log files
- Produces a `done` sentinel when the fake `codex` exits successfully

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tests/review-loop.test.sh
```

Expected: FAIL because `run-review-bg.sh` is missing.

- [ ] **Step 3: Implement the minimal launcher**

Include:
- strict mode
- plugin-root discovery
- mode validation
- state-file parsing
- prompt rendering with round placeholders
- stale pid/sentinel cleanup
- background launch with watchdog and session log file

- [ ] **Step 4: Re-run the test suite**

```bash
bash tests/review-loop.test.sh
```

Expected: launch-related tests PASS; polling/cancel tests still FAIL.

### Task 3: Implement polling and cancellation

**Files:**
- Create: `plugins/review-loop/scripts/check-review.sh`
- Create: `plugins/review-loop/scripts/kill-review.sh`
- Modify: `tests/review-loop.test.sh`

- [ ] **Step 1: Add failing tests for `RUNNING`, `DONE`, `TIMEOUT`, and `FAILED` states**

Cover:
- sentinel missing + live pid => `RUNNING`
- sentinel `timeout` => `TIMEOUT`
- sentinel `done` + missing required review artifact => `FAILED`
- sentinel `done` + expected artifact => `DONE`
- `kill-review.sh` terminates the process group and removes session runtime files

- [ ] **Step 2: Run the test suite to verify those cases fail**

```bash
bash tests/review-loop.test.sh
```

Expected: FAIL on missing polling and kill behavior.

- [ ] **Step 3: Implement the scripts**

Behavior:
- `check-review.sh` reads pid/sentinel and validates mode-specific completion
- `kill-review.sh` kills the session process group and removes pid/sentinel/log files

- [ ] **Step 4: Re-run the test suite**

```bash
bash tests/review-loop.test.sh
```

Expected: all script tests PASS.

### Task 4: Align docs and final verification

**Files:**
- Modify: `README.md`
- Modify: `plugins/review-loop/commands/review-loop.md`
- Modify: `plugins/review-loop/commands/cancel-review.md`
- Modify: `plugins/review-loop/AGENTS.md`
- Modify: `plugins/review-loop/hooks/hooks.json`
- Modify: `tests/review-loop.test.sh`

- [ ] **Step 1: Add tests that assert the command docs and hook config mention the required stage flow**

Assertions:
- design stage, user gate, and code stage are all documented
- commands point to the runtime scripts
- hook config is cleanup-only

- [ ] **Step 2: Run the test suite to verify any doc assertions fail first**

```bash
bash tests/review-loop.test.sh
```

Expected: FAIL until the docs fully match the required flow.

- [ ] **Step 3: Update the docs/config to satisfy the spec**

Keep the command documents operational for Claude Code while preserving the v2 workflow, retry policy, and protected-path behavior.

- [ ] **Step 4: Run final verification**

```bash
bash tests/review-loop.test.sh
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add README.md docs/superpowers/plans/2026-03-20-review-loop-v2.md plugins/review-loop tests/review-loop.test.sh
git commit -m "feat: implement review-loop v2 plugin"
```
