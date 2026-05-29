---
name: interactive-subagent-driven-development
description: Use when executing implementation plans and the human wants to review each task's output before approval — triggers on phrases like "review each task," "human in the loop," "interactive execution," "approve as we go," "githuman," or when the plan is flagged as high-risk
---

# Interactive Subagent-Driven Development

## Overview

Execute a plan by dispatching a fresh subagent per task, running automated reviews (spec compliance + code quality), then pausing for human review via **githuman** before proceeding. Subagents leave their work **staged but uncommitted**; a thin review subagent runs `githuman ask` so the human reviews the staged changes in githuman's UI. The work is **committed only after the human approves**. If the human requests changes, a feedback subagent addresses them and the review repeats.

**Core principle:** Fresh subagent per task + automated gates + human approval via githuman, committing only approved work = high quality, human oversight, and a clean per-task history.

**Announce at start:** "I'm using the interactive-subagent-driven-development skill to implement this plan with human review via githuman."

**Prerequisite:** `githuman` must be installed and on PATH (https://github.com/mcollina/githuman). Verify with `githuman --help` during setup.

## When to Use

- Human wants to review each task before it's marked complete
- High-risk plans (auth, payments, data migration, irreversible changes)
- Human explicitly requests "interactive execution" or "review each step"
- Human is actively present and wants oversight

**Not for:**
- Autonomous execution (use subagent-driven-development)
- Batch execution in parallel session (use executing-plans)
- Human is unavailable for review between tasks

| Scenario | Use |
|----------|-----|
| Human wants to review each task | interactive-subagent-driven-development |
| Autonomous execution, no human present | subagent-driven-development |
| Parallel session, batch execution | executing-plans |

## The Process

### Setup
1. Read plan file, extract all tasks with full text
2. Create TodoWrite for all tasks
3. Verify `githuman` is available: `githuman --help`
4. Confirm work is on a feature branch (not main/master). If on main/master, get explicit user consent before proceeding.

**State model:** There is no state directory and no per-task `base-sha` capture. Git itself is the state — a **committed** task is approved/done, so HEAD always points at the last approved task. The diff under review is always `git diff HEAD`. An **uncommitted (dirty)** working tree means the current task is mid-review.

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

## Prompt Templates

This skill reuses the review templates from subagent-driven-development, with **per-dispatch overrides** (the shared files are NOT edited — they still serve subagent-driven-development's commit-per-task model):

- `../subagent-driven-development/implementer-prompt.md` — dispatch implementer. **Override:** ignore the prompt's "Commit your work" step — do NOT commit; leave changes in the working tree.
- `../subagent-driven-development/spec-reviewer-prompt.md` — spec compliance reviewer. **Override:** there is no task commit; review `git diff HEAD` (all changes vs the last commit).
- `../subagent-driven-development/code-quality-reviewer-prompt.md` — code quality reviewer. **Override:** pass `BASE_SHA = HEAD` and review `git diff HEAD` instead of a two-commit range.

The review loop works identically: dispatch reviewer, reviewer finds issues, implementer fixes (still without committing), re-review, repeat until approved.

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

## Model Selection

- **Implementer:** the least powerful model that can handle the task. See subagent-driven-development model selection for complexity signals.
- **Thin review subagent:** a cheap model — staging, running `githuman ask`, parsing JSON, and committing on approval are mechanical.
- **Feedback subagent:** always the most capable reasoning model available. Human feedback means the first pass wasn't sufficient; revisions require strong reasoning to understand and address nuanced comments.

## Review Round Limit

Maximum 5 feedback rounds per task. The round counter is tracked **in-session by the controller** — git is the only persisted state, so if a session dies mid-revision the counter resets to round 1. This is acceptable because the full review thread remains visible in githuman's UI for the human's reference.

If a task cycles through 5 rounds without approval, stop and escalate:

> Task N has gone through 5 revision rounds without approval. The plan may need adjustment — let's discuss whether to re-scope this task or revisit the plan.

Do not start a 6th round without explicit human direction.

## Cross-Session Resume

Git itself is the state — there are no state files or directories to inspect.

- A task whose work is **committed** → approved/done.
- A **dirty (uncommitted)** working tree → the current task is mid-review. Resume by re-running the automated gates (spec → quality) and re-invoking the thin review subagent.
- A **clean** working tree with tasks remaining → the next task hasn't started; begin it.

The in-session round counter does not survive a restart. On resume, treat a dirty working tree as round 1 of the current task — githuman retains the prior review thread for the human's reference.

## Handling Implementer Status

Same status handling and escalation path as subagent-driven-development. See that skill for the full table.

Key difference: BLOCKED status always escalates to the human immediately (since the human is actively present for review).

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

## After All Tasks

Each task was committed only after the human approved it, so the branch already contains a clean, per-task, human-approved history. The final holistic code reviewer subagent from subagent-driven-development is skipped (the human reviewed each task individually). Proceed directly to finishing-a-development-branch.

## Integration

**Required workflow skills:**
- **superpowers:using-git-worktrees** - Ensures isolated workspace (creates one or verifies existing)
- **superpowers:writing-plans** - Creates the plan this skill executes
- **superpowers:finishing-a-development-branch** - Complete development after all tasks

**Subagents should use:**
- **superpowers:test-driven-development** - Subagents follow TDD for each task

No final code reviewer subagent — human reviewed each task individually, replacing the holistic review.

**Alternative workflows:**
- **superpowers:subagent-driven-development** - Autonomous execution (no human review between tasks)
- **superpowers:executing-plans** - Parallel session execution
