# review-loop

`review-loop` is a Claude Code plugin that drives a two-stage collaboration loop with Codex:

1. Claude Code writes and iterates on a design while Codex audits it.
2. After a user approval gate, Codex implements code while Claude Code reviews it.

The implementation in this repository follows [`specs/2026-03-20-review-loop-v2-design.md`](specs/2026-03-20-review-loop-v2-design.md).

## Layout

- `plugins/review-loop/scripts/`: runtime scripts for background execution, polling, and cancellation
- `plugins/review-loop/prompts/`: Codex prompt templates
- `plugins/review-loop/commands/`: Claude Code slash-command documents
- `plugins/review-loop/hooks/`: cleanup-only hook configuration
- `tests/review-loop.test.sh`: self-contained shell test suite

## Installation

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- [Codex](https://github.com/openai/codex) CLI installed and available on `PATH`
- A Git repository with a clean working tree

### Setup

1. Clone this repository (or note the absolute path if you already have it):

   ```bash
   git clone https://github.com/Whisker17/claude-codex-loop.git
   ```

2. In the project where you want to use the plugin, add the plugin path to `.claude/settings.json` (or `.claude/settings.local.json`):

   ```json
   {
     "plugins": [
       "/absolute/path/to/claude-codex-loop/plugins/review-loop"
     ]
   }
   ```

3. Ensure the scripts are executable:

   ```bash
   chmod +x /path/to/claude-codex-loop/plugins/review-loop/scripts/*.sh
   ```

### Usage

Open Claude Code in your target project and run:

```
/review-loop <task description>
```

This starts the full workflow:

1. **Design stage** - Claude Code writes `specs/design.md`, Codex audits it iteratively (up to 5 rounds).
2. **User gate** - You review and confirm the design before proceeding.
3. **Code stage** - Codex implements the code, Claude Code reviews it iteratively (up to 5 rounds).

All changes are made on a dedicated `review-loop/<session-id>` branch.

To cancel at any time:

```
/cancel-review
```

### No marketplace publication required

This plugin works locally - you do **not** need to publish it to any marketplace. Just point your project's `settings.json` to the plugin directory and it's ready to use.

## Verification

Run:

```bash
bash tests/review-loop.test.sh
```

## Runtime Notes

- The runtime scripts discover the project root by locating `.claude/review-loop.local.md`, so they can be called from subdirectories.
- `REVIEW_LOOP_TIMEOUT_SECONDS` can override the default 20 minute Codex watchdog during tests or debugging.
