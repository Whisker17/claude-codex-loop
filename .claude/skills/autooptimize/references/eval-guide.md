# Eval Guide

How to write eval criteria that actually improve your project instead of giving you false confidence.

---

## the golden rule

Every eval must be a yes/no question. Not a scale. Not a vibe check. Binary.

Why: Scales compound variability. If you have 4 evals scored 1-7, your total score has massive variance across runs. Binary evals give you a reliable signal.

---

## good evals vs bad evals

### Text/copy outputs (newsletters, tweets, emails, landing pages)

**Bad evals:**
- "Is the writing good?" (too vague)
- "Rate the engagement potential 1-10" (scale = unreliable)
- "Does it sound like a human?" (subjective, inconsistent scoring)

**Good evals:**
- "Does the output contain zero phrases from this banned list: [game-changer, here's the kicker, the best part, level up]?" (binary, specific)
- "Does the opening sentence reference a specific time, place, or sensory detail?" (binary, checkable)
- "Is the output between 150-400 words?" (binary, measurable)
- "Does it end with a specific CTA that tells the reader exactly what to do next?" (binary, structural)

### Visual/design outputs (diagrams, images, slides)

**Bad evals:**
- "Does it look professional?" (subjective)
- "Rate the visual quality 1-5" (scale)

**Good evals:**
- "Is all text in the image legible with no truncated or overlapping words?" (binary, specific)
- "Does the color palette use only soft/pastel tones?" (binary, checkable)
- "Is the layout linear with no scattered elements?" (binary, structural)

### Code/technical outputs (code generation, configs, scripts)

**Bad evals:**
- "Is the code clean?" (subjective)
- "Does it follow best practices?" (vague)

**Good evals:**
- "Does the code run without errors?" (binary, testable)
- "Does the output contain zero TODO or placeholder comments?" (binary, greppable)
- "Does the code include error handling for all external calls?" (binary, structural)

### Document outputs (proposals, reports, specs)

**Bad evals:**
- "Is it comprehensive?" (compared to what?)
- "Does it address the client's needs?" (too open-ended)

**Good evals:**
- "Does the document contain all required sections: [list them]?" (binary, structural)
- "Is every claim backed by a specific number, date, or source?" (binary, checkable)
- "Does the executive summary fit in one paragraph of 3 sentences or fewer?" (binary, countable)

### Multi-stage pipeline outputs (review loops, CI/CD, agent workflows)

**Bad evals:**
- "Did the pipeline work?" (too binary at the wrong level)
- "Is the output high quality?" (vague)
- "Did the review process help?" (unmeasurable)

**Good evals:**
- "Did the review process identify at least one substantive issue that was then fixed?" (binary, verifiable from review artifacts)
- "Does the final output satisfy all explicit requirements stated in the input task?" (binary, checkable against task description)
- "Did the pipeline complete all stages without timeout or crash?" (binary, observable from logs)
- "Does the final code pass its own tests (if tests were generated)?" (binary, executable)
- "Is the final design/code free of issues rated 'critical' or 'high' in the last review round?" (binary, checkable from review files)
- "Did independent validation find fewer issues than regular review?" (binary, countable from review files)

**Key principle for pipelines:** Eval the FINAL output, not intermediate steps. The review process is a means, not the end. If the final design is solid and the final code works, it doesn't matter if round 3 had a hiccup.

---

## common mistakes

### 1. Too many evals
More than 6 evals and the optimization starts gaming them. Like a student who memorizes answers without understanding the material.

**Fix:** Pick the 3-6 checks that matter most.

### 2. Too narrow/rigid
"Must contain exactly 3 bullet points" creates outputs that technically pass but produce weird, stilted results.

**Fix:** Evals should check for qualities you care about, not arbitrary structural constraints.

### 3. Overlapping evals
If eval 1 is "Is the text grammatically correct?" and eval 4 is "Are there any spelling errors?" these overlap and you're double-counting.

**Fix:** Each eval should test something distinct.

### 4. Unmeasurable by an agent
"Would a human find this engaging?" - an agent can't reliably answer this.

**Fix:** Translate subjective qualities into observable signals.

### 5. Evaluating process instead of outcome (pipeline-specific)
"Did the reviewer write detailed feedback?" evaluates the review process, not the final output. The review could be detailed but miss the real problem.

**Fix:** Eval the final artifacts. If they're good, the process worked regardless of how it looked along the way.

---

## writing your evals: the 3-question test

Before finalizing an eval, ask:

1. **Could two different agents score the same output and agree?** If not, the eval is too subjective.
2. **Could the project game this eval without actually improving?** If yes, the eval is too narrow.
3. **Does this eval test something the user actually cares about?** If not, drop it.

---

## template

Copy this for each eval:

```
EVAL [N]: [Short name]
Question: [Yes/no question]
Pass: [What "yes" looks like - one sentence, specific]
Fail: [What triggers "no" - one sentence, specific]
```

Example for a pipeline project:

```
EVAL 1: Requirements coverage
Question: Does the final output address every explicit requirement stated in the task description?
Pass: Each requirement can be traced to a specific section of the design or a specific function in the code
Fail: Any stated requirement is missing, only partially addressed, or handled with a TODO/placeholder
```
