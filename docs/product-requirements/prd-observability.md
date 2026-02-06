# PRD: Observability and Tracing

## Problem

Cobbler runs iterative loops (measure, stitch, inspect, mend, pattern) dispatching agents one-shot. Each loop cycle executes multiple operations, each operation may invoke an agent, and each agent invocation may execute multiple tool calls. Without structured observability, we cannot answer basic questions: Which steps succeeded? Which failed? Where was context insufficient? How did the inductive path evolve over time?

The development loop (prd-development-loop) tracks metrics per cycle: tokens used, tasks completed/failed, LOC delta. But these are aggregate numbers. They tell us the batch outcome, not the shape of execution. If a task fails, we see "failed" but not why. If an agent consumed excessive tokens, we see the total but not where they went. If context assembly took longer than agent invocation, we have no visibility into that breakdown.

The inductive path is central to cobbler's purpose. VISION describes the problem: each step layers code on existing code, and a bad sequence produces tangled code that makes subsequent steps harder. Crumbs trails record what tasks were executed in what order. But trails are task-level: they log which crumbs were visited, not what happened inside each crumb's execution. A trail shows that task A preceded task B; it does not show that task A's agent spent 80% of its tokens on a failed tool call before succeeding on retry.

Debugging without tracing is guesswork. When a task fails, the operator reads logs, reconstructs the sequence, and hypothesizes what went wrong. With tracing, the operator queries the trace for the failed span, sees its parent context, examines inputs and outputs, and identifies the cause directly.

Template comparison lacks data. Cobbler's templates control context assembly: different templates produce different prompts for the same task. We want to compare strategies: did template X produce better outcomes than template Y? Without tracing, we compare only aggregate metrics. With tracing, we correlate template choice to execution characteristics (token distribution, success rate, duration) at the operation level.

## Goals

We add observability to cobbler through OpenTelemetry tracing. Every operation invocation produces a span with inputs, outputs, duration, and outcome. Spans nest hierarchically: loop contains operations, operations contain agent invocations, agent invocations contain tool calls. The trace becomes a structured record of the inductive path.

1. Span-based tracing for all cobbler operations (measure, stitch, inspect, mend, pattern)
2. Hierarchical span structure: loop, operation, agent invocation, tool call
3. Attributes on each span: operation type, crumb ID, context size (tokens), outcome (success/failure/partial), duration
4. Export to OTLP endpoint (configurable collector)
5. Local fallback: JSON trace file when no collector is available
6. Visualization: render operation timelines with success/failure coloring and drill-down into spans
7. Trail integration: link spans to crumbs trails for correlation between task sequence and execution details

## Requirements

### R1: OpenTelemetry Integration

Cobbler initializes an OpenTelemetry tracer at startup. The tracer is configured via cobbler's config file or environment variables.

```go
type TracingConfig struct {
    Enabled      bool   // Enable tracing; default true
    ServiceName  string // Service name in traces; default "cobbler"
    OTLPEndpoint string // OTLP collector endpoint; empty for local-only
    SampleRate   float64 // Sampling rate 0.0-1.0; default 1.0
    LocalPath    string // Path for local JSON traces; default ".cobbler/traces/"
}

func InitTracer(cfg TracingConfig) (*sdktrace.TracerProvider, error)
```

| Table 1 Tracer Configuration |
|------------------------------|

| Parameter | Environment Variable | Default | Description |
|-----------|---------------------|---------|-------------|
| Enabled | COBBLER_TRACING_ENABLED | true | Enable or disable tracing |
| ServiceName | COBBLER_SERVICE_NAME | "cobbler" | Service name in trace data |
| OTLPEndpoint | OTEL_EXPORTER_OTLP_ENDPOINT | "" | OTLP collector URL; empty for local-only |
| SampleRate | COBBLER_TRACE_SAMPLE_RATE | 1.0 | Fraction of traces to record |
| LocalPath | COBBLER_TRACE_PATH | ".cobbler/traces/" | Directory for local JSON traces |

We use go.opentelemetry.io/otel and related packages. The tracer provider is registered globally so all cobbler packages can create spans via otel.Tracer("cobbler").

### R2: Span Hierarchy

Traces follow a consistent hierarchy matching cobbler's execution structure.

| Table 2 Span Hierarchy |
|------------------------|

| Level | Span Name | Parent | What It Represents |
|-------|-----------|--------|-------------------|
| 1 | loop | (root) | Full development loop invocation |
| 2 | cycle/{n} | loop | One measure-stitch-inspect cycle |
| 3 | measure, stitch, inspect, mend, pattern | cycle/{n} | Single operation invocation |
| 4 | claim, context-assembly, dispatch, quality-gate | operation | Phases within an operation |
| 5 | agent-run/{n} | dispatch | Single Agent.Run call |
| 6 | tool-call/{name} | agent-run | Tool execution within agent |

