# PRD Format

## Required Sections

1. **Problem** - What problem are we solving? Why now? Why does it matter?
2. **Goals** - Measurable objectives for this feature (what success looks like)
3. **Requirements** - Numbered functional requirements (what the system must do)
4. **Non-Goals** - Explicit scope boundaries (what we are NOT building)
5. **Acceptance Criteria** - How we verify the feature is complete

## Optional Sections

6. **Constraints** - Technical or business limitations that affect scope
7. **Open Questions** - Unresolved issues requiring further discussion

## Writing Guidelines

- **Audience**: Junior developer (explicit, no jargon)
- **Format**: Markdown in `/docs/product-requirements/prd-[feature-name].md`
- **Requirements**: Numbered, specific, actionable (e.g., "The system must allow users to...")
- **Style**: Follow documentation standards (concise, active voice)

## Before Writing

Ask 3-5 clarifying questions if the request is ambiguous:
- Number questions (1, 2, 3)
- List options as A, B, C for easy selection
- Focus on: Problem clarity, Core functionality, Scope boundaries

## Completeness Checklist

- [ ] Problem clearly states what we're solving and why it matters
- [ ] Goals are measurable
- [ ] Requirements are numbered and specific
- [ ] Non-Goals define what's out of scope
- [ ] Acceptance Criteria answer "how do we know it's done?"
- [ ] File saved as `prd-[feature-name].md` in `/docs/product-requirements/`
