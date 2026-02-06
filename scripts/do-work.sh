#!/usr/bin/env bash
#
# Pick the top task from beads and invoke Claude to do the work.
#
# The script handles task picking, reservation, and git worktree management.
# Claude receives a clean prompt focused on the work itself.
#
# Usage: do-work.sh [options] [repo-root]
#
# Options:
#   --silence-claude       Suppress Claude's output
#   --make-work-limit N    Number of issues to create when no tasks (default: 1)
#   --cycles N             Number of make-work cycles (default: 1)
#
# Workflow:
# 1. Pick and claim a task from beads
# 2. Create a git worktree with a branch for the task
# 3. Run Claude in the worktree
# 4. Merge the branch back to main
# 5. Clean up the worktree
# 6. When no tasks left, call make-work.sh to create more
# 7. Repeat for specified number of cycles
#

set -e

# Parse arguments
SILENCE_CLAUDE=false
MAKE_WORK_LIMIT=5
CYCLES=0
REPO_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --silence-claude)
      SILENCE_CLAUDE=true
      shift
      ;;
    --make-work-limit)
      MAKE_WORK_LIMIT="$2"
      shift 2
      ;;
    --cycles)
      CYCLES="$2"
      shift 2
      ;;
    *)
      REPO_ARG="$1"
      shift
      ;;
  esac
done

REPO_ROOT="${REPO_ARG:-$(dirname "$0")/..}"
cd "$REPO_ROOT" || exit 1
REPO_ROOT=$(pwd)

SCRIPT_DIR="$REPO_ROOT/scripts"
PROJECT_NAME=$(basename "$REPO_ROOT")
WORKTREE_BASE="/tmp/${PROJECT_NAME}-worktrees"

# Globals set by pick_task
ISSUE_JSON=""
ISSUE_ID=""
ISSUE_TITLE=""
ISSUE_DESCRIPTION=""
ISSUE_TYPE=""
BRANCH_NAME=""
WORKTREE_DIR=""

pick_task() {
  ISSUE_JSON=$(bd ready -n 1 --json --type "task" 2>/dev/null)

  if [ -z "$ISSUE_JSON" ] || [ "$ISSUE_JSON" = "[]" ]; then
    return 1  # No tasks available
  fi

  ISSUE_ID=$(echo "$ISSUE_JSON" | jq -r '.[0].id // empty')
  ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.[0].title // empty')
  ISSUE_DESCRIPTION=$(echo "$ISSUE_JSON" | jq -r '.[0].description // empty')
  ISSUE_TYPE=$(echo "$ISSUE_JSON" | jq -r '.[0].type // "task"')

  if [ -z "$ISSUE_ID" ]; then
    echo "Failed to parse issue from beads output."
    return 1
  fi

  BRANCH_NAME="task/$ISSUE_ID"
  WORKTREE_DIR="$WORKTREE_BASE/$ISSUE_ID"

  echo "Picking up task: $ISSUE_ID - $ISSUE_TITLE"
  return 0
}

claim_task() {
  bd update "$ISSUE_ID" --status in_progress >/dev/null 2>&1
  echo "Task claimed."
}

create_worktree() {
  echo "Creating worktree at $WORKTREE_DIR..."

  mkdir -p "$WORKTREE_BASE"

  # Create branch from current HEAD if it doesn't exist
  if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git branch "$BRANCH_NAME"
  fi

  # Create worktree
  git worktree add "$WORKTREE_DIR" "$BRANCH_NAME"

  echo "Worktree created on branch $BRANCH_NAME"
  echo ""
}

build_prompt() {
  cat <<EOF
## Task: $ISSUE_TITLE

**Task ID:** $ISSUE_ID
**Type:** $ISSUE_TYPE

### Description

$ISSUE_DESCRIPTION

---

### Instructions

1. Read VISION.md and ARCHITECTURE.md for context
2. Read any PRDs or docs referenced in the description
3. Complete the task according to the description and acceptance criteria
4. Commit your changes with a message that includes the task ID ($ISSUE_ID)

Do not use beads (bd) commands - task tracking is handled externally.
EOF
}

run_claude() {
  local prompt="$1"

  echo "Running Claude in worktree..."
  cd "$WORKTREE_DIR"

  # --dangerously-skip-permissions: auto-approve all tool use
  # -p: non-interactive mode, exit when done
  # --verbose --output-format stream-json: stream events, pipe to jq for readability
  if [ "$SILENCE_CLAUDE" = true ]; then
    echo "$prompt" | claude --dangerously-skip-permissions -p --verbose --output-format stream-json >/dev/null 2>&1
  else
    echo "$prompt" | claude --dangerously-skip-permissions -p --verbose --output-format stream-json | jq
  fi

  cd "$REPO_ROOT"
}

merge_branch() {
  echo ""
  echo "Merging $BRANCH_NAME into main..."

  cd "$REPO_ROOT"

  # Merge the branch
  git merge "$BRANCH_NAME" --no-edit

  echo "Branch merged."
}

cleanup_worktree() {
  echo "Cleaning up worktree..."

  git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
  git branch -d "$BRANCH_NAME" 2>/dev/null || true

  echo "Worktree removed."
}

close_task() {
  echo ""
  echo "Closing task: $ISSUE_ID"
  bd close "$ISSUE_ID" >/dev/null 2>&1
  bd sync >/dev/null 2>&1

  echo "Committing beads changes..."
  git add .beads/
  git commit -m "Close $ISSUE_ID" --allow-empty >/dev/null 2>&1 || true

  echo "Done."
}

do_one_task() {
  claim_task
  create_worktree
  run_claude "$(build_prompt)"
  merge_branch
  cleanup_worktree
  close_task
}

call_make_work() {
  echo ""
  echo "========================================"
  echo "No tasks available. Creating new work..."
  echo "========================================"
  echo ""

  local make_work_args="--limit $MAKE_WORK_LIMIT"
  if [ "$SILENCE_CLAUDE" = true ]; then
    make_work_args="$make_work_args --silence-claude"
  fi

  "$SCRIPT_DIR/make-work.sh" $make_work_args
}

main() {
  local total_tasks=0
  local make_work_calls=0

  while true; do
    # Do all available tasks
    while pick_task; do
      do_one_task
      total_tasks=$((total_tasks + 1))
      echo ""
      echo "----------------------------------------"
      echo ""
    done

    echo "Queue empty. Completed $total_tasks task(s) so far."

    # Check if we should create more work
    if [ "$make_work_calls" -lt "$CYCLES" ]; then
      make_work_calls=$((make_work_calls + 1))
      echo ""
      echo "========================================"
      echo "Make-work call $make_work_calls of $CYCLES"
      echo "========================================"
      call_make_work
    else
      break
    fi
  done

  echo ""
  echo "========================================"
  echo "Done. Total tasks completed: $total_tasks"
  echo "Make-work calls: $make_work_calls"
  echo "========================================"
}

main