```go
// Example: starting an operation span
ctx, span := tracer.Start(ctx, "stitch",
    trace.WithAttributes(
        attribute.String("crumb.id", crumb.CrumbID),
        attribute.String("crumb.work_type", workType),
    ),
)
defer span.End()
```

Child spans inherit context from parents. The trace ID remains constant across the hierarchy; span IDs identify each node.

### R3: Standard Span Attributes

Every span carries a consistent set of attributes. Operation-specific spans add additional attributes relevant to their context.

| Table 3 Common Span Attributes |
|--------------------------------|

| Attribute | Type | Description |
|-----------|------|-------------|
| cobbler.version | string | Cobbler version |
| cobbler.operation | string | Operation name (measure, stitch, etc.) |
| outcome | string | success, failure, partial |
| error.message | string | Error message if outcome is failure |

| Table 4 Operation-Specific Attributes |
|---------------------------------------|

| Span Type | Additional Attributes |
|-----------|-----------------------|
| stitch | crumb.id, crumb.work_type, template.name |
| context-assembly | context.file_count, context.total_tokens |
| dispatch | prompt.token_count, response.token_count |
| agent-run | tokens.input, tokens.output, tool_calls.count |
| tool-call | tool.name, tool.duration_ms, tool.success |
| quality-gate | gate.name, gate.passed, gate.duration_ms |

```go
type SpanAttributes struct {
    CrumbID       string
    WorkType      string
    TemplateName  string
    ContextTokens int
    PromptTokens  int
    ResponseTokens int
    Outcome       string
    ErrorMessage  string
}

func (a *SpanAttributes) ToOTel() []attribute.KeyValue
```

### R4: Loop and Cycle Tracing

The development loop creates a root span for the full invocation. Each cycle creates a child span under the loop.

```go
func (l *Loop) Run(ctx context.Context, cfg LoopConfig) (*LoopResult, error) {
    ctx, loopSpan := tracer.Start(ctx, "loop",
        trace.WithAttributes(
            attribute.Int("config.max_cycles", cfg.MaxCycles),
            attribute.Int("config.batch_size", cfg.BatchSize),
        ),
    )
    defer loopSpan.End()

    for cycleNum := 0; cycleNum < cfg.MaxCycles; cycleNum++ {
        ctx, cycleSpan := tracer.Start(ctx, fmt.Sprintf("cycle/%d", cycleNum))
        // ... execute cycle operations ...
        cycleSpan.End()
    }
    return l.Result(), nil
}
```

Cycle spans record metrics as attributes when the cycle completes.

| Table 5 Cycle Span Attributes |
|-------------------------------|

| Attribute | Type | Description |
|-----------|------|-------------|
| cycle.number | int | Cycle index (0-based) |
| cycle.tasks_completed | int | Tasks completed this cycle |
| cycle.tasks_failed | int | Tasks failed this cycle |
| cycle.tokens_used | int | Total tokens consumed |
| cycle.loc_delta | int | Lines of code change |
| cycle.duration_ms | int | Cycle wall-clock time |

### R5: Operation Tracing

Each operation (measure, stitch, inspect, mend, pattern) creates a span under the current cycle. The span captures operation-level inputs and outputs.

```go
func (s *Stitch) Execute(ctx context.Context, crumb *types.Crumb) error {
    ctx, span := tracer.Start(ctx, "stitch",
        trace.WithAttributes(
            attribute.String("crumb.id", crumb.CrumbID),
            attribute.String("crumb.work_type", crumb.Properties["work_type"]),
        ),
    )
    defer func() {
        span.SetAttributes(attribute.String("outcome", s.outcome))
        if s.err != nil {
            span.RecordError(s.err)
        }
        span.End()
    }()

    // ... execute stitch phases ...
}
```

Each phase within an operation (claim, context-assembly, dispatch, quality-gate) creates a child span.

### R6: Agent Invocation Tracing

Agent.Run calls create spans under the dispatch phase. Multiple agent runs (conversation loops) each get their own span.

```go
func (a *ClaudeAgent) Run(ctx context.Context, req Request) (Response, error) {
    ctx, span := tracer.Start(ctx, fmt.Sprintf("agent-run/%d", a.runCount),
        trace.WithAttributes(
            attribute.Int("tokens.input", req.EstimatedTokens()),
        ),
    )
    defer span.End()

    resp, err := a.client.Messages.Create(ctx, params)

    span.SetAttributes(
        attribute.Int("tokens.output", resp.Usage.OutputTokens),
        attribute.Int("tool_calls.count", len(resp.ToolUse)),
    )
    return resp, err
}
```

