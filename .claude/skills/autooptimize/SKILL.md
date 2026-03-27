---
name: autooptimize
description: "Autonomously optimize any project artifact (prompts, configs, code, plugins) by running end-to-end test scenarios, scoring outputs against binary evals, mutating the artifact, and keeping improvements. Generalized from Karpathy's autoresearch methodology. Use when: optimize this project, improve this plugin, make this better, run autooptimize on, benchmark this, eval my project, improve the prompts, optimize end-to-end quality. Outputs: improved artifact files, a results log, and a changelog of every mutation tried."
---

# Autooptimize

Most projects work about 70% of the time. The other 30% you get subpar results. The fix isn't to rewrite from scratch. It's to let an agent run the project end-to-end dozens of times, score every output, and tighten the artifacts until that 30% disappears.

This skill generalizes Karpathy's autoresearch methodology to any project artifact. Instead of optimizing just skill prompts, we optimize whatever determines output quality — prompts, configs, orchestration logic, agent instructions, or code.

---

## the core job

Take any project with measurable outputs, define what "good output" looks like as binary yes/no checks, then run an autonomous loop that:

1. Executes the project end-to-end using test scenarios
2. Scores every output against the eval criteria
3. Mutates the target artifacts to fix failures
4. Keeps mutations that improve the score, discards the rest
5. Repeats until the score ceiling is hit or the user stops it

**Output:** Improved artifact files + `results.tsv` log + `changelog.md` of every mutation attempted + a live HTML dashboard you can watch in your browser.

---

## before starting: gather context

**STOP. Do not run any experiments until all fields below are confirmed with the user. Ask for any missing fields before proceeding.**

1. **Target artifacts** — Which files control the project's output quality? These are the files you will mutate. Can be one or multiple files (prompts, configs, orchestration docs, agent instructions, code). Need exact paths.
2. **Execution method** — How do you run the project end-to-end? This can be:
   - A shell command (e.g., `bash run.sh <input>`)
   - A Claude Code slash command (e.g., `/review-loop <task>`)
   - A multi-step procedure (describe the steps)
   - An API call or script
3. **Test scenarios** — 3-5 different inputs/tasks to test the project with. Variety matters — pick scenarios that cover different use cases so we don't overfit to one scenario. Each scenario should be self-contained and reproducible.
4. **Output location** — Where does the project produce its outputs? Files, directories, git branches, stdout, etc.
5. **Eval criteria** — 3-6 binary yes/no checks that define a good output. (See [references/eval-guide.md](references/eval-guide.md) for how to write good evals)
6. **Runs per experiment** — How many times should we run the project per mutation? Default: 3 for expensive workflows (LLM-heavy), 5 for cheap ones.
7. **Budget cap** — Optional. Max number of experiment cycles before stopping. Default: no cap (runs until you stop it).
8. **Cleanup procedure** — How to reset the environment between runs? (e.g., `git checkout -- .`, delete output dirs, etc.) The environment MUST be clean before each run.

---

## step 1: understand the project

Before changing anything, read and understand the target artifacts and the project completely.

1. Read ALL target artifact files
2. Read any files they reference or depend on
3. Understand the project's end-to-end flow: input → processing → output
4. Identify which parts of which artifacts have the most influence on output quality
5. Run the project once manually to understand the full lifecycle and output format

Do NOT skip this. You need deep understanding before you can optimize.

---

## step 2: build the eval suite

Convert the user's eval criteria into a structured test. Every check must be binary — pass or fail, no scales.

**Format each eval as:**

```
EVAL [number]: [Short name]
Question: [Yes/no question about the output]
Pass condition: [What "yes" looks like — be specific]
Fail condition: [What triggers a "no"]
```

**Rules for good evals:**
- Binary only. Yes or no. No "rate 1-7" scales. Scales compound variability and give unreliable results.
- Specific enough to be consistent. "Is the output good?" is too vague. "Does the design document address all edge cases mentioned in the task?" is testable.
- Not so narrow that the project games the eval. "Contains fewer than 200 words" will make things optimize for brevity at the expense of everything else.
- 3-6 evals is the sweet spot. More than that and you start chasing eval criteria instead of actual quality.
- For multi-stage projects, evals should assess FINAL output quality, not intermediate steps.

See [references/eval-guide.md](references/eval-guide.md) for detailed examples of good vs bad evals.

**Max score calculation:**
```
max_score = [number of evals] x [runs per experiment]
```

Example: 4 evals x 3 runs = max score of 12.

---

## step 3: generate the live dashboard

Before running any experiments, create a live HTML dashboard at `autooptimize-[project-name]/dashboard.html` and open it in the browser.

The dashboard must:
- Auto-refresh every 10 seconds (reads from results.json)
- Show a score progression line chart (experiment number on X axis, pass rate % on Y axis)
- Show a colored bar for each experiment: green = keep, red = discard, blue = baseline
- Show a table of all experiments with: experiment #, score, pass rate, status, description
- Show per-eval breakdown: which evals pass most/least across all runs
- Show current status: "Running experiment [N]..." or "Idle"
- Use clean styling with soft colors (white background, pastel accents, clean sans-serif font)

