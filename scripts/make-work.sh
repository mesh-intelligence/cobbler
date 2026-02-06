#!/usr/bin/env bash
#
# Invoke Claude to create new work items (issues, PRDs, use cases).
#
# The script externalizes bd: it queries existing issues before invoking Claude,
# and Claude outputs new issues as JSON rather than using bd commands directly.
#
# Usage: make-work.sh [options] [prompt]
#
# Options:
#   --silence-claude       Suppress Claude's output
#   --keep                 Keep previous proposed-issues files (don't clean up)
#   --limit N              Limit to N issues (default: 10)
#   --no-import            Skip bd import instructions (default behavior)
#   --import               Show bd import instructions after completion
#   --issues-file FILE     Use FILE as existing issues instead of querying bd
#   --append-prompt FILE   Append contents of FILE to the prompt
#   --no-auto-import       Skip automatic import into bd (default: auto-import enabled)
#   --prompt TEXT          Add user prompt/context (disabled by default)
#
# Workflow:
# 1. Query bd for existing issues (or use provided file)
# 2. Build prompt with existing work context
# 3. Run Claude to analyze and propose new work
# 4. Claude outputs new issues to docs/proposed-issues-YYYYMMDD-HHMMSS.json
# 5. User reviews and optionally imports via bd
#
# If no prompt is provided, reads from stdin.
#

set -e

# Parse arguments
SILENCE_CLAUDE=false
KEEP_FILES=false
ISSUE_LIMIT=10
SHOW_IMPORT=false
ISSUES_FILE=""
APPEND_PROMPT_FILE=""
AUTO_IMPORT=true
PROMPT_ARG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --silence-claude)
      SILENCE_CLAUDE=true
      shift
      ;;
    --keep)
      KEEP_FILES=true
      shift
      ;;
    --limit)
      ISSUE_LIMIT="$2"
      shift 2
      ;;
    --no-import)
      SHOW_IMPORT=false
      shift
      ;;
    --import)
      SHOW_IMPORT=true
      shift
      ;;
    --issues-file)
      ISSUES_FILE="$2"
      shift 2
      ;;
    --append-prompt)
      APPEND_PROMPT_FILE="$2"
      shift 2
      ;;
    --no-auto-import)
      AUTO_IMPORT=false
      shift
      ;;
    --prompt)
      PROMPT_ARG="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="${SCRIPT_DIR}/.."
cd "$REPO_ROOT" || exit 1
REPO_ROOT=$(pwd)

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="$REPO_ROOT/docs/proposed-issues-${TIMESTAMP}.json"

# Clean up old proposed-issues files unless --keep is set
cleanup_old_files() {
  if [ "$KEEP_FILES" = false ]; then
    rm -f "$REPO_ROOT"/docs/proposed-issues-*.json 2>/dev/null || true
  fi
}

# Get existing issues from bd or file
get_existing_issues() {
  local issues_json="[]"

  if [ -n "$ISSUES_FILE" ]; then
    if [ -f "$ISSUES_FILE" ]; then
      issues_json=$(cat "$ISSUES_FILE")
    else
      echo "Warning: Issues file not found: $ISSUES_FILE" >&2
    fi
  elif command -v bd &> /dev/null; then
    issues_json=$(bd list --json 2>/dev/null || echo "[]")
  fi

  echo "$issues_json"
}

