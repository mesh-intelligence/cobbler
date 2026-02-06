# PRD: Measure

## Problem

The prototype script make-work.sh assesses project state and proposes new tasks by invoking Claude with a monolithic prompt. This approach has several deficiencies.

No structured project state reader exists. The script tells Claude to read VISION.md, ARCHITECTURE.md, ROADMAP.md, and issue files itself. Claude must discover project state during execution rather than receiving it as structured input. This wastes tokens on file reads and produces inconsistent assessments depending on what Claude happens to find.

Context assembly is everything-at-once. The build_prompt function concatenates all existing issues as JSON, generic instructions, and appended user prompts into a single string. There is no curation. A project with fifty open issues sends all fifty to Claude, even if only five are relevant to the current release. The prompt grows without bound and context quality degrades.

Output goes through an intermediate JSON file. Claude writes proposed issues to docs/proposed-issues-TIMESTAMP.json. A separate bash function import_issues parses that file and calls bd create for each issue. Two failure points exist: Claude may produce malformed JSON, and the import function may fail mid-way leaving partial state. There is no direct write to the cupboard.

Work type is implicit. The script does not set a type property on created issues. Downstream (stitch) must infer whether a task is documentation, coding, or operations from the description text rather than structured metadata.

Roadmap alignment is advisory. The script instructs Claude to map issues to use cases in ROADMAP.md, but there is no enforcement. Proposed issues may reference non-existent releases or omit release assignment entirely.

## Goals

We replace make-work.sh with a structured Go implementation that reads project state, curates context for a planning agent, invokes the agent, and writes proposed crumbs directly to the cupboard.

1. Structured project state reader that collects VISION, ARCHITECTURE, roadmap, and cupboard state before agent invocation
2. Curated context for the planning agent: current release focus, incomplete use cases, existing work filtered by relevance, and project stats
3. Direct cupboard write-back: proposed crumbs go straight to Cupboard.GetTable("crumbs").Set(), no intermediate JSON file
4. Work type assignment: each proposed crumb receives a work_type property (planning, documentation, coding, operations)
5. Roadmap-aware proposals: issues map to use cases; unassigned work defaults to release 99.0
6. Review mode: option to output proposals for human review before writing to cupboard

## Requirements

### R1: Project State Reader

Measure reads project state from known locations into a structured representation. The reader runs before agent invocation so the agent receives curated input rather than discovering files itself.

| Table 1 Project State Sources |
|-------------------------------|

| Source | Path | What We Extract |
|--------|------|-----------------|
| Vision | docs/VISION.md | Goals, boundaries, success criteria, phases |
| Architecture | docs/ARCHITECTURE.md | Components, interfaces, design decisions, implementation status |
| Roadmap | docs/ROADMAP.md or ROADMAP.md | Releases, use cases, completion status |
| Cupboard | Cupboard.GetTable("crumbs") | Existing crumbs with state, work type, parent/child relationships |
| Stats | scripts/stats.sh output | LOC (production), LOC (tests), doc word count |

```go
type ProjectState struct {
    Vision       string            // VISION.md content (summarized if large)
    Architecture string            // ARCHITECTURE.md content (summarized if large)
    Roadmap      *RoadmapState     // Parsed roadmap structure
    Crumbs       []CrumbSummary    // Existing work items
    Stats        ProjectStats      // LOC and doc metrics
}

type RoadmapState struct {
    CurrentRelease string          // e.g., "01.0"
    Releases       []Release       // All releases with status
}

type Release struct {
    ID         string              // e.g., "01.0", "02.0"
    Focus      string              // Short description
    UseCases   []UseCase           // Use cases in this release
    Status     string              // "current", "planned", "complete"
}

type UseCase struct {
    ID          string             // e.g., "uc-001"
    Name        string             // Short name
    IsComplete  bool               // Whether implemented
}

type CrumbSummary struct {
    ID          string
    Name        string
    State       string             // ready, taken, completed, failed, etc.
    WorkType    string             // planning, documentation, coding, operations
    Parent      string             // Parent crumb ID if any
    Release     string             // Assigned release if any
}

type ProjectStats struct {
    LOCProd     int                // Production code lines
    LOCTest     int                // Test code lines
    DocWords    int                // Documentation word count
}
```

### R2: Context Assembly

Measure assembles a curated context for the planning agent. Unlike make-work.sh which dumps everything, measure filters and summarizes based on the current release and planning scope.

| Table 2 Context Assembly Strategy |
|-----------------------------------|

