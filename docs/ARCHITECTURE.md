# Cobbler Architecture

## System Overview

Cobbler orchestrates AI coding agents through four autogenic capabilities: self-orienting (measure), self-programming (stitch), self-reflecting (inspect, mend), and self-architecting (pattern). We import the crumbs Go module and access the cupboard interface directly to read work items, coordinate agent execution, and update task state. The core insight is that agent orchestration separates naturally into phases: assess project state, execute work, evaluate output, and propose design changes.

Cobbler replaces prototype bash scripts (make-work.sh and do-work.sh) with a structured Go CLI. Where the scripts built prompts through string concatenation and shelled out to bd commands, cobbler uses Go templates for prompt construction and calls cupboard methods directly via the imported crumbs module.

### Lifecycle

A work item flows through cobbler in stages.

| Table 1 Work Item Lifecycle |
|-----------------------------|

| Stage | State | What happens |
|-------|-------|--------------|
| Ready | ready | Item exists in cupboard, eligible for pickup |
| Claimed | taken | Cobbler claims item via Table.Set, begins prompt construction |
| Executing | taken | Agent receives prompt, produces output |
| Quality gate | taken | Cobbler runs validation (tests, linter, build) |
| Closed | completed or failed | Cobbler updates state, records outcome |

The crumbs Crumb entity has states: draft, pending, ready, taken, completed, failed, archived. Cobbler operates on crumbs in the ready state and transitions them through taken to completed or failed. See crumbs prd-crumbs-interface for the full state machine.

### Coordination Pattern

Cobbler uses pull-based coordination. The CLI queries the cupboard for crumbs in the ready state, picks one, claims it by setting state to taken, and proceeds with execution. No push notifications or pub/sub announcements exist; the agent (cobbler) drives all state transitions.

This pattern matches the crumbs design: crumbs provides storage, not coordination. Agents or coordination frameworks build claiming, timeouts, and announcements on top of the Cupboard API (crumbs ARCHITECTURE).

### Git Worktree Model

For code tasks, cobbler creates a git worktree on a branch named after the task ID. The agent executes in the worktree, commits changes, and cobbler merges the branch back to main. This isolates work-in-progress from the main branch and enables parallel task execution in future phases.

| Table 2 Worktree Workflow |
|---------------------------|

| Step | Action | Location |
|------|--------|----------|
| 1 | Create branch task/[id] | Main repo |
| 2 | Add worktree at /tmp/project-worktrees/[id] | Worktree |
| 3 | Run agent | Worktree |
| 4 | Merge branch to main | Main repo |
| 5 | Remove worktree, delete branch | Cleanup |

## Main Interfaces

Cobbler integrates with crumbs via the imported Go module and defines internal interfaces for agent abstraction and prompt construction.

### Cupboard Integration

We import github.com/petar-djukic/crumbs and use the Cupboard and Table interfaces directly. There is no CrumbsTable.Get(); callers use the pattern Cupboard.GetTable("crumbs").Get(id).

```go
// Cupboard access pattern
cupboard := sqlite.NewCupboard()
cupboard.Attach(types.Config{Backend: "sqlite", DataDir: ".crumbs"})
defer cupboard.Detach()

table, _ := cupboard.GetTable("crumbs")
entity, _ := table.Get(crumbID)
crumb := entity.(*types.Crumb)
```

The Table interface provides uniform CRUD operations.

| Table 3 Table Operations |
|--------------------------|

| Operation | Purpose |
|-----------|---------|
| Get(id) | Retrieve entity by ID |
| Set(id, data) | Create or update entity |
| Delete(id) | Remove entity |
| Fetch(filter) | Query with field filter |

Attach and Detach manage the cupboard lifecycle. Attach accepts a Config struct with Backend (sqlite, dolt, dynamodb) and backend-specific parameters. Detach releases resources and blocks until in-flight operations complete. See crumbs prd-cupboard-core for the full specification.

### Agent Interface

The Agent interface abstracts LLM providers. We start with Claude via anthropic-sdk-go; the interface enables future providers without changing orchestration code.

```go
type Agent interface {
    Run(ctx context.Context, prompt string, tools []Tool) (Response, error)
}

type Tool interface {
    Name() string
    Description() string
    Execute(ctx context.Context, args map[string]any) (any, error)
}

type Response struct {
    Content    string
    ToolCalls  []ToolCall
    TokensUsed int
}
```

