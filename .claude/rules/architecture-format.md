# Architecture Document Format

An architecture document describes **how the system is built**: components, interfaces, protocols, data flow, and design decisions. It is the bridge between vision (what and why) and PRDs (numbered requirements). It does not list requirements; it describes structure, contracts, and rationale so implementers and PRD authors stay aligned.

## Required Sections

1. **System Overview** – What the system does in one or two paragraphs. Core insight (e.g. "agents pick their own work from a shared task board"). Alignment with reference architecture or standards if applicable. Use subsections for:
   - **Lifecycle** – Main state machines or lifecycles (e.g. task lifecycle: pending → ready → running → completed/failed). Link to PRD for full spec.
   - **Coordination pattern** – How components interact (e.g. pull-based workers, PUB/SUB announcements). Sub-subsections as needed (e.g. topic-based classification, routing dimensions).
   - Optional: branch or session model, deployment workflow.

2. **Main interface(s)** – The contract(s) between major parts of the system. Include:
   - **Data structures** – Short list of types and their role. Do not duplicate full field specs; link to PRD.
   - **Operations** – List or table of operations and purpose. Link to PRD for signatures, preconditions, and error conditions.
   - **Announcements / events** – What is broadcast, when, and payload shape. Link to PRD for full format.
   - Optional: JSON or code snippets for representative examples; subsections for special cases (e.g. branch creation).

3. **System Components** – Each major component in the system. For each: name, responsibility in one or two sentences, capabilities (bullets), and link to PRD or use case where details live. Optional: figure showing components.

4. **Design Decisions** – Numbered decisions (e.g. "Decision 1: Interface Design"). For each: short statement of the decision, benefits, and optionally alternatives rejected. Link to PRDs for full rationale where applicable.

5. **Technology Choices** – Table: component (or layer), technology, purpose. Link to Technology Stack PRD for schema, API definitions, and config. Optional: subsections for interface strategy (e.g. MCP vs HTTP vs NNG).

6. **Project Structure** – Directory tree (e.g. `cmd/`, `pkg/`, `internal/`, `workers/`) and one-line role per package or directory. Clarify what is shared (pkg) vs internal. Link to PRD for full layout.

7. **Implementation Status** – Current focus (phase or theme). Optional: implementation phases table, success metrics table (from VISION), and progress checklist (done / in progress). Link to VISION and PRDs.

8. **Related Documents** – List or table of doc and purpose (VISION, PRDs, use cases). Enables traceability.

9. **References** – Optional. External refs or "See PRDs" if references live in linked docs.

## Optional Sections

- **Frontmatter** – YAML at top (e.g. title, date, author, location) for tooling or publishing.
- **Complete System View** – Figure showing all components or phases; short bullet list of what each area covers.
- **Data Flow Patterns** – Subsections (e.g. task creation flow, worker dispatch, state transitions) with figures and short prose. Link to PRDs for detailed flows.
- **Alignment with Reference Architecture** – How this architecture maps to org or standards (e.g. design principles, functional layers).

## Writing Guidelines

- **Audience**: Implementers, PRD authors, and reviewers. Assume readers need to build or extend the system and to trace decisions to requirements.
- **Tone**: Use "we" in active voice (e.g. "We define a protocol-agnostic coordination abstraction"). Follow documentation-standards: concise, active voice, no forbidden terms.
- **Scope**: Describe structure and contracts; do not duplicate PRD-level requirements. Point to PRDs for field specs, operation signatures, acceptance criteria, and state machine details.
- **Figures**: Per documentation-standards. Source in `docs/plantuml/`, image in `docs/images/`, named figure caption (e.g. "Figure N Title").
- **Tables**: Name all tables (e.g. "Table 1: Routing Dimensions"). Use for operations, technology choices, phases, related documents.
- **Location**: Markdown in `docs/ARCHITECTURE.md` (or project root `ARCHITECTURE.md` if preferred).

## Completeness Checklist

- [ ] System Overview states what the system does and the core coordination pattern; lifecycle and pattern subsections present.
- [ ] Main interface(s) describe data structures, operations, and announcements; link to PRD for full spec.
- [ ] System Components list each major component with responsibility and link to PRD or use case.
- [ ] Design Decisions are numbered with rationale and benefits (and optionally alternatives rejected).
- [ ] Technology Choices table and link to Technology Stack PRD.
- [ ] Project Structure shows directory tree and package roles; link to PRD if needed.
- [ ] Implementation Status reflects current focus; optional phases and progress checklist.
- [ ] Related Documents list VISION, PRDs, use cases (and optionally disclosures).
- [ ] Style follows documentation-standards (no forbidden terms, tables named, figures per standard).
- [ ] File saved as `ARCHITECTURE.md` in `docs/` (or agreed location).

## Relationship to Other Docs

- **VISION** – What we are and why; success criteria and phases. Architecture implements the vision.
- **ARCHITECTURE** – Components, interfaces, protocols, design decisions. How the system is built.
- **PRDs** – Numbered requirements, field specs, operation contracts. Architecture points to PRDs for detail.
- **Use cases** – Tracer bullets and flows. Architecture describes the components and interfaces those flows use.

Code and PRDs should be traceable to ARCHITECTURE (components, interfaces) and VISION (goals).
