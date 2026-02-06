# PRD: Agent Interface

## Problem

The prototype scripts (do-work.sh, make-work.sh) invoke coding agents by piping prompts to the claude CLI: `echo "$prompt" | claude --dangerously-skip-permissions -p`. This approach has several deficiencies.

No type safety exists between cobbler and the agent. Prompts are assembled through bash string concatenation, tool registrations happen implicitly through the CLI environment, and responses come back as unstructured JSON streams that the scripts either ignore or pipe through jq for display. Error handling reduces to checking exit codes; there is no programmatic way to distinguish agent errors from tool errors, timeouts, or rate limits.

Context assembly and agent invocation are tangled together. The scripts build prompts inline, shell out to claude, and parse output in the same function. This makes testing difficult, reuse impossible, and adding new agent providers a fork of the entire script.

Token usage, a proxy for cost and a bound on context size, is not tracked. The scripts have no visibility into how many tokens each invocation consumes or cumulative usage across a session.

## Goals

We define a Go interface for agent invocation that replaces the shell-out pattern. The interface provides type safety, structured responses, explicit tool registration, and token tracking. We implement Claude first via anthropic-sdk-go; the interface enables other providers without changing dispatch code.

Specific goals:

1. Type-safe agent invocation from Go code
2. Explicit tool registration with typed arguments and return values
3. Structured responses that distinguish content from tool calls
4. Token usage tracking per invocation and cumulative
5. Error types that distinguish agent failures, tool failures, timeouts, and rate limits
6. Clean separation between prompt construction (covered by stitch PRD) and agent execution

## Requirements

### R1: Agent Interface

The Agent interface abstracts LLM providers. Implementations handle API specifics; callers use the uniform interface.

```go
// Agent sends prompts to an LLM and returns responses.
type Agent interface {
    // Run sends a prompt with available tools and returns the response.
    // The conversation loop is managed by the caller (Executor).
    Run(ctx context.Context, req Request) (Response, error)
}

type Request struct {
    Messages []Message      // Conversation history
    Tools    []Tool         // Available tools for this invocation
    Config   RequestConfig  // Per-request overrides
}

type RequestConfig struct {
    MaxTokens   int     // Max tokens in response; 0 uses agent default
    Temperature float64 // Sampling temperature; -1 uses agent default
}
```

### R2: Tool Interface

Tools are functions the agent can invoke during execution. Each tool declares its name, description, and parameter schema. The executor calls Execute when the agent requests a tool.

```go
// Tool represents a function the agent can call.
type Tool interface {
    // Name returns the tool's identifier (e.g., "read_file").
    Name() string

    // Description returns a human-readable description for the agent.
    Description() string

    // Parameters returns the JSON Schema for the tool's arguments.
    // Used by the agent to understand what arguments to provide.
    Parameters() map[string]any

    // Execute runs the tool with the given arguments.
    // Returns the result to send back to the agent.
    Execute(ctx context.Context, args map[string]any) (any, error)
}
```

### R3: Response Struct

Responses contain generated content, tool call requests, and usage metrics. The executor inspects the response to determine next steps: if ToolCalls is non-empty, execute tools and continue; if empty, the agent has finished.

```go
type Response struct {
    Content    string       // Generated text content
    ToolCalls  []ToolCall   // Tool invocations requested by the agent
    Usage      Usage        // Token counts for this response
    StopReason StopReason   // Why the agent stopped
}

type ToolCall struct {
    ID        string         // Unique identifier for this call
    ToolName  string         // Name of the tool to execute
    Arguments map[string]any // Arguments to pass to the tool
}

type Usage struct {
    InputTokens  int // Tokens in the request (prompt + history)
    OutputTokens int // Tokens in the response
}

type StopReason string

const (
    StopReasonComplete  StopReason = "complete"   // Agent finished naturally
    StopReasonToolUse   StopReason = "tool_use"   // Agent wants to use tools
    StopReasonMaxTokens StopReason = "max_tokens" // Hit token limit
)
```

### R4: Conversation Loop

The executor manages the conversation loop. The pattern repeats until the agent signals completion or an error occurs.

| Table 1 Conversation Loop States |
|----------------------------------|

| State | Condition | Action |
|-------|-----------|--------|
| Send | Start or tool results ready | Call Agent.Run with messages |
| Tool execution | Response has ToolCalls | Execute each tool, collect results |
| Complete | StopReason is complete and no ToolCalls | Return final response |
| Error | Agent.Run returns error | Return error to caller |
| Timeout | Context cancelled | Return timeout error |

The loop maintains message history. Each Agent.Run call includes the full conversation: initial prompt, prior responses, tool calls, and tool results.

```go
type Message struct {
    Role    Role   // user, assistant, or tool_result
    Content string // Text content

    // For tool_result messages
    ToolCallID string // ID of the tool call this responds to
}

type Role string

const (
    RoleUser       Role = "user"
    RoleAssistant  Role = "assistant"
    RoleToolResult Role = "tool_result"
)
```

