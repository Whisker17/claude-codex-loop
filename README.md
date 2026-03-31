# review-loop

`review-loop` is a Claude Code plugin that drives a collaboration loop with Codex:

1. **(Optional) Brainstorming** — If the `superpowers:brainstorming` skill is available, Claude Code can brainstorm requirements before designing.
2. **Design stage** — Claude Code writes and iterates on a design while Codex audits it with full independent reviews each round.
3. **Code stage** — After a user approval gate, Codex implements code while Claude Code reviews it.

The implementation follows [`specs/design.md`](specs/design.md), which was iteratively refined through 5 rounds of design review + a verification pass.

## Layout

- `review-loop/scripts/`: runtime scripts for background execution, polling, and cancellation
- `review-loop/prompts/`: Codex prompt templates
- `review-loop/commands/`: Claude Code slash-command documents
- `review-loop/hooks/`: cleanup-only hook configuration
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
       "/absolute/path/to/claude-codex-loop/review-loop"
     ]
   }
   ```

3. Ensure the scripts are executable:

   ```bash
   chmod +x /path/to/claude-codex-loop/review-loop/scripts/*.sh
   ```

### Usage

Open Claude Code in your target project and run:

```
/review-loop <task description>
```

This starts the full workflow:

1. **Brainstorming (optional)** — If `superpowers:brainstorming` is available, you'll be asked whether to brainstorm first. Output is saved to `specs/brainstorm.md`.
2. **Design stage** — Claude Code writes `specs/design.md`, Codex audits it iteratively (up to 5 rounds + optional verify pass). Each round is a full independent audit.
3. **User gate** — You review and confirm the design before proceeding.
4. **Code stage** — Codex implements the code, Claude Code reviews it iteratively (up to 5 rounds). Each round is a full independent review of the entire diff.

All changes are made on a dedicated `review-loop/<session-id>` branch.

To cancel at any time:

```
/cancel-review
```

Cancellation discards all session work and restores the starting branch.

### Marketplace

This plugin is available on the Claude Code plugin marketplace. You can also install it locally by pointing your project's `settings.json` to the plugin directory.

## Verification

Run:

```bash
bash tests/review-loop.test.sh
```

## Version History

### v2.3

- **Independent validation round** — a separate validation pass after design and code stages
- **Marketplace plugin manifest** — `.claude-plugin/plugin.json` for official publishing

### v2.1

- **Optional brainstorming stage** with user opt-in when `superpowers:brainstorming` is available
- **Fresh independent reviews** — every review round mandates a full audit; verify rounds strip all prior context
- **Improved cancellation** — records `start_branch`/`start_sha`, restores starting point on cancel
- **Session-scoped brainstorming** — `brainstorm_done` flag prevents stale artifacts from bleeding across sessions
- **Protected brainstorm artifacts** — `specs/brainstorm.md` excluded from code-stage staging and diffs

See [`specs/design.md`](specs/design.md) for the current implementation spec.

## Runtime Notes

- The runtime scripts discover the project root by locating `.claude/review-loop.local.md`, so they can be called from subdirectories.
- `REVIEW_LOOP_TIMEOUT_SECONDS` can override the default 20 minute Codex watchdog during tests or debugging.
