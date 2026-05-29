# githuman Interactive Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `skills/interactive-subagent-driven-development/SKILL.md` so the human review gate runs through [githuman](https://github.com/mcollina/githuman) — subagents leave work staged (uncommitted), a thin review subagent runs `githuman ask`, and work is committed only after the human approves.

**Architecture:** Replace the commit-per-task + `.diff`-file + `FEEDBACK`-file machinery with: (1) subagents never commit, (2) a cheap "thin review subagent" owns `git add` + `githuman ask --json` + commit-on-approval, (3) githuman comments route subagent → `/tmp/githuman-<task>-r<N>.md` → feedback subagent so the controller never reads raw githuman output, (4) git itself is the only persisted state (committed = done, dirty = mid-review). The controller only orchestrates and branches on compact one-line results.

**Tech Stack:** Markdown skill content (behavior-shaping prose); `githuman` CLI; git.

---

## Design Decisions (locked in during grilling)

1. **Commit timing:** No commit until human approval. Approved work is committed → HEAD is always the clean per-task boundary.
2. **Feedback channel:** `githuman ask --json`, branch on `status` (`approved` / `changes requested`). No `FEEDBACK` files.
3. **State & round counter:** Git is the state. Round counter is in-session only. No state files, no `reviews/` directory.
4. **Shared prompts:** The shared `subagent-driven-development` prompt files are NOT edited. Overrides are applied per-dispatch.
5. **Automated gates:** Keep spec + code-quality gates per task, before githuman. Both review `git diff HEAD`.
6. **Git/githuman ownership:** A thin review subagent (cheap model) owns `git add` + `githuman ask` + commit-on-approval. Comments route via `/tmp` handoff file; controller never reads them.
7. **Roles:** implementer / spec / quality / thin-review / feedback all stay subagents; controller only orchestrates.
8. **Models:** implementer = cheap; thin review subagent = cheap; feedback subagent = strong reasoning.

## File Structure

- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the only file changed)
- Do NOT touch: `skills/subagent-driven-development/implementer-prompt.md`, `spec-reviewer-prompt.md`, `code-quality-reviewer-prompt.md` (shared; overridden at dispatch time)

Each task below replaces one section of `SKILL.md` with exact target content. Apply them top-to-bottom; the final task is a whole-file consistency pass.

---

### Task 1: Rewrite the Overview section

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `## Overview` section, lines ~8-14)

- [ ] **Step 1: Replace the Overview section with:**

```markdown
## Overview

Execute a plan by dispatching a fresh subagent per task, running automated reviews (spec compliance + code quality), then pausing for human review via **githuman** before proceeding. Subagents leave their work **staged but uncommitted**; a thin review subagent runs `githuman ask` so the human reviews the staged changes in githuman's UI. The work is **committed only after the human approves**. If the human requests changes, a feedback subagent addresses them and the review repeats.

**Core principle:** Fresh subagent per task + automated gates + human approval via githuman, committing only approved work = high quality, human oversight, and a clean per-task history.

**Announce at start:** "I'm using the interactive-subagent-driven-development skill to implement this plan with human review via githuman."

**Prerequisite:** `githuman` must be installed and on PATH (https://github.com/mcollina/githuman). Verify with `githuman --help` during setup.
```

- [ ] **Step 2: Verify** — Read the section back. Confirm it no longer mentions "generated diff" or "FEEDBACK file" and that it introduces githuman, staged-not-committed, and commit-on-approval.

---

### Task 2: Rewrite Setup (remove reviews/ dir and base-sha)

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `### Setup` block, lines ~36-42)

- [ ] **Step 1: Replace the entire Setup block (steps 1-4 and the trailing Note) with:**

```markdown
### Setup
1. Read plan file, extract all tasks with full text
2. Create TodoWrite for all tasks
3. Verify `githuman` is available: `githuman --help`
4. Confirm work is on a feature branch (not main/master). If on main/master, get explicit user consent before proceeding.

**State model:** There is no state directory and no per-task `base-sha` capture. Git itself is the state — a **committed** task is approved/done, so HEAD always points at the last approved task. The diff under review is always `git diff HEAD`. An **uncommitted (dirty)** working tree means the current task is mid-review.
```

- [ ] **Step 2: Verify** — Confirm `reviews/` directory creation and `base-sha` capture are gone, and the githuman availability check is present.

---

