---
name: interactive-subagent-driven-development
description: Use when executing implementation plans and the human wants to review each task's output before approval — triggers on phrases like "review each task," "human in the loop," "interactive execution," "approve as we go," or when the plan is flagged as high-risk
---

# Interactive Subagent-Driven Development

## Overview

Execute plan by dispatching a fresh subagent per task, running automated reviews (spec compliance + code quality), then pausing for human review before proceeding. Human reviews a generated diff, provides feedback via a FEEDBACK file if changes are needed, and approves to advance.

**Core principle:** Fresh subagent per task + automated gates + human approval gate = high quality with human oversight.

**Announce at start:** "I'm using the interactive-subagent-driven-development skill to implement this plan with human review."

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
3. Ensure `reviews/` directory exists at plan location: `.claude/plans/<plan-name>/reviews/`
4. For each task, capture the current HEAD as the task's `base-sha` BEFORE dispatching the implementer

Note: The `reviews/` directory should be deleted after all tasks are approved and the branch is finished. It exists only as transient state for the review process.

### Per Task

1. Mark task as in_progress and create an `.in-progress-<task-name>` sentinel file in `reviews/`
2. Dispatch implementer subagent with task text + context (fast model for mechanical tasks)
   - If implementer asks questions before/during work, answer them. The human is present — escalate questions to them for decisions the controller can't make.
3. Handle implementer status: DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
4. Run spec compliance review (loop until pass)
5. Run code quality review (loop until pass)
6. Delete the `.in-progress-<task-name>` sentinel, then generate `<task-name>.diff` in `reviews/` directory
7. Tell human: "Task N ready for review. Diff at `reviews/<task-name>.diff`"
8. **WAIT for human response**

### Human Review Outcomes

**Approved** (human signals in chat with "approved", "looks good", "lgtm", "task N approved"):
- Delete `.diff` file
- Mark task complete
- Proceed to next task

**Revisions needed** (human creates `FEEDBACK-<task-name>-r<N>.md`):
- Dispatch feedback subagent (reasoning model) with plan, task, `.diff`, and `FEEDBACK` file
- Feedback subagent addresses all comments, squashes changes into original commit, regenerates `.diff`, deletes `FEEDBACK` file
- Return to step 6 (generate diff, announce, wait)

The round counter in the filename persists across sessions, so the 5-round limit is durable.

**Max 5 feedback rounds** — if exceeded, stop and escalate:
> Task N has gone through 5 revision rounds without approval. The plan may need adjustment — let's discuss whether to re-scope this task or revisit the plan.

## Prompt Templates

This skill reuses the review templates from subagent-driven-development. Dispatch reviewers using the same pattern:

- `../subagent-driven-development/implementer-prompt.md` — Dispatch implementer subagent
- `../subagent-driven-development/spec-reviewer-prompt.md` — Dispatch spec compliance reviewer subagent
- `../subagent-driven-development/code-quality-reviewer-prompt.md` — Dispatch code quality reviewer subagent

The review loop works identically: dispatch reviewer, reviewer finds issues, implementer fixes, re-review, repeat until approved.

## Human Review Gate

After automated reviews pass, the main agent:

1. Generates diff using the base-sha captured before the implementer ran: `git diff <base-sha> HEAD > reviews/<task-name>.diff`
2. Announces: "Task N: `<task-name>` ready for review. Diff at `reviews/<task-name>.diff`"
3. **Waits** — do not proceed until human responds

**Human response types:**
- "approved" / "looks good" / "lgtm" / "task N approved" → delete diff, mark complete, next task
- "ready" / "feedback added" → check for `reviews/FEEDBACK-<task-name>-r<N>.md`
  - If exists → check the round number in the filename. If `FEEDBACK-<task-name>-r5.md`, escalate immediately.
  - Otherwise → dispatch feedback subagent
  - If not → treat as approval

**Review directory:**
```
.claude/plans/<plan-name>/reviews/
├── task-01-auth-middleware.diff
├── .in-progress-task-02-database-schema   # (only while implementer is running)
├── FEEDBACK-task-01-auth-middleware-r1.md  # (only if revisions needed)
├── FEEDBACK-task-01-auth-middleware-r2.md  # (each round increments)
├── task-02-database-schema.diff
└── ...
```

## Feedback Subagent

When human creates a `FEEDBACK-<task-name>-r<N>.md` file, dispatch a subagent with the most capable reasoning model available.

**Context provided to feedback subagent:**
- The plan file
- The specific task from the plan
- The current `<task-name>.diff`
- The human's `FEEDBACK-<task-name>-r<N>.md`
- The base-sha (commit before this task's work began)
- The current round number N (from the filename)

**Feedback subagent's job:**
1. Read and understand every comment in the FEEDBACK file
2. Address each comment with code changes
3. Squash all changes into the original commit: `git reset --soft <base-sha> && git commit -m "original message"`
4. Run automated reviews (spec compliance + code quality) — loop until pass
5. Regenerate diff: `git diff <base-sha> HEAD > reviews/<task-name>.diff`
6. Delete `FEEDBACK-<task-name>-r<N>.md`
7. Report back

The round counter in the filename persists across sessions, so the 5-round limit is durable.

**After feedback subagent completes:**
- Main agent tells human: "Task N revised. Updated diff at `reviews/<task-name>.diff`"
- Returns to waiting state

If the feedback subagent fails (crash, timeout): Re-dispatch once. If it fails again, escalate to human with the FEEDBACK file contents and the subagent's error.

## Model Selection

**First-pass implementer:** Use the least powerful model that can handle the task. See subagent-driven-development model selection for complexity signals.

**Feedback subagent:** Always use the most capable reasoning model available. Human feedback means the first pass wasn't sufficient — revisions require strong reasoning to understand and address nuanced comments correctly.

## Review Round Limit

Maximum 5 feedback rounds per task. If a task cycles through 5 revision rounds without approval, stop and escalate:

> Task N has gone through 5 revision rounds without approval. The plan may need adjustment — let's discuss whether to re-scope this task or revisit the plan.

Do not start a 6th round without explicit human direction.

## Cross-Session Resume

On skill start, if `reviews/` directory exists with `.diff` files, a plan is in progress. Resume from the first task whose diff still exists (not yet approved/deleted). No extra state file needed — the presence/absence of diff files is the state.

If an `.in-progress-<task-name>` file exists without a corresponding `.diff`, the task was interrupted mid-execution. Re-execute that task from scratch (the original subagent session is lost).

## Handling Implementer Status

Same status handling and escalation path as subagent-driven-development. See that skill for the full table.

Key difference: BLOCKED status always escalates to the human immediately (since the human is actively present for review).

## Red Flags

**Never:**
- Proceed past a task without human approval
- Skip automated reviews (spec compliance OR code quality)
- Accept "close enough" on human feedback — address every comment
- Exceed 5 feedback rounds without escalation
- Start implementation on main/master branch without explicit user consent
- Delete FEEDBACK file before addressing all comments
- Dispatch multiple implementation subagents in parallel
- All Red Flags from subagent-driven-development apply here as well — see that skill for the full list. Key ones: provide full task text (don't make subagent read plan), never start code quality review before spec compliance passes, never let self-review replace actual review.

**If human creates a FEEDBACK file:**
- Address every comment before regenerating diff
- Use the most capable reasoning model for revisions

**If human is unresponsive:**
- Do not proceed. Wait for explicit approval or feedback.
- Do not interpret silence as approval.

## After All Tasks

Since the human has approved each task individually, the final code reviewer subagent from subagent-driven-development is skipped. Proceed directly to finishing-a-development-branch.

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