Generate the dashboard as a single self-contained HTML file with inline CSS and JavaScript. Use Chart.js loaded from CDN for the line chart. The JS should fetch `results.json` and re-render.

**Open it immediately** after creating it: `open dashboard.html` (macOS) so the user can see it in their browser.

**Update `results.json`** after every experiment so the dashboard stays current. The JSON format:

```json
{
  "project_name": "[name]",
  "status": "running",
  "current_experiment": 3,
  "baseline_score": 70.0,
  "best_score": 90.0,
  "target_artifacts": ["path/to/file1.md", "path/to/file2.md"],
  "experiments": [
    {
      "id": 0,
      "score": 14,
      "max_score": 20,
      "pass_rate": 70.0,
      "status": "baseline",
      "description": "original artifacts - no changes",
      "artifact_changed": null
    }
  ],
  "eval_breakdown": [
    {"name": "Design completeness", "pass_count": 8, "total": 10},
    {"name": "Code correctness", "pass_count": 9, "total": 10}
  ]
}
```

When the run finishes, update `status` to `"complete"`.

---

## step 4: establish baseline

Run the project AS-IS before changing anything. This is experiment #0.

1. **Ask the user what to name the optimization run.** Example: "What should I call this run? (e.g., review-loop-v3, optimized-prompts)"
2. Create a working directory: `autooptimize-[project-name]/` in the project root
3. **Copy ALL target artifacts into the working directory** with their relative paths preserved. These copies are what you mutate. NEVER edit the originals.
4. Also save `.baseline/` copies of every target artifact (identical to originals — this is your revert target)
5. Create `results.tsv`, `results.json`, and `dashboard.html`, then open the dashboard
6. Run the project [N] times using the test scenarios
7. Score every output against every eval
8. Record the baseline score and update both results.tsv and results.json

**results.tsv format (tab-separated):**

```
experiment	score	max_score	pass_rate	status	artifact	description
0	8	12	66.7%	baseline	-	original artifacts - no changes
```

**IMPORTANT:** After establishing baseline, confirm the score with the user before proceeding. If baseline is already 90%+, the project may not need optimization — ask the user if they want to continue.

---

## step 5: run the experiment loop

This is the core optimization loop. Once started, run autonomously until stopped.

### managing multiple artifacts

When optimizing multiple artifacts simultaneously, follow these rules:

- **Change ONE artifact per experiment.** Never change two files in the same experiment — you won't know which change helped.
- **Prioritize by impact.** Start with the artifact that has the most influence on the most-failed evals.
- **Track which artifact changed.** Log the artifact path in results.tsv and results.json for every experiment.
- **Carry forward improvements.** When a mutation is kept, all subsequent experiments build on the improved version.

### the loop

**LOOP:**

1. **Analyze failures.** Look at which evals are failing most. Read the actual outputs that failed. Identify the pattern — is it a missing instruction? An ambiguous directive? A wrong priority? A structural problem?

2. **Form a hypothesis.** Pick ONE thing to change in ONE artifact. Don't change multiple things at once.

   Good mutations:
   - Add a specific instruction that addresses the most common failure
   - Reword an ambiguous instruction to be more explicit
   - Add an anti-pattern ("Do NOT do X") for a recurring mistake
   - Move a buried instruction higher in the artifact (priority = position)
   - Add or improve an example that shows the correct behavior
   - Restructure the flow to prevent a class of errors
   - Remove an instruction that's causing over-optimization for one thing at the expense of others
   - Adjust coordination between artifacts (e.g., align an agent instruction with a prompt template)

   Bad mutations:
   - Rewriting an entire artifact from scratch
   - Adding 10 new rules at once
   - Making artifacts longer without a specific reason
   - Adding vague instructions like "make it better" or "be more careful"
   - Changing the fundamental architecture of the project

3. **Make the change.** Edit the working copy of the target artifact. NEVER touch the originals.

4. **Copy the changed artifact back to its original location** so the project uses the updated version during execution. (After the experiment, if discarded, revert the original too.)

5. **Run the experiment.** Execute the project [N] times with the same test scenarios.

6. **Score it.** Run every output through every eval. Calculate total score.

7. **Decide: keep or discard.**
   - Score improved -> **KEEP.** Log it. Update the working copy as the new baseline for that artifact.
   - Score stayed the same -> **DISCARD.** Revert the artifact to previous version.
   - Score got worse -> **DISCARD.** Revert the artifact to previous version.

8. **Log the result** in results.tsv and update results.json.

9. **Repeat.** Go back to step 1 of the loop.

**NEVER STOP.** Once the loop starts, do not pause to ask the user if you should continue. They may be away from the computer. Run autonomously until:
- The user manually stops you
- You hit the budget cap (if one was set)
- You hit 95%+ pass rate for 3 consecutive experiments (diminishing returns)

**If you run out of ideas:** Re-read the failing outputs. Try combining two previous near-miss mutations. Try a completely different approach to the same problem. Try removing things instead of adding them. Simplification that maintains the score is a win.

---

## step 6: write the changelog

