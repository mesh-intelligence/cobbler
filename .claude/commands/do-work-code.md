# Command: Do Work (Code)

Use this command when the work is **code** (implementation): packages, internal logic, cmd, workers, tests. Follow the **code-prd-architecture-linking** rule (`.claude/rules/code-prd-architecture-linking.md`): code must correspond to existing PRDs and architecture; commits must mention PRDs; add PRD references in code where appropriate (e.g. top of file).

Read VISION.md and ARCHITECTURE.md for context.

## 1. Select a code task

1. Run `bd ready` to see available work.
2. **Pick a code issue**: one whose description specifies an **implementation** deliverable (e.g. component under `pkg/`, `internal/`, `cmd/`; Requirements and Design Decisions for code; Acceptance Criteria like tests or observable behaviour). If the issue lists "Code", "Implementation", "Component or path", or references a PRD for implementation, it is a code task.
3. Run `bd update <issue-id> --status in_progress` to claim it.

## 2. Before implementing

1. **Identify related PRDs and docs** from the issue (deliverable path, component, requirements). See `docs/product-requirements/prd-*.md` and `docs/ARCHITECTURE.md`.
2. **Read** the relevant sections so behaviour, data shapes, and contracts are clear.
3. Read the issue description (Requirements, Design Decisions, Acceptance Criteria) in full.
4. **Read existing code** that you will modify or extend:
   - **NEVER propose changes to code you haven't read first**
   - Read files in the target component or package (`pkg/`, `internal/`, `cmd/`)
   - Understand existing patterns, conventions, and interfaces
   - Identify where your changes will fit into the existing structure
   - Check for related test files and understand the testing approach

## 3. Implement

1. Implement according to the issue **Requirements and Design Decisions** and the **related PRDs/architecture**.
2. Verify the **Acceptance Criteria** are met (tests, behaviour, observability if specified).
3. Write tests if the issue or PRD specifies them.
4. Where appropriate (e.g. package doc or top of file), add a short comment listing **implemented PRDs** (see code-prd-architecture-linking rule).

## 4. After implementation

1. **Run any tests** to verify your work.
2. **Calculate metrics**: tokens used; lines added/modified for this change (e.g. `git diff --stat`). When summarizing changes, run `./scripts/stats.sh` and include its output (Go production/test LOC, doc words) in the summary.
3. **Log metrics and close**:
   ```bash
   bd comments add <issue-id> "tokens: <count>, loc: <lines_added>+<lines_modified>"
   bd close <issue-id>
   ```
4. **Commit** changes and `.beads/issues.jsonl`. **Commit message must mention which PRDs (or aspects) are implemented**:
   ```bash
   git add -A
   git commit -m "Implement X (prd-..., prd-...)"
   ```
5. If you discovered new work or issues, file them in Beads.

## 5. After completing an epic

When you close the **last issue in an epic** (all child tasks complete), perform a **thorough code inspection**:

1. **Read all files** that were created or modified during the epic
2. **Check for inconsistencies**:
   - Naming conventions across files and packages
   - Error handling patterns
   - Code duplication or missed abstractions
   - Test coverage gaps
3. **Verify epic-level acceptance criteria** (from the epic issue description)
4. **Run full test suite** and any integration tests
5. **File follow-up issues** for any technical debt, refactoring, or improvements discovered
6. **Check for doc updates needed**: if implementation revealed design changes or clarifications, **ask the user** before updating architecture or PRD docs
7. **Evaluate use case completion**:
   - Identify which use case(s) this epic contributes to
   - Review success criteria in `docs/use-cases/`
   - If all criteria are met, update ROADMAP.md to mark the use case status as "Complete"
   - If not complete, note what remains and ensure follow-up tasks exist
8. **Summarize epic completion**: run `./scripts/stats.sh` and report:
   - What was built (components, features)
   - Total metrics (tokens, LOC across all child issues)
   - Any deviations from original design
   - Follow-up work filed
   - Use case status (complete or remaining work)

IMPORTANT:
- Never edit `.beads/` by hand; use `bd` only.
- Always commit `.beads/issues.jsonl` along with your code changes.
- Track token usage and lines of code for every issue closed.
- **Link code to docs**: identify PRDs/architecture → implement to fit → commit with PRD refs → optional PRD list in file/package comments.

Show what you completed and what's next. When summarizing, run `./scripts/stats.sh` and include its output.
