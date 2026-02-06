# PRD: Stitch

## Problem

The prototype script do-work.sh executes tasks by picking an issue from beads, creating a git worktree, piping a prompt to Claude, merging the result, and closing the issue. This approach has reached its limits.

Prompt construction happens through bash string concatenation. The build_prompt function assembles a fixed template: task title, description, and generic instructions ("Read VISION.md and ARCHITECTURE.md for context"). Every task receives the same prompt shape regardless of whether the work is documentation, coding, or operations. A documentation task needs different context than a coding task: the former benefits from seeing related PRDs and style guides; the latter needs relevant source files, tests, and interface definitions. The script makes no distinction.

No context management exists. The script cannot determine what files are relevant to a task, what PRDs define the requirements, or what existing code the agent should understand. It tells the agent to read VISION and ARCHITECTURE for every task, which may be too much context for a small fix or not enough for a complex feature.

Quality gates are absent. The script merges whatever the agent produces, closes the task, and moves on. There is no check that tests pass, linters are clean, or the build succeeds. Defects propagate to main without evaluation.

The worktree workflow is implicit in bash control flow. Error handling amounts to `set -e`: any failure aborts the script. There is no structured cleanup on partial failure, no way to release a claimed task if the agent errors out, and no retry logic.

Token tracking does not exist. The script has no visibility into how many tokens the agent consumed or what the cost was.

## Goals

Stitch is the command that executes work through agents. We replace do-work.sh with a structured Go implementation that provides work type routing, minimal context assembly, quality gates, and proper lifecycle management.

1. Work type routing: documentation, coding, and operations tasks each follow a different context assembly strategy
2. Minimal context per task: assemble only the files, PRDs, and rules the agent needs for that specific task
3. Template-driven prompts: Go templates with substitution from crumb fields and project context, stored as crumbs and swappable per work type
4. Quality gates before closing: run tests, linter, and build for code tasks before marking completed
5. Git worktree isolation for code tasks: create branch, execute in worktree, merge on success, cleanup on failure
6. Proper lifecycle management: claim tasks atomically, release on failure, track tokens and LOC

## Requirements

### R1: Task Picker

Stitch queries the cupboard for crumbs in the ready state, filtered by work type if specified. The picker selects one crumb based on priority (if set) and work type compatibility.

```go
// Fetch ready crumbs, optionally filtered by work type
type PickerConfig struct {
    WorkType string // "documentation", "coding", "operations", or empty for any
    Limit    int    // Max crumbs to fetch; 1 for single task
}

func (s *Stitch) Pick(ctx context.Context, cfg PickerConfig) (*types.Crumb, error)
```

The picker uses Cupboard.GetTable("crumbs").Fetch() with a filter for state=ready. When multiple crumbs match, selection prefers higher priority values.

### R2: Claim and Release

When stitch picks a task, it claims the crumb by setting state to taken. The claim is atomic: if the crumb's state changed between fetch and update (another process claimed it), the claim fails and stitch picks again.

```go
func (s *Stitch) Claim(ctx context.Context, crumb *types.Crumb) error
func (s *Stitch) Release(ctx context.Context, crumb *types.Crumb, reason string) error
```

Release sets state back to ready (or failed if the reason indicates unrecoverable error) and records the reason in crumb metadata. This allows failed tasks to be retried.

| Table 1 Claim Outcomes |
|------------------------|

| Outcome | Action |
|---------|--------|
| Claim succeeds | Proceed with execution |
| Crumb already taken | Pick another crumb |
| Crumb not found | Error; log and continue |
| Other error | Return error to caller |

### R3: Context Assembler

The context assembler gathers files relevant to a task based on its work type. Each work type has a different assembly strategy.

| Table 2 Context Assembly by Work Type |
|---------------------------------------|

| Work Type | Context Sources | What Gets Assembled |
|-----------|-----------------|---------------------|
| documentation | docs/, .claude/rules/, PRDs | Style guides, related docs, PRD sections, format rules |
| coding | source files, tests, PRDs, interfaces | Relevant packages, test files, interface definitions, PRD requirements |
| operations | configs, build output, CI | Config files, recent build logs, CI definitions |

The assembler reads the crumb's description and metadata to identify required reading (files explicitly listed) and infers related files from the task context (e.g., if modifying pkg/foo, include pkg/foo/*.go and tests).

```go
type AssembledContext struct {
    Files       []FileContent   // File paths and contents
    Rules       []string        // Applicable .claude/rules/*.md
    PRDSections []string        // Relevant PRD excerpts
}

func (s *Stitch) AssembleContext(ctx context.Context, crumb *types.Crumb) (*AssembledContext, error)
```