### Task 3: Rewrite the Per Task list

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `### Per Task` block, lines ~44-54)

- [ ] **Step 1: Replace the Per Task block with:**

```markdown
### Per Task

1. Mark the task as in_progress
2. Dispatch the implementer subagent with task text + context (cheap model for mechanical tasks). **Override:** "Do NOT commit — leave your changes in the working tree; the controller handles staging, review, and commit."
   - If the implementer asks questions before/during work, answer them. The human is present — escalate decisions the controller can't make.
3. Handle implementer status: DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
4. Run spec compliance review (loop until pass) — reviewer diffs `git diff HEAD`
5. Run code quality review (loop until pass) — reviewer diffs `git diff HEAD`
6. Dispatch the **thin review subagent** (see Human Review Gate) to stage, run `githuman ask`, and commit on approval
7. Branch on the subagent's compact result:
   - `APPROVED @ <sha>` → mark task complete, proceed to the next task
   - `CHANGES_REQUESTED → <path>` → dispatch the feedback subagent (see Feedback Subagent), then return to step 4
```

- [ ] **Step 2: Verify** — Confirm the old diff-generation step ("generate `<task-name>.diff`") and "WAIT for human response" steps are gone, replaced by the thin-review-subagent dispatch and compact-result branching.

---

### Task 4: Add overrides to Prompt Templates

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `## Prompt Templates` section, lines ~73-81)

- [ ] **Step 1: Replace the Prompt Templates section with:**

```markdown
## Prompt Templates

This skill reuses the review templates from subagent-driven-development, with **per-dispatch overrides** (the shared files are NOT edited — they still serve subagent-driven-development's commit-per-task model):

- `../subagent-driven-development/implementer-prompt.md` — dispatch implementer. **Override:** ignore the prompt's "Commit your work" step — do NOT commit; leave changes in the working tree.
- `../subagent-driven-development/spec-reviewer-prompt.md` — spec compliance reviewer. **Override:** there is no task commit; review `git diff HEAD` (all changes vs the last commit).
- `../subagent-driven-development/code-quality-reviewer-prompt.md` — code quality reviewer. **Override:** pass `BASE_SHA = HEAD` and review `git diff HEAD` instead of a two-commit range.

The review loop works identically: dispatch reviewer, reviewer finds issues, implementer fixes (still without committing), re-review, repeat until approved.
```

- [ ] **Step 2: Verify** — Confirm all three templates have an explicit override and the note that shared files are not edited.

---

### Task 5: Rewrite Human Review Gate as the Thin Review Subagent

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `## Human Review Gate` section AND the `### Human Review Outcomes` block — consolidate them; lines ~56-107)

- [ ] **Step 1: Delete the `### Human Review Outcomes` block (lines ~56-71) and the `## Human Review Gate` section (lines ~83-107, including the `Review directory:` tree), and replace both with a single new section:**

```markdown
## Human Review Gate (Thin Review Subagent)

After both automated reviews pass, the controller dispatches a **thin review subagent** (cheap model — the work is mechanical). It does all git and githuman work so the controller's context stays lean. It:

1. Stages all task changes: `git add -A`
2. Runs `githuman ask --json "Task N: <task-name> — <one-line summary>"` and **waits** — this blocks until the human clicks "Continue assistant" in githuman's UI. `githuman ask` starts or reuses the githuman server automatically; no separate serve step is needed.
3. Parses the JSON `status`:
   - **`approved`** → commit the staged work: `git commit -m "<task message>"`, then return exactly: `APPROVED @ <commit-sha>`
   - **`changes requested`** → distill the returned todos/comments into `/tmp/githuman-<task-name>-r<N>.md`, then return exactly: `CHANGES_REQUESTED → /tmp/githuman-<task-name>-r<N>.md`
4. Returns **only** that compact line — never the raw JSON.

The commit message is derived from the task (its title/name from the plan, optionally the description) — the same message the implementer would have written, deferred until after approval.

**Controller's role:** The controller never reads the raw githuman output and never runs git itself. It sees only `APPROVED @ <sha>` (→ next task) or `CHANGES_REQUESTED → <path>` (→ pass the path to the feedback subagent). githuman comments flow **thin-review-subagent → `/tmp` file → feedback-subagent**, never through the controller's persistent context.
```

- [ ] **Step 2: Verify** — Confirm there is exactly one human-review section, it describes the thin review subagent + `githuman ask --json` + commit-on-approval + `/tmp` handoff, and the old `reviews/` directory tree diagram is gone.

