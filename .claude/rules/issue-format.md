# Issue Format

Beads issues fall into two deliverable types: **documentation** (markdown in `docs/`) and **code** (implementation). The issue description must make the type and output location explicit so agents know what to produce and where.

## Common Structure (All Issues)

Every issue description should include:

1. **Required Reading** – Files the agent must read before starting work. List PRDs, ARCHITECTURE sections, existing code, or other docs that provide context. This prevents the agent from working without understanding the design.
2. **Files to Create/Modify** – Explicit list of files the issue will produce or change. For documentation: the output path. For code: the packages or files to create/edit.
3. **Requirements** – What needs to be built or written (functional requirements, scope)
4. **Design Decisions** – Technical or structural choices to follow (optional but recommended)
5. **Acceptance Criteria** – How we know it is done (checkable outcomes, tests, or completeness checklist)

For epics, the description can be higher level; child tasks carry the detailed structure.

## Documentation Issues

Documentation issues produce markdown (and optionally diagrams) under `docs/`. The issue must specify **output location** and **which format rule** applies.

### Output Location and Format Rule

| Deliverable type | Output location | Format rule | When to use |
| ----------------- | ---------------- | ----------- | ------------ |
| **ARCHITECTURE / docs** | `docs/ARCHITECTURE.md` or specific doc | documentation-standards | Updating system overview, components, diagrams, design decisions |
| **PRD** | `docs/product-requirements/prd-[feature-name].md` | prd-format | New or updated product requirements; numbered requirements, Problem/Goals/Non-Goals |
| **Use case** | `docs/use-cases/uc-[short-name].md` | use-case-format | Tracer-bullet flows, actor/trigger, demo criteria |

### What to Put in the Issue

- **File or directory path** – e.g. `docs/product-requirements/prd-feature-name.md`, `docs/use-cases/uc-scenario-name.md`
- **Required sections** – List the sections from the format rule (e.g. for PRD: Problem, Goals, Requirements, Non-Goals, Acceptance Criteria)
- **Scope or content hints** – Bullet points or short paragraphs for Problem, Goals, main requirements, and non-goals so the agent does not have to infer them
- **Reference to format rule** – e.g. "Follow .claude/rules/prd-format.md" or "per prd-format rule"
- **Acceptance criteria** – Include checklist items such as "All required sections present", "File saved at [path]", "Requirements numbered and specific"

Example (PRD issue):

```markdown
## Required Reading
- docs/ARCHITECTURE.md § System Components
- docs/product-requirements/prd-cupboard-core.md (interface contract)

## Files to Create/Modify
- docs/product-requirements/prd-feature-name.md (create)

## Required Sections (per prd-format rule)
1. Problem - ...
2. Goals - ...
3. Requirements - R1: ..., R2: ...
4. Non-Goals - ...
5. Acceptance Criteria - ...

## Acceptance Criteria
- [ ] All required sections present
- [ ] File saved as prd-feature-name.md
```

## Code Issues

Code issues produce or change implementation (e.g. Go, Python, config, tests) outside of `docs/`. The issue must specify:

- **Required Reading** – PRDs, ARCHITECTURE sections, or existing code the agent must read first
- **Files to Create/Modify** – Packages or files to create/edit (e.g. `internal/crumbs/crumbs.go`, `pkg/types/crumb.go`)
- **Requirements** – Features, behaviors, or changes to implement
- **Design Decisions** – Architecture, patterns, or constraints
- **Acceptance Criteria** – How to verify: tests, CLI behavior, observable outcomes

Do not put PRD-style "Problem/Goals/Non-Goals" in code issues; use the structure above.

Example (code issue):

```markdown
## Required Reading
- docs/product-requirements/prd-crumbs-interface.md (CrumbTable contract)
- pkg/types/cupboard.go (existing interface)

## Files to Create/Modify
- pkg/types/crumb.go (create) - Crumb struct, Filter type
- internal/sqlite/crumbs.go (create) - CrumbTable implementation
- internal/sqlite/crumbs_test.go (create) - tests

## Requirements
- Implement CrumbTable interface per prd-crumbs-interface
- Add, Get, Archive, Purge, Fetch operations
- Property operations (Set/Get/Clear)

## Design Decisions
- Use table accessor pattern from prd-cupboard-core
- Filter as map[string]any per PRD

## Acceptance Criteria
- [ ] All CrumbTable operations implemented
- [ ] Tests pass for each operation
- [ ] Errors match PRD error types
```

### Go Layout (Recommended)

- **pkg/** – Shared public API: types and interfaces. No implementation; importable by other modules.
- **internal/** – Private implementation details. Not importable outside the module.
- **cmd/** – Entry points and executables.

When proposing or implementing code issues, keep implementation in **internal/** not **pkg/**.

## Quick Reference

| Issue type | Output | Key sections in issue |
| ---------- | ------ | ---------------------- |
| Documentation (ARCHITECTURE, general docs) | `docs/*.md`, `docs/**/*.puml` | Required Reading, Files to Create/Modify, Requirements, Acceptance Criteria; follow documentation-standards |
| Documentation (PRD) | `docs/product-requirements/prd-*.md` | Required Reading, Files to Create/Modify, Required sections (Problem, Goals, Requirements, Non-Goals, Acceptance Criteria), Acceptance Criteria; follow prd-format |
| Documentation (use case) | `docs/use-cases/uc-*.md` | Required Reading, Files to Create/Modify, Summary, Actor/trigger, Flow, Success criteria; follow use-case-format |
| Code | `pkg/`, `internal/`, `cmd/` | Required Reading, Files to Create/Modify, Requirements, Design Decisions, Acceptance Criteria (tests/behavior); see Go layout above |

## When Creating or Editing Issues

1. Set **deliverable type**: documentation vs code.
2. List **Required Reading**: PRDs, ARCHITECTURE sections, or code the agent must read before starting.
3. List **Files to Create/Modify**: explicit paths for all outputs.
4. If documentation: set **format rule** (PRD, use case, ARCHITECTURE) and **required sections**.
5. Include **Requirements** and **Acceptance Criteria** in every issue.