After each experiment (whether kept or discarded), append to `changelog.md`:

```markdown
## Experiment [N] - [keep/discard]

**Score:** [X]/[max] ([percent]%)
**Artifact changed:** [file path]
**Change:** [One sentence describing what was changed]
**Reasoning:** [Why this change was expected to help]
**Result:** [What actually happened - which evals improved/declined]
**Failing outputs:** [Brief description of what still fails, if anything]
```

This changelog is the most valuable artifact. It's a research log that any future agent (or smarter future model) can pick up and continue from.

---

## step 7: deliver results

When the user returns or the loop stops, present:

1. **Score summary:** Baseline score -> Final score (percent improvement)
2. **Total experiments run:** How many mutations were tried
3. **Keep rate:** How many mutations were kept vs discarded
4. **Per-artifact breakdown:** Which artifacts were changed and how many times
5. **Top 3 changes that helped most** (from the changelog)
6. **Remaining failure patterns** (what the project still gets wrong, if anything)
7. **The improved artifacts** (in the working directory - the originals are untouched)
8. **Location of results.tsv and changelog.md** for reference

---

## output format

The skill produces these files in `autooptimize-[project-name]/`:

```
autooptimize-[project-name]/
+-- dashboard.html       # live browser dashboard (auto-refreshes)
+-- results.json         # data file powering the dashboard
+-- results.tsv          # score log for every experiment
+-- changelog.md         # detailed mutation log
+-- .baseline/           # original artifacts before optimization
+-- [artifact copies]    # working copies with relative paths preserved
```

**The original files are NEVER modified permanently.** During experiments, the changed artifact is temporarily copied to its original location for execution, and reverted if discarded. On completion, the user decides whether to apply changes. Do NOT offer to overwrite the originals. The whole point is that the originals stay safe until the user explicitly applies changes.

---

## example: optimizing a Claude Code plugin (review-loop)

**Context gathered:**
- Target artifacts:
  - `review-loop/commands/review-loop.md` (main orchestration)
  - `review-loop/prompts/design-review.md` (design review prompt)
  - `review-loop/prompts/independent-design-review.md` (validation prompt)
  - `review-loop/prompts/code-implement.md` (implementation prompt)
  - `review-loop/prompts/independent-code-review.md` (code validation prompt)
  - `review-loop/AGENTS.md` (agent role definitions)
- Execution method: `/review-loop <task>` in a test project
- Test scenarios:
  1. "Build a CLI todo app with add/remove/list commands"
  2. "Create a REST API rate limiter middleware"
  3. "Implement a file-based key-value store with TTL support"
- Output location: `specs/design.md`, `specs/reviews/`, implemented code on session branch
- Eval criteria:
  1. Does the final design address all requirements from the task?
  2. Does the code compile/run without errors?
  3. Did the review process catch at least one real issue per stage?
  4. Does the final code match the design spec's architecture?
  5. Are edge cases handled in both design and code?
- Runs per experiment: 3 (LLM-heavy workflow)
- Cleanup: reset test project to clean state between runs

**Baseline run (experiment 0):**
Ran review-loop 3 times with 3 different tasks. Scored each against 5 evals. Result: 10/15 (66.7%).
Common failures: design reviews missed edge cases, code implementation deviated from spec on 2/3 runs.

**Experiment 1 - KEEP (12/15, 80%):**
Artifact: `review-loop/prompts/design-review.md`
Change: Added explicit instruction to check for edge case coverage and require listing unaddressed edge cases.
Result: Design review quality improved. Edge case eval went from 1/3 to 3/3.

**Experiment 2 - DISCARD (11/15, 73.3%):**
Artifact: `review-loop/prompts/code-implement.md`
Change: Added "verify your code compiles before finishing."
Result: No improvement. Codex already attempts to run code. The failures were spec deviations, not compilation errors.

**Experiment 3 - KEEP (13/15, 86.7%):**
Artifact: `review-loop/commands/review-loop.md`
Change: Added instruction for Claude's code review to explicitly diff against spec section-by-section.
Result: Spec conformance eval went from 1/3 to 3/3.

---

## how this connects to other workflows

**What feeds into autooptimize:**
- Any project with measurable outputs
- User-defined eval criteria (or help them define evals using the eval guide)

**What autooptimize feeds into:**
- Improved artifacts can be applied back to the project
- The changelog can be passed to future models for continued optimization
- The eval suite can be reused whenever the project is updated

---

## the test

A good autooptimize run:

1. **Started with a baseline** - never changed anything before measuring the starting point
2. **Used binary evals only** - no scales, no vibes, no "rate this 1-10"
3. **Changed one thing at a time** - so you know exactly what helped
4. **Changed one artifact at a time** - so you know exactly where improvement came from
5. **Kept a complete log** - every experiment recorded, kept or discarded
6. **Improved the score** - measurable improvement from baseline to final
7. **Didn't overfit** - the project got better at the actual job, not just at passing specific test scenarios
8. **Ran autonomously** - didn't stop to ask permission between experiments

If the project "passes" all evals but the actual output quality hasn't improved - the evals are bad, not the project. Go back to step 2 and write better evals.