### R7: Tool Call Tracing

Each tool execution creates a span under the agent-run. Tool spans capture the tool name, arguments (sanitized), duration, and result.

```go
func (t *Tool) Execute(ctx context.Context, args map[string]any) (any, error) {
    ctx, span := tracer.Start(ctx, fmt.Sprintf("tool-call/%s", t.Name()),
        trace.WithAttributes(
            attribute.String("tool.name", t.Name()),
        ),
    )
    defer span.End()

    start := time.Now()
    result, err := t.execute(ctx, args)

    span.SetAttributes(
        attribute.Int64("tool.duration_ms", time.Since(start).Milliseconds()),
        attribute.Bool("tool.success", err == nil),
    )
    if err != nil {
        span.RecordError(err)
    }
    return result, err
}
```

Sensitive data in tool arguments (file contents, API keys) must not appear in span attributes. The tracing layer sanitizes arguments before recording.

### R8: OTLP Export

When OTLPEndpoint is configured, cobbler exports spans to an OpenTelemetry collector. The exporter uses gRPC by default with HTTP as a fallback.

```go
func newOTLPExporter(endpoint string) (sdktrace.SpanExporter, error) {
    ctx := context.Background()

    // Try gRPC first
    grpcExporter, err := otlptracegrpc.New(ctx,
        otlptracegrpc.WithEndpoint(endpoint),
        otlptracegrpc.WithInsecure(), // Configurable
    )
    if err == nil {
        return grpcExporter, nil
    }

    // Fall back to HTTP
    return otlptracehttp.New(ctx,
        otlptracehttp.WithEndpoint(endpoint),
    )
}
```

| Table 6 OTLP Export Configuration |
|-----------------------------------|

| Parameter | Environment Variable | Description |
|-----------|---------------------|-------------|
| Endpoint | OTEL_EXPORTER_OTLP_ENDPOINT | Collector address (host:port) |
| Insecure | OTEL_EXPORTER_OTLP_INSECURE | Skip TLS verification |
| Headers | OTEL_EXPORTER_OTLP_HEADERS | Auth headers (key=value,...) |

### R9: Local JSON Fallback

When no OTLP endpoint is configured or the collector is unreachable, cobbler writes traces to local JSON files. This ensures tracing data is never lost.

```go
type LocalExporter struct {
    path string
}

func (e *LocalExporter) ExportSpans(ctx context.Context, spans []sdktrace.ReadOnlySpan) error {
    filename := fmt.Sprintf("%s/trace-%s.json", e.path, time.Now().Format("20060102-150405"))
    data := convertToJSON(spans)
    return os.WriteFile(filename, data, 0644)
}
```

| Table 7 Local Trace File Format |
|---------------------------------|

| Field | Type | Description |
|-------|------|-------------|
| trace_id | string | Unique trace identifier |
| spans | []Span | Array of span records |
| spans[].span_id | string | Unique span identifier |
| spans[].parent_span_id | string | Parent span ID (empty for root) |
| spans[].name | string | Span name |
| spans[].start_time | timestamp | Span start time (RFC3339) |
| spans[].end_time | timestamp | Span end time (RFC3339) |
| spans[].attributes | object | Key-value attributes |
| spans[].status | string | ok, error |
| spans[].events | []Event | Recorded events and errors |

Local traces are written per-loop invocation. The filename includes a timestamp for easy identification.

### R10: Visualization

Cobbler supports visualization of traces through two approaches: external tools (Jaeger, Grafana Tempo) via OTLP export, and a built-in lightweight viewer for local traces.

```go
// CLI command to view local traces
type ViewConfig struct {
    TracePath  string // Path to trace file or directory
    TraceID    string // Specific trace ID to view
    Filter     string // Filter expression (e.g., "outcome=failure")
    Format     string // "timeline", "tree", "summary"
}

func ViewTraces(cfg ViewConfig) error
```

| Table 8 Visualization Modes |
|-----------------------------|

| Mode | Description | Output |
|------|-------------|--------|
| timeline | Horizontal timeline of spans | ASCII art timeline with duration bars |
| tree | Hierarchical span tree | Indented tree with span names and durations |
| summary | Aggregated statistics | Counts, durations, and success rates by span type |

The built-in viewer renders traces in the terminal. For richer visualization, we recommend Jaeger (docker run jaegertracing/all-in-one) or Grafana Tempo with the Grafana UI.