---

### Task 6: Rewrite the Feedback Subagent section

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `## Feedback Subagent` section, lines ~109-136)

- [ ] **Step 1: Replace the Feedback Subagent section with:**

```markdown
## Feedback Subagent

When the thin review subagent returns `CHANGES_REQUESTED`, the controller dispatches a feedback subagent with the **most capable reasoning model available** (human feedback means the first pass wasn't sufficient — revisions require strong reasoning to address nuanced comments correctly).

**Context provided to the feedback subagent:**
- The plan file
- The specific task from the plan
- The `/tmp/githuman-<task-name>-r<N>.md` handoff file **path** (the subagent reads the human's comments/todos from it — the controller does not read or relay the content)
- The current round number N
- **Override:** "Address every comment. Leave your changes in the working tree — do NOT commit and do NOT stage-and-commit. The controller re-runs the automated reviews and re-invokes githuman."

**Feedback subagent's job:**
1. Read the handoff file and understand every comment/todo
2. Address each comment with code changes in the working tree
3. Leave changes uncommitted (do not commit, do not squash)
4. Report back

**After the feedback subagent completes:** the controller returns to the automated review gates (spec → quality, each looping until pass), then re-dispatches the thin review subagent for round N+1.

If the feedback subagent fails (crash, timeout): re-dispatch once. If it fails again, escalate to the human with the handoff file contents and the subagent's error.

The `/tmp` handoff files live outside the repo, so they are never staged or committed and the OS reclaims them — no cleanup step.
```

- [ ] **Step 2: Verify** — Confirm the old `git reset --soft <base-sha> && git commit` squash step and diff-regeneration step are gone, the subagent reads from `/tmp` by path, and it leaves work uncommitted.

---

### Task 7: Update Model Selection

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `## Model Selection` section, lines ~138-142)

- [ ] **Step 1: Replace the Model Selection section with:**

```markdown
## Model Selection

- **Implementer:** the least powerful model that can handle the task. See subagent-driven-development model selection for complexity signals.
- **Thin review subagent:** a cheap model — staging, running `githuman ask`, parsing JSON, and committing on approval are mechanical.
- **Feedback subagent:** always the most capable reasoning model available. Human feedback means the first pass wasn't sufficient; revisions require strong reasoning to understand and address nuanced comments.
```

- [ ] **Step 2: Verify** — Confirm the thin review subagent is listed as cheap and the feedback subagent as the strong model.

---

### Task 8: Update Review Round Limit (in-session counter)

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `## Review Round Limit` section, lines ~144-150)

- [ ] **Step 1: Replace the Review Round Limit section with:**

```markdown
## Review Round Limit

Maximum 5 feedback rounds per task. The round counter is tracked **in-session by the controller** — git is the only persisted state, so if a session dies mid-revision the counter resets to round 1. This is acceptable because the full review thread remains visible in githuman's UI for the human's reference.

If a task cycles through 5 rounds without approval, stop and escalate:

> Task N has gone through 5 revision rounds without approval. The plan may need adjustment — let's discuss whether to re-scope this task or revisit the plan.

Do not start a 6th round without explicit human direction.
```

- [ ] **Step 2: Verify** — Confirm the counter is described as in-session (not filename-based) and the 5-round escalation message is intact. Also remove the two stale "The round counter in the filename persists across sessions..." sentences elsewhere in the file (one was in the old Per Task / Human Review Outcomes area, one in the old Feedback Subagent section) — confirm Tasks 3 and 6 already removed them.

---

### Task 9: Rewrite Cross-Session Resume (git-state based)

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `## Cross-Session Resume` section, lines ~152-156)

- [ ] **Step 1: Replace the Cross-Session Resume section with:**

```markdown
## Cross-Session Resume

Git itself is the state — there are no state files or directories to inspect.

- A task whose work is **committed** → approved/done.
- A **dirty (uncommitted)** working tree → the current task is mid-review. Resume by re-running the automated gates (spec → quality) and re-invoking the thin review subagent.
- A **clean** working tree with tasks remaining → the next task hasn't started; begin it.

The in-session round counter does not survive a restart. On resume, treat a dirty working tree as round 1 of the current task — githuman retains the prior review thread for the human's reference.
```

