# Command: Do Work (Documentation)

Use this command when the work is **documentation** (markdown in `docs/`): PRDs, use cases, invention disclosures, ARCHITECTURE updates, or other docs. Follow the **issue-format** rule for output location and format; use the format rule named in the issue (prd-format, use-case-format, patent-disclosure-format, documentation-standards).

Read VISION.md and ARCHITECTURE.md for context. For PRDs also scan existing `docs/product-requirements/`; for use cases `docs/use-cases/`; for invention disclosures `docs/invention-disclosures/`.

## 1. Select a documentation task

1. Run `bd ready` to see available work.
2. **Pick a documentation issue**: one whose description specifies a **documentation** deliverable (output path under `docs/`, e.g. `docs/product-requirements/prd-*.md`, `docs/use-cases/uc-*.md`, `docs/invention-disclosures/`, or `docs/ARCHITECTURE.md`). If the issue lists "File location", "PRD location", "Output path", or "Required sections" from a doc format rule, it is a documentation task.
3. Run `bd update <issue-id> --status in_progress` to claim it.

## 2. Before writing

1. **Read the issue** and note:
   - **Output path** (exact file or directory, e.g. `docs/product-requirements/prd-task-tracking-auditing.md`).
   - **Format rule** (e.g. prd-format, use-case-format, patent-disclosure-format, documentation-standards) and **required sections**.
   - **Scope or content hints** (Problem, Goals, requirements bullets, non-goals, etc.).
2. **Open the format rule** (e.g. `.claude/rules/prd-format.md`, `.claude/rules/use-case-format.md`) and follow its structure and checklist.
3. If the doc references or extends existing content (e.g. ARCHITECTURE, another PRD), read the relevant sections so the new doc is consistent.

## 3. Write the doc

1. Produce the deliverable at the **exact output path** given in the issue.
2. Include all **required sections** from the format rule (Problem, Goals, Requirements, Non-Goals, Acceptance Criteria for PRDs; Summary, Actor/trigger, Flow, Architecture touchpoints, Success criteria, Out of scope for use cases; etc.).
3. Follow **documentation-standards** (concise, active voice, no forbidden terms; tables/lists per doc standards).
4. For diagrams: create `.puml` files in `docs/plantuml/`, convert to PNG in `docs/images/`, and reference using this exact format:

   ```markdown
   |  |
   |:--:|
   | ![plantuml/diagram-name.puml](images/diagram-name.png) |
   |Figure N Title of the Figure |
   ```

   - Source path in alt text: `![plantuml/source.puml](...)`
   - Image path in src: `(images/generated.png)`
   - Caption format: `|Figure N Description |` (no colon after "Figure N")
5. Verify the issue **Acceptance Criteria** (e.g. "All required sections present", "File saved at [path]").

## 4. After writing

1. **Check completeness** against the issue Acceptance Criteria and the format rule checklist.
2. **Calculate metrics**: tokens used; lines added/modified for this change (e.g. `git diff --stat` for the new/changed file). When summarizing changes, run `./scripts/stats.sh` and include its output (Go production/test LOC, doc words) in the summary.
3. **Log metrics and close**:
   ```bash
   bd comments add <issue-id> "tokens: <count>, loc: <lines_added>+<lines_modified>"
   bd close <issue-id>
   ```
4. **Commit** changes and `.beads/issues.jsonl`. **Commit message must state the deliverable and path** (e.g. `Add prd-task-tracking-auditing (docs/product-requirements/prd-task-tracking-auditing.md)`):
   ```bash
   git add -A
   git commit -m "Add <doc name> (<output path>)"
   ```
5. If you found follow-up work, file it in Beads.

## 5. After completing an epic

When you close the **last issue in an epic** (all child tasks complete):

1. **Review all docs** created or modified during the epic for consistency
2. **Verify epic-level acceptance criteria** (from the epic issue description)
3. **Evaluate use case completion**:
   - Identify which use case(s) this epic contributes to
   - Review success criteria in `docs/use-cases/`
   - If all criteria are met, update ROADMAP.md to mark the use case status as "Complete"
   - If not complete, note what remains and ensure follow-up tasks exist
4. **File follow-up issues** for any gaps discovered
5. **Summarize epic completion**: run `./scripts/stats.sh` and report what was built and use case status

IMPORTANT:
- Never edit `.beads/` by hand; use `bd` only.
- Always commit `.beads/issues.jsonl` with your doc changes.
- Track token usage and lines of code for every issue closed.
- **Update ROADMAP.md** when use cases are completed.

Show what you completed and what's next. When summarizing, run `./scripts/stats.sh` and include its output.