```bash
# View local traces
cobbler trace view --path .cobbler/traces/trace-20240115-143022.json --format tree

# View with filter
cobbler trace view --filter "outcome=failure" --format timeline
```

### R11: Trail Integration

Spans link to crumbs trails so we can correlate execution traces with the task sequence. When stitch executes a crumb, the span includes the trail ID if the crumb belongs to a trail.

```go
type TrailLink struct {
    TrailID   string // Trail containing this crumb
    CrumbID   string // Crumb being executed
    Position  int    // Position in trail sequence
}

func (s *Stitch) linkToTrail(span trace.Span, crumb *types.Crumb) {
    if trailID := crumb.Properties["trail_id"]; trailID != "" {
        span.SetAttributes(
            attribute.String("trail.id", trailID),
            attribute.Int("trail.position", crumb.Properties["trail_position"].(int)),
        )
    }
}
```

| Table 9 Trail-Trace Correlation |
|---------------------------------|

| Query | Use Case |
|-------|----------|
| Find all spans for trail X | Understand execution of a complete exploration path |
| Compare traces across trails | Analyze which context strategies (templates) perform better |
| Find failed spans in trail order | Debug where an exploration path went wrong |

Trail integration enables the analysis loop described in VISION: record the path through the induction (trails), record execution details (traces), compare strategies to learn which paths produce clean code.

### R12: Error Recording

Errors are recorded as span events with full context. The error chain is preserved for debugging.

```go
func recordError(span trace.Span, err error) {
    span.RecordError(err,
        trace.WithAttributes(
            attribute.String("error.type", fmt.Sprintf("%T", err)),
        ),
    )
    span.SetStatus(codes.Error, err.Error())
}
```

| Table 10 Error Attributes |
|---------------------------|

| Attribute | Description |
|-----------|-------------|
| error.type | Go type of the error |
| error.message | Error message |
| error.stack | Stack trace (if available) |
| error.cause | Underlying cause (for wrapped errors) |

### R13: Metrics Derived from Traces

While traces provide detailed execution data, cobbler derives aggregate metrics from trace data for dashboards and reporting.

```go
type DerivedMetrics struct {
    OperationCount      map[string]int     // Count by operation type
    SuccessRate         map[string]float64 // Success rate by operation
    AvgDuration         map[string]time.Duration // Avg duration by operation
    TokenDistribution   map[string]int     // Tokens by operation type
    ToolCallFrequency   map[string]int     // Tool usage frequency
}

func DeriveMetrics(traces []Trace) *DerivedMetrics
```

These metrics complement the per-cycle metrics in prd-development-loop with operation-level granularity.

## Non-Goals

We do not build a custom tracing backend. Cobbler exports to standard OTLP collectors (Jaeger, Tempo, Honeycomb). The local JSON fallback provides data persistence, not a query engine.

We do not implement real-time monitoring or alerting. Traces are for post-hoc analysis and debugging. Real-time health monitoring belongs in a separate observability layer.

We do not replace crumbs trails with traces. Trails record the logical task sequence (which crumbs, in what order). Traces record execution details (how long, what resources, what errors). They complement each other: trails for path analysis, traces for execution analysis.

We do not trace external systems. Cobbler traces its own operations. LLM API latency appears in agent-run spans, but we do not instrument the LLM provider itself.

We do not implement distributed tracing across multiple cobbler instances. One cobbler process produces one trace. Distributed coordination is out of scope.

## Acceptance Criteria

- [ ] OpenTelemetry tracer initialized at cobbler startup with configuration from file and environment
- [ ] Span hierarchy: loop, cycle, operation, phase, agent-run, tool-call
- [ ] Common attributes on all spans: cobbler.version, cobbler.operation, outcome
- [ ] Operation-specific attributes: crumb.id, work_type, tokens, durations
- [ ] Loop and cycle spans record metrics (tasks completed/failed, tokens, LOC delta)
- [ ] Agent.Run calls create spans with token counts and tool call counts
- [ ] Tool executions create spans with name, duration, and success status
- [ ] OTLP export to configurable endpoint (gRPC with HTTP fallback)
- [ ] Local JSON traces written when no collector available
- [ ] Built-in trace viewer with timeline, tree, and summary formats
- [ ] Spans link to crumbs trails via trail.id attribute
- [ ] Errors recorded with type, message, and cause
- [ ] Derived metrics computed from trace data
- [ ] Documentation: setup guide for local tracing and collector integration
- [ ] File saved as prd-observability.md in docs/product-requirements/
