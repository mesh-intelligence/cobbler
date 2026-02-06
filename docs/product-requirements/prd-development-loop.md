# PRD: Development Loop

## Problem

The prototype script do-work.sh implements a basic iterative loop: drain the task queue, call make-work when empty, repeat for N cycles. The main function (lines 217-251) picks tasks until the queue empties, invokes make-work.sh to propose new work, then continues. This covers two operations (measure and stitch) in a simple alternating pattern.

The loop has no evaluation step. After stitch completes a task, the loop moves to the next task without checking whether the output was any good. Defects accumulate undetected. There is no inspect to assess quality, no mend to fix problems, and no pattern to propose design improvements.

Path management does not exist. The vision describes the induction problem: each step layers code on existing code, and a bad sequence of steps produces tangled code that makes subsequent steps harder. The prototype has no mechanism to detect this. It cannot measure code quality trends, identify when a refactor is needed, or intervene before the path becomes unproductive.

The five operations (measure, stitch, inspect, mend, pattern) exist independently in the architecture documentation. Each has a defined purpose: measure assesses state and proposes tasks; stitch executes tasks; inspect evaluates output; mend fixes issues; pattern proposes structural changes. But there is no specification for how these operations compose into a cycle. When does inspect run relative to stitch? Under what conditions does the loop invoke mend versus pattern? What triggers a design review?

Human touchpoints are implicit. The prototype runs until cycles are exhausted, then stops. A human must read logs to understand what happened. There is no structured handoff, no summary of decisions that need judgment, and no explicit check-in point where the human can redirect work.

## Goals

We define the development loop: the full cycle that composes all five operations into an iterative method for managing the inductive development path. The loop replaces do-work.sh's simple drain-then-create pattern with a structured state machine that evaluates output, detects path degradation, and surfaces decisions for human review.

1. Single iterative loop composing measure, stitch, inspect, mend, and pattern
2. State machine with defined transitions between operations
3. Path health monitoring: detect when the codebase is degrading (test failures, lint violations, LOC growth rate) and trigger corrective operations
4. Configurable cycles: control how many measure-stitch iterations run before stopping
5. Failure recovery: handle task failures gracefully without aborting the loop
6. Metrics per cycle: tokens used, tasks completed/failed, LOC delta, doc words delta
7. Human touchpoints: report after each cycle with decisions that need judgment

## Requirements

### R1: Loop State Machine

The development loop operates as a state machine. Each state corresponds to an operation or a decision point.

| Table 1 Loop States |
|---------------------|

| State | Description |
|-------|-------------|
| idle | Loop not running; awaiting start command |
| measuring | Invoking measure to assess project state and propose work |
| stitching | Executing tasks via stitch |
| inspecting | Evaluating recent stitch output via inspect |
| mending | Fixing issues found by inspect via mend |
| patterning | Proposing design changes via pattern |
| reporting | Preparing human-readable summary for touchpoint |
| stopped | Loop terminated (cycles exhausted or human interrupt) |

State transitions follow defined rules. The loop enters a state, executes the operation, evaluates the result, and transitions to the next state based on conditions.

```go
type LoopState string

const (
    StateIdle       LoopState = "idle"
    StateMeasuring  LoopState = "measuring"
    StateStitching  LoopState = "stitching"
    StateInspecting LoopState = "inspecting"
    StateMending    LoopState = "mending"
    StatePatterning LoopState = "patterning"
    StateReporting  LoopState = "reporting"
    StateStopped    LoopState = "stopped"
)

type Loop struct {
    State         LoopState
    CycleCount    int
    MaxCycles     int
    CurrentBatch  []string  // Crumb IDs in current stitch batch
    HealthMetrics PathHealth
}
```

### R2: Default Operation Order

The loop follows a default order that covers the full development cycle. This order can be modified by configuration but provides a sensible baseline.

| Table 2 Default Operation Order |
|---------------------------------|

| Phase | Operation | Trigger | Next Phase |
|-------|-----------|---------|------------|
| 1 | Measure | Queue empty or cycle start | Stitch |
| 2 | Stitch | Tasks available | Inspect (after batch) |
| 3 | Inspect | Stitch batch complete | Mend (if issues) or Measure (if clean) |
| 4 | Mend | Inspect found issues | Inspect (verify fix) |
| 5 | Pattern | Path health degraded or periodic | Measure |

The loop starts by checking for ready work. If the queue is empty, it runs measure to propose tasks. Once tasks exist, it enters stitch to execute them. After completing a batch of tasks (configurable size, default all ready tasks), it runs inspect. If inspect finds issues, mend attempts fixes. Pattern runs when path health indicators degrade or on a periodic schedule.

### R3: Cycle Management

A cycle is one complete iteration through the default order: measure (if needed), stitch (drain queue), inspect, and optionally mend/pattern. The loop tracks cycle count and respects a maximum.