### R4: Prompt Builder

The prompt builder constructs prompts from Go templates. Templates live in internal/prompt as embedded strings. The builder substitutes crumb fields and assembled context into template variables.

| Table 3 Template Variables |
|----------------------------|

| Variable | Source | Description |
|----------|--------|-------------|
| .TaskID | Crumb.CrumbID | Unique identifier for the task |
| .TaskTitle | Crumb.Name | Human-readable task title |
| .TaskDescription | Crumb property | Full task description |
| .TaskType | Crumb property (work_type) | documentation, coding, or operations |
| .AcceptanceCriteria | Crumb property | List of acceptance criteria |
| .RequiredReading | AssembledContext.Files | Files the agent must read |
| .Rules | AssembledContext.Rules | Project rules that apply |
| .PRDContext | AssembledContext.PRDSections | Relevant PRD content |
| .Instructions | Template-defined | Work-type-specific instructions |

```go
type PromptBuilder struct {
    templates map[string]*template.Template // keyed by work type
}

func (b *PromptBuilder) Build(crumb *types.Crumb, context *AssembledContext) (string, error)
```

Templates are versioned. The builder loads the template for the crumb's work type; if a crumb specifies a template override in metadata, the builder uses that instead.

### R5: Agent Dispatch

Stitch invokes the agent interface (see prd-agent-interface) with the assembled prompt and registered tools. The agent executes the task; stitch manages the conversation loop.

```go
func (s *Stitch) Dispatch(ctx context.Context, prompt string, tools []agent.Tool) (agent.Response, error)
```

Dispatch creates a Request with the prompt as the initial user message, passes configured tools, and runs the conversation loop until completion or error. The executor tracks metrics (tokens, invocations) across the loop.

| Table 4 Tools by Work Type |
|----------------------------|

| Work Type | Tools Registered |
|-----------|------------------|
| documentation | read_file, write_file, list_files |
| coding | read_file, write_file, list_files, run_tests, run_linter |
| operations | read_file, write_file, run_command |

Tools are defined in internal/tools and implement the Tool interface from pkg/agent.

### R6: Git Worktree Management

For coding tasks, stitch creates a git worktree on a branch named after the task ID. All agent execution happens in the worktree. On success, stitch merges the branch; on failure, stitch cleans up without merging.

| Table 5 Worktree Lifecycle |
|----------------------------|

| Step | Action | On Failure |
|------|--------|------------|
| 1. Create branch | git branch task/[id] from current HEAD | Abort; release crumb |
| 2. Add worktree | git worktree add /tmp/project-worktrees/[id] task/[id] | Delete branch; abort |
| 3. Run agent | Execute in worktree directory | Skip merge; cleanup |
| 4. Run quality gates | Tests, linter, build in worktree | Skip merge; cleanup |
| 5. Merge | git merge task/[id] --no-edit | Cleanup; mark failed |
| 6. Cleanup | git worktree remove, git branch -d | Log error; continue |

Documentation tasks do not use worktrees; they execute directly in the main repository.

```go
type Worktree struct {
    Branch  string // task/[id]
    Path    string // /tmp/project-worktrees/[id]
}

func (s *Stitch) CreateWorktree(ctx context.Context, taskID string) (*Worktree, error)
func (s *Stitch) MergeWorktree(ctx context.Context, wt *Worktree) error
func (s *Stitch) CleanupWorktree(ctx context.Context, wt *Worktree) error
```

### R7: Quality Gate Execution

Before marking a coding task completed, stitch runs quality gates in the worktree. All gates must pass; any failure prevents merge and marks the task for review.

| Table 6 Quality Gates |
|-----------------------|

| Gate | Command | Pass Condition |
|------|---------|----------------|
| Tests | go test ./... | Exit code 0 |
| Linter | golangci-lint run | Exit code 0 |
| Build | go build ./... | Exit code 0 |

Quality gate configuration comes from cobbler's config file. Projects can customize the commands or disable specific gates.

```go
type QualityGateConfig struct {
    TestCommand   string // default: "go test ./..."
    LintCommand   string // default: "golangci-lint run"
    BuildCommand  string // default: "go build ./..."
    SkipTests     bool
    SkipLint      bool
    SkipBuild     bool
}

func (s *Stitch) RunQualityGates(ctx context.Context, wt *Worktree) error
```

Documentation tasks run a lighter gate: check that the output file exists and has content.