| Element | What Gets Included | What Gets Excluded |
|---------|--------------------|--------------------|
| Roadmap | Current release, incomplete use cases, next release preview | Completed releases, far-future releases |
| Existing crumbs | Ready, pending, in-progress items relevant to current release | Completed items, archived items, unrelated releases |
| Stats | Current LOC and doc metrics | Historical snapshots |
| Vision/Architecture | Summaries or excerpts relevant to current focus | Full documents (agent can read if needed) |

Context assembly produces a planning context struct suitable for template substitution.

```go
type PlanningContext struct {
    CurrentRelease      string           // Release we are working on
    ReleaseDescription  string           // What this release delivers
    IncompleteUseCases  []UseCase        // Use cases not yet done
    ExistingWork        []CrumbSummary   // Relevant in-flight work
    RecentlyCompleted   []CrumbSummary   // Recent completions for context
    ProjectStats        ProjectStats     // Current metrics
    VisionExcerpt       string           // Goals and boundaries
    ArchitectureExcerpt string           // Relevant components
}

func (m *Measure) AssembleContext(ctx context.Context, state *ProjectState) (*PlanningContext, error)
```

### R3: Agent Dispatch

Measure invokes the agent interface (see prd-agent-interface) with a planning prompt. The agent analyzes project state and outputs proposed crumbs.

```go
func (m *Measure) Dispatch(ctx context.Context, planCtx *PlanningContext) ([]ProposedCrumb, error)
```

Dispatch constructs a prompt from the planning context using a template (see R8), invokes Agent.Run, and parses the response into structured proposals. The agent may use tools (read_file to inspect specific files) but receives curated context upfront so tool use is minimized.

| Table 3 Dispatch Responsibilities |
|-----------------------------------|

| Responsibility | How |
|----------------|-----|
| Prompt construction | Template substitution with PlanningContext fields |
| Agent invocation | Agent.Run per prd-agent-interface |
| Response parsing | Extract proposals from agent output |
| Validation | Verify proposals have required fields |

### R4: Proposal Format

The agent outputs proposed crumbs in a structured format. Each proposal includes fields needed to create a crumb.

```go
type ProposedCrumb struct {
    Title       string            // Short descriptive title
    Description string            // Full description per issue-format
    WorkType    string            // planning, documentation, coding, operations
    Priority    int               // Relative priority (higher = more important)
    Release     string            // Target release (e.g., "01.0", "99.0")
    UseCase     string            // Related use case ID if any
    Labels      []string          // Optional labels
}
```

| Table 4 Required Proposal Fields |
|----------------------------------|

| Field | Required | Default if Missing |
|-------|----------|-------------------|
| Title | Yes | Error: cannot create |
| Description | Yes | Error: cannot create |
| WorkType | Yes | Error: cannot create |
| Priority | No | 0 (lowest) |
| Release | No | "99.0" (unscheduled) |
| UseCase | No | Empty |
| Labels | No | Empty |

Descriptions must follow issue-format: Required Reading, Files to Create/Modify, Requirements, and Acceptance Criteria sections.

### R5: Cupboard Write-Back

When operating in write mode (not review mode), measure writes approved proposals directly to the cupboard via Table.Set. No intermediate JSON file.

```go
func (m *Measure) WriteProposals(ctx context.Context, proposals []ProposedCrumb) ([]string, error)
```

WriteProposals iterates through proposals and creates crumbs. It returns the list of created crumb IDs. Each crumb is created with state=pending (not ready) so a human can review before making them available for stitch.

| Table 5 Crumb Creation Fields |
|-------------------------------|

| Crumb Field | Source |
|-------------|--------|
| Name | ProposedCrumb.Title |
| State | pending |
| Properties.description | ProposedCrumb.Description |
| Properties.work_type | ProposedCrumb.WorkType |
| Properties.priority | ProposedCrumb.Priority |
| Properties.release | ProposedCrumb.Release |
| Properties.use_case | ProposedCrumb.UseCase |
| Properties.labels | ProposedCrumb.Labels |
| Properties.created_by | "measure" |

### R6: Work Type Assignment

Every proposed crumb must have a work_type property set. The planning agent assigns type based on the nature of the work.

| Table 6 Work Types |
|--------------------|

| Type | Definition | Examples |
|------|------------|----------|
| planning | Work cobbler does internally | Assess state, analyze dependencies |
| documentation | Markdown output in docs/ | PRDs, use cases, architecture updates |
| coding | Implementation code | Features, bug fixes, tests |
| operations | Config and maintenance | CI updates, dependency upgrades, scripts |

The agent determines work type from the task description. Measure validates that work_type is one of the four allowed values; invalid types cause the proposal to be rejected with an error.

### R7: Roadmap Alignment

Proposals should map to use cases in the roadmap. Measure validates release assignments against known releases.

