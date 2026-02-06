# Command: Do Work

Pick **one** of the two workflows below depending on the type of work. Use **do-work-docs** for documentation tasks, **do-work-code** for implementation tasks.

## Task Priority

When selecting from available issues, **prefer documentation issues over code issues**. Documentation establishes the design before implementation begins. Complete PRDs, use cases, and architecture updates before moving to code tasks.

## Choose the right command

| Task type | Command | How to tell |
|-----------|---------|-------------|
| **Documentation** | [do-work-docs](do-work-docs.md) | Issue specifies output under `docs/` (PRD, use case, invention disclosure, ARCHITECTURE); has "File location", "PRD location", "Required sections", or a doc format rule. |
| **Code** | [do-work-code](do-work-code.md) | Issue specifies implementation (e.g. `pkg/`, `internal/`, `cmd/`, `workers/`); has code Requirements, Design Decisions, tests or behaviour in Acceptance Criteria. |

## Quick selection

1. Run `bd ready` and look at the issue titles and descriptions.
2. If the deliverable is **markdown in docs/** (path like `docs/product-requirements/...`, `docs/use-cases/...`, `docs/invention-disclosures/...`, or `docs/ARCHITECTURE.md`) → use **do-work-docs**.
3. If the deliverable is **code** (Go, tests, `pkg/`, `internal/`, `cmd/`, `workers/`) → use **do-work-code**.

Then run the chosen command and follow its steps (select task, follow rules, implement, close issue, commit).