- [ ] **Step 2: Verify** — Confirm references to `.diff` files and `.in-progress-<task-name>` sentinels as resume state are gone, replaced by committed-vs-dirty git state.

---

### Task 10: Update Red Flags

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `## Red Flags` section, lines ~164-182)

- [ ] **Step 1: Replace the Red Flags section with:**

```markdown
## Red Flags

**Never:**
- Commit work before the human approves it
- Commit unreviewed work (skip the githuman gate)
- Proceed past a task without human approval
- Skip automated reviews (spec compliance OR code quality)
- Read the raw githuman output in the controller instead of routing comments via the `/tmp` handoff file
- Let the implementer or feedback subagent commit (or stage-and-commit) — only the thin review subagent commits, and only after approval
- Accept "close enough" on human feedback — address every comment
- Exceed 5 feedback rounds without escalation
- Start implementation on main/master without explicit user consent
- Dispatch multiple implementation subagents in parallel
- All Red Flags from subagent-driven-development apply here as well — see that skill for the full list. Key ones: provide full task text (don't make the subagent read the plan), never start code quality review before spec compliance passes, never let self-review replace actual review.

**If the human requests changes:**
- Address every comment before re-invoking githuman
- Use the most capable reasoning model for revisions

**If the human is unresponsive:**
- `githuman ask` blocks until the human acts. Do not work around the gate, and do not interpret the absence of a response as approval.
```

- [ ] **Step 2: Verify** — Confirm the new commit-discipline red flags are present and the old "Delete FEEDBACK file before addressing all comments" line is gone.

---

### Task 11: Update After All Tasks

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (the `## After All Tasks` section, lines ~184-186)

- [ ] **Step 1: Replace the After All Tasks section with:**

```markdown
## After All Tasks

Each task was committed only after the human approved it, so the branch already contains a clean, per-task, human-approved history. The final holistic code reviewer subagent from subagent-driven-development is skipped (the human reviewed each task individually). Proceed directly to finishing-a-development-branch.
```

- [ ] **Step 2: Verify** — Confirm it explains the branch already has per-task approved commits and points to finishing-a-development-branch.

---

### Task 12: Whole-file consistency pass

**Files:**
- Modify: `skills/interactive-subagent-driven-development/SKILL.md` (entire file)

- [ ] **Step 1: Read the entire file top to bottom.**

- [ ] **Step 2: Grep for stale terms and confirm zero hits (except intentional historical mentions):**

```bash
grep -n -i "\.diff\|FEEDBACK-\|reviews/\|base-sha\|\.in-progress\|reset --soft\|filename persists" skills/interactive-subagent-driven-development/SKILL.md
```

Expected: no matches. Any match is a leftover from the old model — fix it.

- [ ] **Step 3: Confirm cross-section consistency:**
  - The compact result strings (`APPROVED @ <sha>`, `CHANGES_REQUESTED → <path>`) are identical everywhere they appear (Per Task step 7, Human Review Gate, Feedback Subagent trigger).
  - The `/tmp/githuman-<task-name>-r<N>.md` path format is identical in the Human Review Gate and Feedback Subagent sections.
  - Model assignments match between Model Selection and the per-section mentions (implementer cheap, thin review cheap, feedback strong).

- [ ] **Step 3b: Optionally check the `description:` frontmatter** still reflects the skill (no edit required, but add the keyword `githuman` to the trigger list if it reads naturally).

- [ ] **Step 4: Confirm the Integration section** (lines ~188-203) still lists the required workflow skills (using-git-worktrees, writing-plans, finishing-a-development-branch), the TDD sub-skill note, and the alternative workflows — these are unchanged by this plan and should remain intact.

---

## Self-Review

**Spec coverage:** Every grilling decision maps to a task — Q1 commit-on-approval (Tasks 3, 5), Q2 `--json`/status branching (Task 5), Q3 git-state + in-session counter + no files (Tasks 2, 8, 9), Q4 prompt overrides (Tasks 3, 4), Q5 automated gates kept (Task 3), Q6 thin review subagent + `/tmp` handoff (Tasks 5, 6), models (Task 7), red flags (Task 10).

**Placeholder scan:** Each task contains the exact replacement markdown — no TBD/TODO/placeholder content.

**Consistency:** Compact result strings and the `/tmp` path format are defined once and reused; Task 12 explicitly checks they match across sections. Shared prompt files are never edited (Task 4 documents the override approach instead).