# Import proposed issues into bd
import_issues() {
  local json_file="$1"

  if ! command -v bd &> /dev/null; then
    echo "Error: bd command not found, cannot import" >&2
    return 1
  fi

  if [ ! -f "$json_file" ]; then
    echo "Error: JSON file not found: $json_file" >&2
    return 1
  fi

  echo "Importing issues from $json_file..."

  # Track epic IDs for parent references (using temp file for bash 3 compat)
  local epic_map_file
  epic_map_file=$(mktemp)
  trap "rm -f $epic_map_file" EXIT

  # First pass: create epics
  local epic_count
  epic_count=$(jq '[.[] | select(.type == "epic")] | length' "$json_file")
  echo "Creating $epic_count epic(s)..."

  while IFS= read -r epic; do
    local title description slug
    title=$(echo "$epic" | jq -r '.title')
    description=$(echo "$epic" | jq -r '.description')
    slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

    echo "  Creating epic: $title"
    local epic_id
    epic_id=$(bd create --type epic --title "$title" --description "$description" --json 2>/dev/null | jq -r '.id // empty')

    if [ -n "$epic_id" ]; then
      echo "$slug=$epic_id" >> "$epic_map_file"
      echo "    Created: $epic_id"
    else
      echo "    Warning: Failed to create epic" >&2
    fi
  done < <(jq -c '.[] | select(.type == "epic")' "$json_file")

  # Second pass: create tasks
  local task_count
  task_count=$(jq '[.[] | select(.type == "task")] | length' "$json_file")
  echo "Creating $task_count task(s)..."

  while IFS= read -r task; do
    local title description parent labels parent_id
    title=$(echo "$task" | jq -r '.title')
    description=$(echo "$task" | jq -r '.description')
    parent=$(echo "$task" | jq -r '.parent // empty')
    labels=$(echo "$task" | jq -r '.labels // [] | join(",")')

    echo "  Creating task: $title"

    # Build command
    local cmd="bd create --type task --title \"$title\" --description \"$description\""

    # Add parent if specified and found
    if [ -n "$parent" ]; then
      parent_id=$(grep "^${parent}=" "$epic_map_file" 2>/dev/null | cut -d= -f2)
      if [ -n "$parent_id" ]; then
        cmd="$cmd --parent $parent_id"
      else
        echo "    Warning: Parent epic '$parent' not found" >&2
      fi
    fi

    # Add labels if specified
    if [ -n "$labels" ]; then
      cmd="$cmd --labels $labels"
    fi

    eval "$cmd" >/dev/null 2>&1 && echo "    Created" || echo "    Warning: Failed to create task" >&2
  done < <(jq -c '.[] | select(.type == "task")' "$json_file")

  echo "Import complete."

  # Sync beads and commit
  echo "Syncing and committing beads changes..."
  bd sync >/dev/null 2>&1 || true
  git add .beads/
  git commit -m "Add issues from make-work" --allow-empty >/dev/null 2>&1 || true
  echo "Changes committed."
}