The Agent.Run method sends a prompt to the LLM with available tools. The response includes generated content, tool call requests, and token usage. The executor manages the conversation loop: send prompt, execute tool calls, send results, repeat until the agent signals completion.

### Executor Interface

The Executor coordinates the claim-execute-close workflow for a single task.

```go
type Executor interface {
    Execute(ctx context.Context, crumb *types.Crumb) error
}
```

Execute claims the crumb, builds a prompt, runs the agent loop, validates output, and updates crumb state. On success, the crumb moves to completed; on failure, to failed with error details in metadata.

### Prompt Builder

The Prompt Builder constructs prompts from templates and task context. Templates live in internal/prompt as Go templates or embedded strings. The builder substitutes task fields (title, description, acceptance criteria) and project context (file paths, rules).

| Table 4 Prompt Template Variables |
|-----------------------------------|

| Variable | Source |
|----------|--------|
| TaskID | Crumb.CrumbID |
| TaskTitle | Crumb.Name |
| TaskDescription | Crumb property or metadata |
| ProjectRules | .claude/rules/*.md |
| RelatedDocs | PRDs, ARCHITECTURE sections |

## System Components

**CLI (cmd/cobbler)**: Entry point using cobra for command parsing. Commands: measure, stitch, inspect, mend, pattern. Each command maps to an autogenic self-* capability. Viper loads configuration from file and environment.

| Table 5 Commands and Capabilities |
|-----------------------------------|

| Command | Self-* capability | What it does |
|---------|-------------------|--------------|
| measure | Self-orienting | Assess project state, propose tasks |
| stitch | Self-programming | Execute work via AI agents |
| inspect | Self-reflecting | Evaluate output quality |
| mend | Self-reflecting | Fix issues found by inspect |
| pattern | Self-architecting | Propose design and structural changes |

**Config (internal/config)**: Loads and validates configuration. Cupboard settings (backend, data directory), agent settings (API keys, model selection), and execution settings (worktree base path, timeout).

**Measure (internal/measure)**: Reads VISION, ARCHITECTURE, ROADMAP, and cupboard state. Invokes an agent to analyze project state and propose new crumbs. Replaces make-work.sh. Output is a set of proposed crumbs that the user reviews before import.

**Stitch (internal/stitch)**: Picks a ready crumb, claims it, builds a prompt, runs the agent, validates output, and closes the crumb. Replaces do-work.sh. Handles both documentation tasks (write markdown) and code tasks (git worktree, merge).

**Inspect (internal/inspect)**: Evaluates recent work for quality issues. Runs an agent with inspection prompts (check tests pass, linter clean, docs complete). Reports findings without making changes.

**Mend (internal/mend)**: Fixes issues identified by inspect. Claims a crumb with findings, invokes an agent to make corrections, validates the fix.

**Pattern (internal/pattern)**: Proposes architectural changes. Analyzes project structure, identifies technical debt or design improvements, outputs proposals as new crumbs or documentation updates.

**Agent (internal/claude)**: Claude implementation of the Agent interface using anthropic-sdk-go. Manages API calls, streaming responses, and tool execution. Handles rate limiting and retries.

**Crumbs Client (internal/crumbs)**: Thin wrapper around the imported crumbs module. Provides convenience methods for common operations: fetch ready crumbs, claim crumb, close crumb, add metadata. Does not duplicate Table interface functionality.

## Design Decisions

**Decision 1: Import crumbs as Go module, not CLI wrapper.** We import github.com/petar-djukic/crumbs and call cupboard methods directly. Benefits: type safety, no process spawning overhead, direct access to entity structs. Alternative rejected: wrapping bd CLI commands loses type information and adds shell parsing complexity.

**Decision 2: Agent interface for provider abstraction.** The Agent interface decouples orchestration from LLM provider. We implement Claude first via anthropic-sdk-go. Benefits: add providers without changing executor code, test with mock agents. Alternative rejected: hardcoding Claude calls spreads provider-specific logic throughout the codebase.

**Decision 3: Prompt templates in internal/prompt.** Templates are Go templates or embedded strings in the internal/prompt package. Benefits: templates are testable Go code, IDE support for editing, compile-time errors for missing variables. Alternative rejected: external template files add deployment complexity and make testing harder.

**Decision 4: Commands named after shoemaking terms.** Cobbler commands (measure, stitch, inspect, mend, pattern) follow the shoemaking metaphor. Benefits: memorable naming, consistent theme with project name. Each command maps to an autogenic self-* capability, grounding the metaphor in the research context.

**Decision 5: Git worktree isolation for code tasks.** Code tasks execute in a worktree on a task-specific branch. Benefits: main branch stays clean during execution, multiple tasks can run in parallel (future), failed tasks leave main unaffected. Alternative rejected: working directly on main risks leaving partial changes on failure.

**Decision 6: Quality gates before closing.** The executor runs validation (tests, linter, build) before marking a crumb completed. Benefits: catch failures before closing, enable mend to fix issues. Alternative rejected: closing immediately after agent output loses the feedback loop.

## Technology Choices

| Table 6 Technology Stack |
|--------------------------|

| Component | Technology | Purpose |
|-----------|------------|---------|
| Language | Go | CLI tool; strong typing, concurrency, single binary |
| CLI framework | cobra | Command parsing, help generation, subcommands |
| Configuration | viper | File and environment config, YAML/JSON support |
| Cupboard | github.com/petar-djukic/crumbs | Work item storage; imported as Go module |
| LLM client | anthropic-sdk-go | Claude API; streaming, tool use |
| Testing | Go testing + testify | Unit and integration tests |

## Project Structure

```
cobbler/
├── cmd/
│   └── cobbler/          # CLI entry point, cobra root command
├── pkg/
│   ├── agent/            # Agent and Tool interfaces (public API)
│   └── executor/         # Executor interface (public API)
├── internal/
│   ├── config/           # Configuration loading and validation
│   ├── claude/           # Claude Agent implementation
│   ├── prompt/           # Prompt templates and builder
│   ├── measure/          # Measure command logic
│   ├── stitch/           # Stitch command logic (executor impl)
│   ├── inspect/          # Inspect command logic
│   ├── mend/             # Mend command logic
│   ├── pattern/          # Pattern command logic
│   └── crumbs/           # Crumbs cupboard convenience wrapper
├── docs/
│   ├── VISION.md
│   ├── ARCHITECTURE.md
│   ├── product-requirements/
│   └── use-cases/
└── .claude/              # Project rules for AI agents
```

**cmd/cobbler**: CLI entry point. Registers subcommands (measure, stitch, inspect, mend, pattern) with cobra. Initializes config via viper.

**pkg/agent**: Public Agent and Tool interfaces. Other modules may import these to implement agents or build tooling.

**pkg/executor**: Public Executor interface. Defines the contract for claim-execute-close workflows.

**internal/config**: Private configuration. Loads from file (~/.cobbler/config.yaml) and environment (COBBLER_* vars). Validates required fields.

**internal/claude**: Private Claude implementation. Implements Agent interface using anthropic-sdk-go. Handles API calls, streaming, tool execution.

**internal/prompt**: Private prompt construction. Go templates for documentation and code tasks. Template variables from crumb fields and project context.

**internal/measure, internal/stitch, internal/inspect, internal/mend, internal/pattern**: Private command implementations. Each package contains the logic for its respective command.

**internal/crumbs**: Private cupboard wrapper. Convenience methods built on the imported crumbs module.

## Implementation Status

We are in phase 01.0: stitch for documentation. The focus is cobbler stitch executing documentation tasks with cupboard read/write via the crumbs module and prompt templates for doc work.

| Table 7 Implementation Phases |
|-------------------------------|

| Phase | Focus | Status |
|-------|-------|--------|
| 01.0 | Stitch for documentation | Current |
| 02.0 | Stitch for code | Planned |
| 03.0 | Measure | Planned |
| 04.0 | Inspect, mend, pattern | Planned |

Success criteria from VISION: autonomous execution (agents complete tasks without intervention), cupboard integration (direct Go calls, no shell commands), graduated prototypes (make-work.sh and do-work.sh become obsolete).

## Related Documents

| Table 8 Related Documents |
|---------------------------|

| Document | Purpose |
|----------|---------|
| VISION.md | Goals, boundaries, phases, success criteria |
| prd-cupboard-core.md (crumbs) | Cupboard interface, Table interface, lifecycle |
| prd-crumbs-interface.md (crumbs) | Crumb entity, state transitions, properties |
| prd-trails-interface.md (crumbs) | Trail entity, exploration sessions |

## References

See crumbs ARCHITECTURE.md and PRDs for cupboard interface details. See VISION.md for project goals and boundaries.
