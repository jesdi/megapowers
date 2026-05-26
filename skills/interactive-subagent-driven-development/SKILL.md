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

## The Process

### Setup
1. Read plan file, extract all tasks with full text
2. Create TodoWrite for all tasks
3. Ensure `reviews/` directory exists at plan location: `.claude/plans/<plan-name>/reviews/`

### Per Task

1. Mark task as in_progress
2. Dispatch implementer subagent with task text + context (fast model for mechanical tasks)
3. Handle implementer status: DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
4. Run spec compliance review (loop until pass)
5. Run code quality review (loop until pass)
6. Generate `<task-name>.diff` in `reviews/` directory
7. Tell human: "Task N ready for review. Diff at `reviews/<task-name>.diff`"
8. **WAIT for human response**

### Human Review Outcomes

**Approved** (human signals in chat with "approved", "looks good", "lgtm", "task N approved"):
- Delete `.diff` file
- Mark task complete
- Proceed to next task

**Revisions needed** (human creates `FEEDBACK-<task-name>.md`):
- Dispatch feedback subagent (reasoning model) with plan, task, `.diff`, and `FEEDBACK` file
- Feedback subagent addresses all comments, squashes changes into original commit, regenerates `.diff`, deletes `FEEDBACK` file
- Return to step 6 (generate diff, announce, wait)

**Max 5 feedback rounds** — if exceeded, stop and escalate:
> Task N has gone through 5 revision rounds without approval. The plan may need adjustment — let's discuss whether to re-scope this task or revisit the plan.

## Human Review Gate

After automated reviews pass, the main agent:

1. Generates diff: `git diff <base-sha> HEAD > reviews/<task-name>.diff`
2. Announces: "Task N: `<task-name>` ready for review. Diff at `reviews/<task-name>.diff`"
3. **Waits** — do not proceed until human responds

**Human response types:**
- "approved" / "looks good" / "lgtm" / "task N approved" → delete diff, mark complete, next task
- "ready" / "feedback added" → check for `reviews/FEEDBACK-<task-name>.md`
  - If exists → dispatch feedback subagent
  - If not → treat as approval

**Review directory:**
```
.claude/plans/<plan-name>/reviews/
├── task-01-auth-middleware.diff
├── FEEDBACK-task-01-auth-middleware.md    # (only if revisions needed)
├── task-02-database-schema.diff
└── ...
```

## Feedback Subagent

When human creates a `FEEDBACK-<task-name>.md` file, dispatch a subagent with the most capable reasoning model available.

**Context provided to feedback subagent:**
- The plan file
- The specific task from the plan
- The current `<task-name>.diff`
- The human's `FEEDBACK-<task-name>.md`
- The current HEAD SHA (base for diff regeneration)

**Feedback subagent's job:**
1. Read and understand every comment in the FEEDBACK file
2. Address each comment with code changes
3. Squash all changes into the original commit: `git reset --soft <original-base> && git commit -m "original message"`
4. Run automated reviews (spec compliance + code quality) — loop until pass
5. Regenerate diff: `git diff <base-sha> HEAD > reviews/<task-name>.diff`
6. Delete `FEEDBACK-<task-name>.md`
7. Report back

**After feedback subagent completes:**
- Main agent tells human: "Task N revised. Updated diff at `reviews/<task-name>.diff`"
- Returns to waiting state

## Model Selection

**First-pass implementer:** Use the least powerful model that can handle the task. See subagent-driven-development model selection for complexity signals.

**Feedback subagent:** Always use the most capable reasoning model available. Human feedback means the first pass wasn't sufficient — revisions require strong reasoning to understand and address nuanced comments correctly.

## Review Round Limit

Maximum 5 feedback rounds per task. If a task cycles through 5 revision rounds without approval, stop and escalate:

> Task N has gone through 5 revision rounds without approval. The plan may need adjustment — let's discuss whether to re-scope this task or revisit the plan.

Do not start a 6th round without explicit human direction.

## Cross-Session Resume

On skill start, if `reviews/` directory exists with `.diff` files, a plan is in progress. Resume from the first task whose diff still exists (not yet approved/deleted). No extra state file needed — the presence/absence of diff files is the state.

## Handling Implementer Status

Same as subagent-driven-development:

- **DONE:** Proceed to spec compliance review
- **DONE_WITH_CONCERNS:** Read concerns before proceeding. If about correctness or scope, address before review. If observations (e.g., "file is getting large"), note them and proceed.
- **NEEDS_CONTEXT:** Provide missing context, re-dispatch implementer
- **BLOCKED:** Escalate to human. Do not force retry without changes.

## Red Flags

**Never:**
- Proceed past a task without human approval
- Skip automated reviews (spec compliance OR code quality)
- Accept "close enough" on human feedback — address every comment
- Exceed 5 feedback rounds without escalation
- Start implementation on main/master branch without explicit user consent
- Delete FEEDBACK file before addressing all comments
- Dispatch multiple implementation subagents in parallel

**If human creates a FEEDBACK file:**
- Address every comment before regenerating diff
- Use the most capable reasoning model for revisions

**If human is unresponsive:**
- Do not proceed. Wait for explicit approval or feedback.
- Do not interpret silence as approval.

## Integration

**Required workflow skills:**
- **superpowers:using-git-worktrees** - Ensures isolated workspace (creates one or verifies existing)
- **superpowers:writing-plans** - Creates the plan this skill executes
- **superpowers:finishing-a-development-branch** - Complete development after all tasks

**Subagents should use:**
- **superpowers:test-driven-development** - Subagents follow TDD for each task

**Alternative workflows:**
- **superpowers:subagent-driven-development** - Autonomous execution (no human review between tasks)
- **superpowers:executing-plans** - Parallel session execution