build_prompt() {
  local user_input="$1"
  local existing_issues="$2"
  local limit="$3"
  local output_filename="$4"
  local append_content="$5"

  cat <<'PROMPT_START'
# Make Work

Read VISION.md, ARCHITECTURE.md, ROADMAP.md, docs/product-requirements/README.md, and docs/use-cases/README.md if they exist.

## Existing Work

The following issues already exist in the system:

```json
PROMPT_START

  echo "$existing_issues"

  cat <<PROMPT_MIDDLE
\`\`\`

Review what's in progress, what's completed, and what's pending.

## Instructions

Summarize:

1. What problem this project solves
2. The high-level architecture (major components and how they fit together)
3. The current state of implementation (what's done, what's in progress)
4. **Current release**: Which release we are working on and which use cases remain (check ROADMAP.md)
5. Current repo size: run \`./scripts/stats.sh\` and include its output (Go production/test LOC, doc words)

Based on this, propose next steps using **release priority**:

1. **Focus on earliest incomplete release**: Prioritize completing use cases from the current release in ROADMAP.md
2. **Early preview allowed**: Later use cases can be partially implemented if they share functionality with the current release
3. **Assign issues to releases**: Each issue should map to a use case in ROADMAP.md; if uncertain, use release 99.0 (unscheduled)
4. If epics exist: suggest new issues to add to existing epics, or identify what to work on next
5. If no epics exist: suggest epics to create and initial issues for each
6. Identify dependencies - what should be built first and why?

When proposing issues (per issue-format rule):

1. **Type**: Say whether each issue is **documentation** (markdown in \`docs/\`) or **code** (implementation).
2. **Required Reading**: List files the agent must read before starting (PRDs, ARCHITECTURE sections, existing code). This is mandatory for all issues.
3. **Files to Create/Modify**: Explicit list of files the issue will produce or change. For docs: output path. For code: packages/files to create or edit.
4. **Structure** (all issues): Requirements, Design Decisions (optional), Acceptance Criteria.
5. **Documentation issues**: Add **format rule** reference and **required sections** (PRD: Problem, Goals, Requirements, Non-Goals, Acceptance Criteria; use case: Summary, Actor/trigger, Flow, Success criteria).
6. **Code issues**: Requirements, Design Decisions, Acceptance Criteria (tests/behavior); no PRD-style Problem/Goals/Non-Goals.

**Code task sizing**: Target 300-700 lines of production code per task, touching no more than 5 files. This keeps tasks completable in a single session while being substantial enough to make meaningful progress. Split larger features into multiple tasks; combine trivial changes into one task.

**Task limit**: Create no more than ${limit} tasks. If more work is needed, create additional tasks in a future session.

## Output

After analyzing the project and proposing work, output the new issues as a JSON file.

**IMPORTANT**: Do NOT use bd commands. Instead, write the proposed issues to \`${output_filename}\` using the Write tool.

The JSON format should be an array of issue objects:

\`\`\`json
[
  {
    "type": "task",
    "title": "Task title",
    "description": "Full task description with Required Reading, Files to Create/Modify, Requirements, Design Decisions, Acceptance Criteria",
    "labels": ["code"]
  }
]
\`\`\`

Field notes:
- \`type\`: "epic" or "task"
- \`title\`: Short descriptive title
- \`description\`: Full issue description following issue-format rule
- \`parent\`: (tasks only, optional) Reference to parent epic by title slug (lowercase, hyphenated). Only use if creating a NEW epic in the same JSON.
- \`labels\`: Optional array, use "documentation" for doc tasks, "code" for code tasks

**Epics are optional.** Only create a new epic if there is a clear need for grouping multiple related tasks. Most of the time, standalone tasks are sufficient. Do NOT create an epic just to have one - if you have only 1-2 tasks, just create the tasks without an epic.

The issues will be automatically imported into bd.
PROMPT_MIDDLE

  if [ -n "$user_input" ]; then
    cat <<PROMPT_USER

## Additional Context from User

$user_input
PROMPT_USER
  fi

  if [ -n "$append_content" ]; then
    cat <<PROMPT_APPEND

## Appended Instructions

$append_content
PROMPT_APPEND
  fi
}

run_claude() {
  local prompt="$1"

  echo "Running Claude with make-work..."
  echo ""

  # --dangerously-skip-permissions: auto-approve all tool use
  # -p: non-interactive mode, exit when done
  # --verbose --output-format stream-json: stream events, pipe to jq for readability
  if [ "$SILENCE_CLAUDE" = true ]; then
    echo "$prompt" | claude --dangerously-skip-permissions -p --verbose --output-format stream-json >/dev/null 2>&1
  else
    echo "$prompt" | claude --dangerously-skip-permissions -p --verbose --output-format stream-json | jq
  fi
}

main() {
  local user_input="$PROMPT_ARG"

  # Clean up old files
  cleanup_old_files

  echo "Querying existing issues..."
  if [ -n "$ISSUES_FILE" ]; then
    echo "  Using issues file: $ISSUES_FILE"
  fi
  local existing_issues
  existing_issues=$(get_existing_issues)

  local issue_count
  issue_count=$(echo "$existing_issues" | jq 'length' 2>/dev/null || echo "0")
  echo "Found $issue_count existing issue(s)."
  echo "Issue limit: $ISSUE_LIMIT"
  echo "Output file: $OUTPUT_FILE"
  echo ""

  local output_filename
  output_filename=$(basename "$OUTPUT_FILE")

  # Read append prompt file if specified
  local append_content=""
  if [ -n "$APPEND_PROMPT_FILE" ]; then
    if [ -f "$APPEND_PROMPT_FILE" ]; then
      append_content=$(cat "$APPEND_PROMPT_FILE")
      echo "Appending prompt from: $APPEND_PROMPT_FILE"
    else
      echo "Warning: Append prompt file not found: $APPEND_PROMPT_FILE" >&2
    fi
  fi

  run_claude "$(build_prompt "$user_input" "$existing_issues" "$ISSUE_LIMIT" "docs/$output_filename" "$append_content")"

  echo ""
  if [ -f "$OUTPUT_FILE" ]; then
    echo "Proposed issues written to: $OUTPUT_FILE"
    echo ""
    echo "To review:"
    echo "  cat $OUTPUT_FILE | jq"

    if [ "$AUTO_IMPORT" = true ]; then
      echo ""
      import_issues "$OUTPUT_FILE"
      # Delete proposed issues file after successful import
      rm -f "$OUTPUT_FILE"
      echo "Removed: $OUTPUT_FILE"
    elif [ "$SHOW_IMPORT" = true ]; then
      echo ""
      echo "To import into bd (after review):"
      echo "  # Manual import - bd create commands for each issue"
    fi
  else
    echo "No proposed issues file created."
  fi

  echo ""
  echo "Done."
}

main
