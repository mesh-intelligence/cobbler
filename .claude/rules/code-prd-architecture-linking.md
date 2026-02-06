# Code ↔ PRD and Architecture Linking

When implementing code (e.g. via the **do-work** command), code must correspond to existing PRDs and architecture documents. Implementations must be traceable to those docs, and commits and comments must record the link.

## Before Implementing

1. **Identify related docs** from the issue, component, or area you are changing:
   - **PRDs**: `docs/product-requirements/prd-*.md`
   - **Architecture**: `docs/ARCHITECTURE.md` (components, interfaces, protocols)
   - **Vision** (if relevant): `docs/VISION.md`
2. **Read** the relevant sections of those docs so behaviour, data shapes, and contracts are clear.
3. **Implement** so that the code conforms to the requirements and design described there.

## Git Commit Message

The commit message **must mention which PRDs (or aspects) are being implemented**.

- Prefer a short, explicit line such as: `Implement X (prd-feature-name, prd-component)` or `Add Y per prd-feature R12`.
- If only parts of a PRD are touched, say so: e.g. `Implement operation X (prd-feature R8, R13)`.

Example:

```
Implement core operations (prd-feature-name R6–R7)

- pkg/mypackage types and internal/mypackage implementation
```

## Code Comments (Where Appropriate)

Where it helps readability—especially at the **top of a file** or **package doc**—list the **implemented PRDs** (and optionally architecture sections) that this code fulfils. Do not repeat this in every function; use file- or package-level comments only.

Example (Go):

```go
// Package mypackage implements the core functionality.
// Implements: prd-feature-name (operations listed in PRD);
//             docs/ARCHITECTURE § Component Name.
package mypackage
```

Example (top of file):

```go
// Server implements the HTTP API.
// Implements: prd-api-interface (operation set). See docs/ARCHITECTURE § System Components.
```

## Do-Work Flow (Summary)

When **do-work** is invoked:

1. Use **bd ready** / **bd show** and claim an issue.
2. **Identify related PRDs and docs** from the issue text, deliverable path, or component.
3. **Read** those PRDs and relevant ARCHITECTURE sections before writing code.
4. **Implement** so behaviour and contracts match those docs.
5. **Commit** with a message that states which PRDs (or aspects) are implemented.
6. Where useful (e.g. package or top-of-file), **add a short comment** listing the implemented PRDs.
7. Close the issue and track metrics per beads-workflow.

## Reference Paths

| Doc | Path | Use |
|-----|------|-----|
| Architecture | `docs/ARCHITECTURE.md` | Components, interfaces, protocols |
| PRDs | `docs/product-requirements/prd-*.md` | Requirements, operations, data structures |
| Vision | `docs/VISION.md` | Goals and context |

Code that does not map to at least one PRD or architecture section is out of scope for do-work unless the issue explicitly adds new behaviour and you first propose or update the relevant doc.