```go
type LoopConfig struct {
    MaxCycles      int    // 0 = unlimited until human stop
    BatchSize      int    // Tasks per stitch batch before inspect; 0 = all
    PatternPeriod  int    // Run pattern every N cycles; 0 = only on degradation
    StopOnFailure  bool   // Stop loop if any task fails
}

func (l *Loop) Run(ctx context.Context, cfg LoopConfig) (*LoopResult, error)
```

| Table 3 Cycle Configuration |
|-----------------------------|

| Parameter | Default | Description |
|-----------|---------|-------------|
| MaxCycles | 1 | Number of measure-stitch cycles; 0 for unlimited |
| BatchSize | 0 | Tasks per inspect; 0 means inspect after queue drained |
| PatternPeriod | 0 | Run pattern every N cycles; 0 means only on health issues |
| StopOnFailure | false | Whether a failed task stops the loop |

### R4: Queue Empty Handling

When stitch finds no ready tasks, the loop transitions to measuring. Measure proposes new work, writes crumbs to the cupboard, and the loop returns to stitching.

```go
func (l *Loop) handleEmptyQueue(ctx context.Context) error {
    l.State = StateMeasuring
    result, err := l.measure.Run(ctx, MeasureConfig{
        ReviewMode: false,
        IssueLimit: l.config.MeasureLimit,
    })
    if err != nil {
        return err
    }
    // Measure creates crumbs in pending state
    // Approve them to ready state for stitch
    for _, id := range result.CreatedIDs {
        l.approveCrumb(ctx, id)
    }
    l.State = StateStitching
    return nil
}
```

The approval step transitions crumbs from pending to ready. In autonomous mode (future), this happens automatically. In the current guided mode, the loop pauses for human review.

### R5: Failure Recovery

When stitch fails on a task, the loop records the failure and continues to the next task. Repeated failures within a batch trigger inspect to diagnose systemic issues.

| Table 4 Failure Handling |
|--------------------------|

| Condition | Action |
|-----------|--------|
| Single task fails | Mark crumb failed, log reason, continue to next task |
| Multiple failures in batch (> 50%) | Transition to inspecting before continuing |
| Inspect identifies pattern | Transition to patterning |
| Mend fails to fix | Mark issue for human review, continue |

```go
type FailurePolicy struct {
    FailureThreshold float64 // Fraction of batch that triggers inspect (default 0.5)
    MaxRetries       int     // Retries per task before marking failed (default 0)
}

func (l *Loop) handleStitchFailure(ctx context.Context, crumb *types.Crumb, err error) {
    l.batchFailures++
    l.recordFailure(crumb, err)

    if l.batchFailures > l.failureThreshold() {
        l.State = StateInspecting
    }
}
```

### R6: Path Health Monitoring

The loop monitors indicators of codebase health. Degradation triggers corrective operations before the path becomes unproductive.

| Table 5 Path Health Indicators |
|--------------------------------|

| Indicator | Healthy | Degraded | Action on Degradation |
|-----------|---------|----------|----------------------|
| Test pass rate | > 90% | < 90% | Invoke mend |
| Lint violations | 0 new | > 0 new | Invoke mend |
| LOC growth rate | < 200 LOC/task | > 200 LOC/task | Invoke pattern |
| Cyclomatic complexity | Stable | Increasing | Invoke pattern |
| Task completion rate | > 80% | < 80% | Invoke inspect |

```go
type PathHealth struct {
    TestPassRate       float64
    NewLintViolations  int
    LOCGrowthRate      float64  // Average LOC per task in batch
    CompletionRate     float64  // Tasks completed / tasks attempted
    CyclomaticDelta    float64  // Change in average complexity
}

func (l *Loop) assessPathHealth(ctx context.Context) (*PathHealth, error)

func (l *Loop) isHealthy(health *PathHealth) bool {
    return health.TestPassRate > 0.9 &&
           health.NewLintViolations == 0 &&
           health.LOCGrowthRate < 200 &&
           health.CompletionRate > 0.8
}
```

When path health degrades, the loop invokes the appropriate corrective operation. Mend addresses localized issues (test failures, lint). Pattern addresses structural issues (excessive LOC growth, increasing complexity).

### R7: Operation Dispatch

Each operation reads its definition from the cupboard. Operations are crumbs with work_type=operation. The loop dispatches operations by loading the crumb and executing according to its definition.

```go
type Operation struct {
    Name        string            // measure, stitch, inspect, mend, pattern
    Definition  string            // Template or instructions
    Config      map[string]any    // Operation-specific configuration
}

func (l *Loop) dispatchOperation(ctx context.Context, op Operation) error
```

| Table 6 Operation Crumbs |
|--------------------------|

| Operation | Crumb Name | Definition Contains |
|-----------|------------|---------------------|
| measure | op-measure | Planning prompt template, context assembly rules |
| stitch | op-stitch | Execution workflow, quality gate config |
| inspect | op-inspect | Evaluation criteria, health thresholds |
| mend | op-mend | Fix strategies, retry limits |
| pattern | op-pattern | Analysis prompt, proposal format |