### R5: Claude Implementation

The Claude implementation uses anthropic-sdk-go. It translates between the Agent interface and the Anthropic API.

| Table 2 Claude Implementation Responsibilities |
|------------------------------------------------|

| Responsibility | How |
|----------------|-----|
| Request translation | Convert Request to Anthropic message format |
| Tool schema conversion | Convert Tool.Parameters() to Anthropic tool format |
| Response parsing | Extract content, tool calls, usage from Anthropic response |
| Streaming | Support streaming responses for long outputs |
| Retry on transient errors | Retry with backoff on 5xx and rate limit errors |

The implementation lives in internal/claude. It is not exported; callers use the Agent interface from pkg/agent.

### R6: Timeout and Cancellation

All Agent methods accept context.Context for timeout and cancellation. The executor passes a context with deadline; the agent implementation respects it.

```go
// Executor creates context with timeout
ctx, cancel := context.WithTimeout(parentCtx, cfg.Timeout)
defer cancel()

resp, err := agent.Run(ctx, req)
if errors.Is(err, context.DeadlineExceeded) {
    // Handle timeout
}
```

The agent implementation should check ctx.Done() during long operations (streaming responses, retries) and return promptly when cancelled.

### R7: Token Tracking

The agent tracks token usage per invocation. The executor accumulates usage across the conversation loop.

```go
// Executor tracks cumulative usage
type ExecutionMetrics struct {
    TotalInputTokens  int
    TotalOutputTokens int
    Invocations       int
}

// After each Agent.Run call
metrics.TotalInputTokens += resp.Usage.InputTokens
metrics.TotalOutputTokens += resp.Usage.OutputTokens
metrics.Invocations++
```

Token counts come from the LLM provider's response. For Claude, the Anthropic API returns usage in the response metadata.

### R8: Error Types

Errors distinguish failure modes so callers can handle them appropriately.

```go
// AgentError wraps errors from agent invocation.
type AgentError struct {
    Kind    ErrorKind
    Message string
    Cause   error // Underlying error if any
}

type ErrorKind string

const (
    ErrKindAgent     ErrorKind = "agent"      // LLM returned an error
    ErrKindTool      ErrorKind = "tool"       // Tool execution failed
    ErrKindTimeout   ErrorKind = "timeout"    // Context deadline exceeded
    ErrKindRateLimit ErrorKind = "rate_limit" // Provider rate limit hit
    ErrKindNetwork   ErrorKind = "network"    // Network failure
    ErrKindInvalid   ErrorKind = "invalid"    // Invalid request (bad schema, etc.)
)

func (e *AgentError) Error() string
func (e *AgentError) Unwrap() error
```

The executor uses error kind to decide retry strategy: rate limits may warrant backoff, tool errors may warrant skipping, agent errors may be fatal.

### R9: Configuration

Agent configuration covers model selection, default parameters, and provider credentials.

```go
type AgentConfig struct {
    // Provider selection
    Provider string // "claude" (default), future: "openai", etc.

    // Model selection
    Model string // e.g., "claude-sonnet-4-20250514"

    // Default parameters (overridable per request)
    MaxTokens   int     // Default max tokens; 0 means provider default
    Temperature float64 // Default temperature; -1 means provider default

    // Timeouts
    RequestTimeout time.Duration // Timeout for single API call

    // Provider-specific
    APIKey string // API key; if empty, read from environment
}
```

Configuration loads from cobbler's config file (~/.cobbler/config.yaml) via viper. Environment variables (COBBLER_AGENT_API_KEY, ANTHROPIC_API_KEY) provide fallbacks for credentials.

## Non-Goals

We do not implement multi-provider support beyond interface definition in v1. The interface enables future providers; we implement Claude only.

We do not build streaming UI. The agent may stream responses internally for efficiency, but the interface returns complete responses. UI streaming is a presentation concern handled elsewhere.

We do not handle prompt construction. The stitch PRD covers prompt templates and context assembly. The agent interface receives a ready prompt.

We do not persist agent memory across invocations. Each Run call is stateless from the agent's perspective. The executor maintains conversation history within a single task; it does not carry memory between tasks.

We do not implement agent orchestration or multi-agent patterns. Cobbler operates one agent at a time on one task. Coordination patterns are out of scope.

## Acceptance Criteria

- [ ] Agent interface defined in pkg/agent/agent.go with Run method
- [ ] Tool interface defined in pkg/agent/tool.go with Name, Description, Parameters, Execute
- [ ] Response struct includes Content, ToolCalls, Usage, StopReason
- [ ] Message types defined for conversation history (user, assistant, tool_result)
- [ ] Error types defined with ErrorKind enumeration
- [ ] AgentConfig struct covers model, parameters, timeout, credentials
- [ ] Conversation loop state machine documented (send, tool execution, complete, error, timeout)
- [ ] Token tracking requirements specify per-invocation and cumulative metrics
- [ ] Claude implementation requirements specify translation, streaming, retry responsibilities
- [ ] All code signatures use context.Context for cancellation