| Table 7 Roadmap Validation |
|----------------------------|

| Validation | Behavior |
|------------|----------|
| Release exists | Accept proposal |
| Release does not exist | Warn, set to "99.0" |
| Use case exists in release | Accept proposal |
| Use case does not exist | Accept proposal (use case may be new) |

Proposals for use cases not in the roadmap are allowed; the roadmap itself may need updating. The warning surfaces misalignment for human review.

```go
func (m *Measure) ValidateRoadmapAlignment(proposal *ProposedCrumb, roadmap *RoadmapState) []Warning
```

### R8: Review Mode

Measure supports two modes: write mode and review mode. In review mode, proposals are displayed for human review but not written to the cupboard.

```go
type MeasureConfig struct {
    ReviewMode bool              // If true, output proposals without writing
    IssueLimit int               // Max proposals per invocation (default: 10)
    WorkTypes  []string          // Filter to specific work types, or empty for all
}

func (m *Measure) Run(ctx context.Context, cfg MeasureConfig) (*MeasureResult, error)

type MeasureResult struct {
    Proposals     []ProposedCrumb // Proposed crumbs
    CreatedIDs    []string        // IDs of created crumbs (empty in review mode)
    Warnings      []string        // Validation warnings
    TokensUsed    int             // Tokens consumed
}
```

In review mode, Run returns proposals in MeasureResult.Proposals without calling WriteProposals. The human reviews and may run again in write mode.

### R9: Issue Limit

Measure accepts a configurable limit on proposals per invocation. This prevents unbounded task creation.

```go
// In MeasureConfig
IssueLimit int  // Max proposals; default 10
```

The limit is passed to the planning agent in the prompt. If the agent produces more than IssueLimit proposals, measure takes the first IssueLimit by priority.

### R10: Planning Prompt Template

Measure uses a Go template for the planning prompt. The template is stored as a crumb with work_type=template, similar to stitch templates (see prd-stitch R10).

| Table 8 Template Variables |
|----------------------------|

| Variable | Source |
|----------|--------|
| .CurrentRelease | PlanningContext.CurrentRelease |
| .ReleaseDescription | PlanningContext.ReleaseDescription |
| .IncompleteUseCases | PlanningContext.IncompleteUseCases |
| .ExistingWork | PlanningContext.ExistingWork |
| .RecentlyCompleted | PlanningContext.RecentlyCompleted |
| .Stats | PlanningContext.ProjectStats |
| .Vision | PlanningContext.VisionExcerpt |
| .Architecture | PlanningContext.ArchitectureExcerpt |
| .IssueLimit | MeasureConfig.IssueLimit |

```go
func (m *Measure) LoadTemplate(ctx context.Context) (*template.Template, error)
```

If no template crumb exists, measure falls back to an embedded default template.

## Non-Goals

We do not implement autonomous approval in v1. Crumbs are created in pending state. A human reviews and transitions to ready before stitch picks them up. Autonomous approval requires confidence scoring and validation beyond v1 scope.

We do not support multi-project analysis. Measure operates on a single project (the current working directory). Cross-project coordination is out of scope.

We do not modify the roadmap or VISION. Measure reads these documents; pattern modifies them. Separation prevents measure from expanding its own scope.

We do not run stitch after measure. Measure proposes work; stitch executes it. The development loop (measure then stitch then inspect) is orchestrated by the user or a future scheduler, not by measure itself.

We do not implement dependency ordering. Measure may note dependencies in proposal descriptions, but it does not enforce execution order. That logic belongs in stitch or a scheduler.

## Acceptance Criteria

- [ ] Project state reader extracts VISION, ARCHITECTURE, roadmap, crumbs, and stats into ProjectState struct
- [ ] Roadmap parser identifies current release, incomplete use cases, and release status
- [ ] Context assembly filters crumbs and summarizes documents based on current release focus
- [ ] Planning context struct includes all fields for template substitution
- [ ] Agent dispatch uses Agent interface from prd-agent-interface
- [ ] Proposal format requires title, description, and work_type; optional priority, release, use_case, labels
- [ ] Cupboard write-back creates crumbs with state=pending via Table.Set
- [ ] Work type property set on every created crumb (planning, documentation, coding, operations)
- [ ] Roadmap alignment validation warns on unknown releases and defaults to 99.0
- [ ] Review mode outputs proposals without writing to cupboard
- [ ] Write mode creates crumbs and returns IDs
- [ ] Issue limit configurable; default 10
- [ ] Template system loads from cupboard crumb or falls back to embedded default
- [ ] File saved as prd-measure.md in docs/product-requirements/
