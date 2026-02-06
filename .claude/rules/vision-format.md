# Vision Document Format

A vision document states **what the project is**, **why it exists**, **how success is measured**, and **what it is not**. It orients stakeholders, new contributors, and downstream docs (ARCHITECTURE, PRDs). It is not a PRD; it does not list numbered requirements. It sets direction and boundaries.

## Required Sections

1. **Executive Summary** – One or two short paragraphs. What the project is (e.g. "The Task Coordinator is a task board where agents pick their own work"). What it is not in one line (e.g. "We are not a traditional workflow engine"). Elevator pitch only.

2. **Introduction** – Context and problem. Use subsections as needed (e.g. "Research Context", "The Problem", "What This Does"). Include:
   - Organizational or research context (why this exists in this org).
   - The problem being solved and why current solutions fall short.
   - What this project does differently (core approach in a few sentences).
   - Optional: definitions (e.g. "Distributed vs decentralized coordination") when terms are ambiguous.

3. **Why [Organization / Team]** – Why this org or team is doing it. Competitive advantage, fit with strategy, standards work, domain expertise, integration with existing products. One section; tables allowed for relationships to other initiatives.

4. **Planning and Implementation** – How success is measured and how work is phased.
   - **Success Criteria**: Dimensions (e.g. coordination efficiency, agent adaptation, system overhead). Optional: table of measurable outcomes (metrics and targets).
   - **What "Done" Looks Like**: One or two paragraphs describing the desired end state.
   - **Implementation Phases**: Table (phase name, focus, deliverables).
   - **Risks and Mitigations**: Table (risk, impact, likelihood, mitigation).

5. **What This Is NOT** – Explicit boundaries. Short statements: "We are not X. We are not Y." Clarify how this differs from workflow engines, agentic frameworks, job queues, policy engines, GitOps, LLM platforms, etc. Use comparison tables where helpful.

6. **References** – Optional. List or link to external refs; or "See ARCHITECTURE, PRDs" if refs live elsewhere.

## Optional Sections

- **Frontmatter** – YAML at top of file (e.g. title, subtitle, date, author, source) for tooling or publishing. Not required for the rule.
- **Figures** – Diagrams (e.g. PlantUML) per documentation-standards: source in `docs/plantuml/`, image in `docs/images/`, reference in markdown with named figure caption.

## Writing Guidelines

- **Audience**: Stakeholders, new team members, and downstream doc authors. Avoid unexplained jargon; define domain-specific terms when first used.
- **Tone**: Use "we" in active voice (e.g. "We manage tasks as first-class entities"). Follow documentation-standards: concise, active voice, no forbidden terms.
- **Scope**: Vision sets direction and boundaries. Do not duplicate PRD-level requirements; point to PRDs for detailed requirements and acceptance criteria.
- **Location**: Markdown in `docs/VISION.md` (or project root `VISION.md` if preferred).

## Completeness Checklist

- [ ] Executive Summary states what the project is and what it is not in 1–2 paragraphs.
- [ ] Introduction covers context, problem, and what this does (with subsections as needed).
- [ ] "Why [Org]" explains why this org/team is doing it.
- [ ] Planning and Implementation includes success criteria (and optionally metrics table), "What Done Looks Like", phases table, and risks table.
- [ ] "What This Is NOT" clearly lists boundaries and comparisons.
- [ ] Style follows documentation-standards (no forbidden terms, tables named, figures per standard).
- [ ] File saved as `VISION.md` in `docs/` (or agreed location).

## Relationship to Other Docs

- **VISION** – What we are, why we exist, what done looks like, what we are not.
- **ARCHITECTURE** – Components, interfaces, protocols. How the system is built.
- **PRDs** – Numbered requirements, acceptance criteria. What the system must do.
- **Use cases** – Tracer bullets and demos. How we validate the path.

Code and PRDs should be traceable to VISION (goals, boundaries) and ARCHITECTURE (design).