### R8: Crumb State Transitions

Stitch manages crumb state through the task lifecycle. State transitions use Cupboard.GetTable("crumbs").Set() to update the crumb.

| Table 7 State Transitions |
|---------------------------|

| From State | To State | Trigger | Metadata Updated |
|------------|----------|---------|------------------|
| ready | taken | Claim succeeds | claimed_at, claimed_by |
| taken | completed | Quality gates pass, merge succeeds | completed_at, tokens_used, loc_delta |
| taken | failed | Agent error, quality gate failure, merge conflict | failed_at, failure_reason |
| taken | ready | Release (retryable failure) | released_at, release_reason |

State transitions align with crumbs prd-crumbs-interface. The valid states are: draft, pending, ready, taken, completed, failed, archived. Stitch operates on ready crumbs and moves them to taken, then to completed or failed.

### R9: Token and LOC Tracking

Stitch tracks token usage and lines-of-code changes for each task. Metrics are recorded in crumb metadata and available for reporting.

```go
type ExecutionMetrics struct {
    TokensUsed       int       // Total tokens (input + output) across conversation
    LOCDelta         int       // Lines of code changed (additions - deletions)
    LOCProd          int       // Production code LOC
    LOCTest          int       // Test code LOC
    DocWordsDelta    int       // Documentation word count change
    Duration         time.Duration
    AgentInvocations int       // Number of Agent.Run calls
}
```

Token counts come from the agent response (see prd-agent-interface R7). LOC counts use the project's stats.sh script or equivalent Go implementation.

### R10: Template System

Prompt templates are stored as crumbs in the cupboard with work_type=template. Each template crumb contains the Go template text in its description field and metadata indicating which work types it applies to.

| Table 8 Template Crumbs |
|-------------------------|

| Template Name | Applies To | Purpose |
|---------------|------------|---------|
| prompt-documentation | documentation | Default prompt for doc tasks |
| prompt-coding | coding | Default prompt for code tasks |
| prompt-operations | operations | Default prompt for ops tasks |

Stitch loads the appropriate template crumb at runtime. If no template crumb exists for a work type, stitch falls back to embedded defaults.

This design enables:
- Swapping templates without code changes
- A/B testing different prompt strategies
- Agent (via pattern command) modifying how stitch builds prompts

```go
func (s *Stitch) LoadTemplate(ctx context.Context, workType string) (*template.Template, error)
```

## Non-Goals

We do not implement parallel task execution in v1. Stitch executes one task at a time. Parallel execution requires additional coordination (work stealing, lock management) deferred to a future phase.

We do not modify templates during stitch execution. Stitch reads templates; the pattern command modifies them. Separation prevents feedback loops where the agent changes its own prompt mid-task.

We do not integrate with measure. Measure creates work; stitch executes it. The commands share the cupboard but operate independently.

We do not support interactive agent sessions. Stitch dispatches one-shot; the agent receives everything upfront and returns a result. Interactive workflows (agent asks clarifying questions, human responds) are out of scope.

We do not implement automatic retries of failed tasks. When a task fails, stitch records the failure and moves on. Retry logic belongs in a scheduler layer above stitch.

## Acceptance Criteria

- [ ] Task picker queries cupboard for ready crumbs with optional work type filter
- [ ] Claim sets crumb state to taken atomically; release restores to ready or failed
- [ ] Context assembly strategy differs by work type (documentation, coding, operations)
- [ ] Prompt builder uses Go templates with substitution from crumb fields and assembled context
- [ ] Template variables include TaskID, TaskTitle, TaskDescription, TaskType, AcceptanceCriteria, RequiredReading, Rules, PRDContext
- [ ] Agent dispatch uses the Agent interface from prd-agent-interface
- [ ] Tools registered per work type (read_file, write_file, list_files, run_tests, run_linter, run_command)
- [ ] Git worktree created for coding tasks: branch task/[id], path /tmp/project-worktrees/[id]
- [ ] Worktree lifecycle handles create, merge, cleanup with proper error recovery
- [ ] Quality gates run before closing coding tasks: tests, linter, build
- [ ] Quality gate configuration allows customization and per-gate skip
- [ ] State transitions: ready to taken to completed/failed; release returns to ready
- [ ] Token tracking per task recorded in crumb metadata
- [ ] LOC tracking per task recorded in crumb metadata
- [ ] Templates stored as crumbs with work_type=template; loaded at runtime
- [ ] Fallback to embedded templates when template crumb not found
- [ ] File saved as prd-stitch.md in docs/product-requirements/