Initially, operation definitions are fixed (hardcoded defaults). The template system enables modification: pattern can propose changes to operation definitions, which a human approves. This opens the path to recursive behavior described in VISION.

### R8: Metrics Per Cycle

The loop tracks metrics for each cycle. Metrics inform path health assessment and provide visibility into loop performance.

```go
type CycleMetrics struct {
    CycleNumber       int
    TokensUsed        int           // Total tokens across all operations
    TasksCompleted    int           // Tasks that reached completed state
    TasksFailed       int           // Tasks that reached failed state
    LOCDelta          LOCDelta      // Lines of code change
    DocWordsDelta     int           // Documentation word count change
    Duration          time.Duration // Wall-clock time for cycle
    OperationsRun     []string      // Operations invoked in order
}

type LOCDelta struct {
    Production int  // Production code change
    Test       int  // Test code change
}

func (l *Loop) recordCycleMetrics(ctx context.Context) *CycleMetrics
```

Metrics are recorded at the end of each cycle and available for reporting. Cumulative metrics across all cycles are computed in the final result.

### R9: Human Touchpoints

The loop reports to a human after each cycle. The report summarizes what happened, surfaces decisions that need judgment, and presents options for continuing.

```go
type CycleReport struct {
    Cycle           int
    Summary         string           // Human-readable summary
    Metrics         CycleMetrics     // Quantitative metrics
    Decisions       []Decision       // Items needing human input
    Recommendations []string         // Suggested next actions
    ContinueOptions []ContinueOption // How to proceed
}

type Decision struct {
    ID          string
    Description string
    Options     []string
    Default     string
}

type ContinueOption struct {
    Label       string  // "Continue", "Stop", "Run pattern", etc.
    Description string
}

func (l *Loop) prepareReport(ctx context.Context) *CycleReport
```

| Table 7 Decision Types |
|------------------------|

| Decision Type | When Surfaced | Example Options |
|---------------|---------------|-----------------|
| Approval | Measure proposed tasks | Approve all, approve subset, reject |
| Path intervention | Health degraded significantly | Run pattern, continue anyway, stop |
| Failure triage | Multiple tasks failed | Retry, skip, investigate |
| Design review | Pattern proposed changes | Accept, modify, defer |

In the current guided mode, the loop pauses at reporting state and waits for human input before continuing. The human can approve decisions, adjust configuration, or stop the loop.

### R10: Loop Result

When the loop completes (cycles exhausted or human stop), it returns a structured result summarizing the session.

```go
type LoopResult struct {
    CyclesCompleted   int
    TotalMetrics      CycleMetrics      // Aggregate across all cycles
    CycleDetails      []CycleMetrics    // Per-cycle breakdown
    FinalHealthState  PathHealth        // Path health at end
    PendingDecisions  []Decision        // Decisions deferred for next session
    NextActions       []string          // Recommended next steps
}

func (l *Loop) Result() *LoopResult
```

## Non-Goals

We do not implement recursive operation modification in v1. Pattern can propose changes to operation definitions, but a human must approve. The loop does not self-modify during execution.

We do not implement parallel task execution. The loop executes one task at a time. Parallel execution requires work stealing, lock management, and conflict resolution deferred to a future phase.

We do not implement autonomous multi-cycle runs without human check-in. The loop reports after each cycle and waits for human input. Full autonomy requires confidence scoring and safety bounds beyond v1 scope.

We do not implement DAG-based operation ordering. Operations follow a linear sequence with conditional branches. Complex dependency graphs between operations are out of scope.

We do not implement persistent loop state across sessions. Each invocation starts fresh. Resume capability (pick up where a previous session left off) is deferred.

## Acceptance Criteria

- [ ] Loop state machine defines states: idle, measuring, stitching, inspecting, mending, patterning, reporting, stopped
- [ ] State transitions follow defined rules with clear triggers
- [ ] Default operation order: measure (if empty) to stitch to inspect to mend/pattern
- [ ] Cycle management configurable: MaxCycles, BatchSize, PatternPeriod, StopOnFailure
- [ ] Queue empty triggers measure to propose new work
- [ ] Failure recovery: single failure continues, multiple failures trigger inspect
- [ ] Path health indicators defined: test pass rate, lint violations, LOC growth, completion rate
- [ ] Health degradation triggers corrective operations (mend or pattern)
- [ ] Operation dispatch loads definitions from cupboard (with hardcoded fallback)
- [ ] Metrics tracked per cycle: tokens, tasks completed/failed, LOC delta, doc words delta, duration
- [ ] Human touchpoint after each cycle with summary, decisions, and continue options
- [ ] Loop result includes aggregate metrics, per-cycle details, final health state, and next actions
- [ ] File saved as prd-development-loop.md in docs/product-requirements/
