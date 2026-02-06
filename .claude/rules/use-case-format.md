# Use Case Format

A **use case** describes a concrete usage of the architecture. It specifies a **tracer bullet**: one end-to-end path of functionality through the system. Use cases lead to a **proof of concept** or **demo** and guide **how we develop software**—what to build next and in what order.

- **Tracer bullet**: A thin slice of capability that goes from trigger to outcome, touching each layer so we validate the path before broadening.
- **PoC/Demo**: The use case defines what "done" looks like for a demo or PoC milestone.
- **Guides development**: Use cases drive prioritization: we implement the path needed for the use case, then expand. PRDs specify the pieces; use cases show how they connect.

## Required Sections

1. **Summary** – One or two sentences: who does what, and what outcome is achieved. The "elevator pitch" for the use case.

2. **Actor and trigger** – Who or what initiates the scenario (e.g. user, system, upstream service) and what event or action starts it.

3. **Flow** – Numbered steps from trigger to outcome. Each step should be testable and map to components/operations. This is the tracer bullet path.

4. **Architecture touchpoints** – Explicit list of architecture elements this use case exercises: interfaces, components, and protocols. Ensures the use case validates the architecture.

5. **Success / demo criteria** – How we know the use case is implemented: observable outcomes, metrics, or demo script. Must be checkable without ambiguity.

6. **Out of scope** – What this use case does *not* cover. Keeps the tracer bullet thin.

## Optional Sections

7. **Dependencies** – Other use cases or PRD deliverables that must exist first.
8. **Risks / mitigations** – What could block the PoC or demo and how we address it.

## Writing Guidelines

- **One path**: One primary flow per use case. Variants or error paths can be short subsections.
- **Concrete**: Use real operations, component names, and data from your architecture.
- **Aligned to docs**: Reference ARCHITECTURE and PRDs so the use case stays consistent with the design.
- **Demo-ready**: Success criteria should be something you can show: "Run X, then Y, then Z; observe W."

## File and Naming

- **Location**: `docs/use-cases/rel[NN].[N]-uc[NNN]-[short-name].md`
- **Release prefix**: Major and minor release (e.g., 01.0, 01.1, 02.0). A release delivers all use cases in that release. Minor releases add functionality discovered later.
- **Use case number**: Three-digit sequence number within the release (e.g., 001, 002, 003).
- **Short name**: Lowercase, hyphenated, verb or scenario describing the use case.

### Release Numbering

See ROADMAP.md for the authoritative release schedule and use case status. Summary:

| Release | Focus |
|---------|-------|
| 00.0 | Cross-release milestones (span multiple releases) |
| 01.0 | Core storage with SQLite backend |
| 02.0 | Properties with enforcement |
| 03.0 | Trails and stashes |
| 04.0 | Metadata and additional backends |
| 99.0 | Unscheduled (not yet assigned to a release) |

Minor releases (e.g., 01.1, 02.1) add functionality to a major release without renumbering existing use cases.

## Relationship to Other Docs

| Document | Role |
|----------|------|
| **VISION** | Why we build; use case should support vision goals. |
| **ROADMAP** | Release schedule and use case status; determines work priority. |
| **ARCHITECTURE** | What we build; use case traces a path through it. |
| **PRDs** | Detailed requirements for components; use case motivates which PRD items to implement first. |
| **Use case** | One tracer bullet through the stack → PoC/demo; guides development order. |

## Completeness Checklist

- [ ] Summary states who, what, and outcome in 1–2 sentences
- [ ] Actor and trigger are explicit
- [ ] Flow is numbered, end-to-end, and maps to real components/operations
- [ ] Architecture touchpoints list interfaces, components, and protocols used
- [ ] Success/demo criteria are observable and checkable
- [ ] Out of scope keeps the use case focused
- [ ] File saved as `rel[NN].[N]-uc[NNN]-[short-name].md` in `docs/use-cases/`
