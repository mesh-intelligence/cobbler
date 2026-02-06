# Cobbler Vision

## Executive Summary

Cobbler cobbles together context for coding agents. We break work into small tasks, assemble the right context for each one, and dispatch to an agent one-shot. The agent executes without back-and-forth; cobbler evaluates the result and decides what happens next. Over repeated cycles, cobbler becomes an iterative method for managing what coding agents see and do.

Coding agents are guided components. They produce useful output, but quality depends on the context they receive. Cobbler tests whether iterative context management — breaking work down, assembling the right inputs, evaluating outputs, and refining the process — can compose guided agents into something more reliable than running them ad hoc. We are not a coding agent, a task tracker, or a CI system. We operate agents; we do not replace them.

## Introduction

### The Problem

Software development with coding agents is inductive. Given step n (the current codebase), the agent produces step n+1 (a small addition or change). Each step layers code on existing code, starting from zero. This works when steps are small and well-defined. Give an agent a clear function to write or a specific bug to fix and it performs.

Two things go wrong. First, the path through the induction matters. A sequence of steps that produces tangled code makes the next step harder. Eventually the codebase becomes so knotted that the agent cannot make progress — a refactor is needed, and the refactor may itself be too large for a single step. The path can become unproductive.

Second, context compounds. Each step adds code, and the agent needs to understand some of it to take the next step. But giving the agent everything is wasteful: more tokens, more noise, worse focus. We want to give the agent the least context it needs to do the job. This is the context management problem.

Manual operation does not solve either problem at scale. A human reads the project state, formulates a prompt, invokes the agent, reviews output, and uses a gut feeling to decide what to do next. Prototype bash scripts (make-work.sh and do-work.sh) automated parts of this loop but reached their limits: they lack direct access to work item storage, build prompts through string concatenation, and have no structured evaluation of results.

### What Cobbler Does

Cobbler replaces those prototypes. We import the crumbs Go module and call cupboard methods directly: Cupboard.GetTable("crumbs").Get(id), Cupboard.GetTable("crumbs").Set(id, data). We use structured prompt templates rather than string concatenation. We implement commands that cover the full inductive cycle: assess state, assemble minimal context, execute a step, evaluate the result, fix issues, and propose design changes.

Each cycle is a step in the induction. Cobbler manages the path by choosing what work to do next and in what order. It manages context by assembling only what the agent needs for that step. When the path goes wrong — code tangles, a refactor looms — cobbler can break the refactor into steps the agent can handle.

Five commands, named after shoemaking terms, cover this cycle.

| Table 1 Commands |
|------------------|

| Command | What it does |
|---------|--------------|
| measure | Assess project state, propose tasks |
| stitch | Execute work via AI agents |
| inspect | Evaluate output quality |
| mend | Fix issues found by inspect |
| pattern | Propose design and structural changes |

We measure the work to understand what needs doing. We stitch to execute tasks through agents. We inspect and mend to evaluate and fix. We pattern to propose architectural changes.

### Guided and Recursive

A human invokes cobbler and walks away. Cobbler breaks the work down, dispatches agents, evaluates results, and reports back when something needs a decision. The human does not approve each step; cobbler handles the loop and surfaces only what requires judgment.

The five operations (measure, stitch, inspect, mend, pattern) are themselves stored as crumbs. Initially the operations are fixed: measure always reads project state the same way, stitch always builds prompts the same way. But because operation definitions live in the cupboard, they can change. Cobbler could start using crumb templates to define how each operation runs. An agent invoked through pattern could redesign the templates, change the order of operations, or alter how stitch assembles context. Cobbler's own behavior becomes mutable data in the same store it operates on.

Templates make context strategies swappable. Different templates can assemble different slices of context for the same task, letting us experiment with what the agent actually needs. Crumbs trails record the path through the induction — what steps were taken, in what order, with what context — so we can compare strategies and learn which paths produce clean code and which produce tangles.

This is the path toward recursive behavior. Today cobbler is a guided system: the human sets direction and cobbler executes with fixed operations. As operation templates accumulate and prove reliable, cobbler may modify its own behavior through the same dispatch mechanism it uses for everything else. We test that boundary.

## Why This Project

Cobbler uses crumbs as its work store. The cupboard holds both cobbler's own work (planning, evaluation, design proposals) and work intended for agents (documentation, code). A property on each crumb indicates its type: planning, documentation, coding, or operations. Cobbler reads work from the cupboard, formulates prompts, dispatches agents, updates state, and creates new work items as it discovers them.

| Table 2 Relationship to Other Components |
|------------------------------------------|

| Component | Role | Cobbler's relationship |
|-----------|------|------------------------|
| Crumbs | Work item storage (cupboard) | Stores all work: cobbler's own and agent-bound; accessed via Go module |
| Beads (bd) | CLI for crumbs | Cobbler replaces bd usage with direct Go calls |
| make-work.sh | Prototype work creation | Cobbler measure replaces this script |
| do-work.sh | Prototype work execution | Cobbler stitch replaces this script |
| Claude Code | AI agent runtime | Cobbler invokes agents; does not replace the runtime |

We leverage the existing cupboard interfaces defined in crumbs. The Cupboard interface has GetTable(name) returning a table reference, and each table has Get and Set methods. The attach/detach methods connect to backends with optional JSON configuration. Cobbler calls these interfaces rather than shelling out to bd commands.

## Planning and Implementation

### Success Criteria

We measure success along three dimensions.

Task completion without iteration: agents complete documentation and code tasks via cobbler stitch without back-and-forth. The human invokes cobbler; cobbler handles the rest and reports back.

Cupboard integration: cobbler accesses crumbs directly through Go module import, never through shell commands to bd.

Replaced prototypes: make-work.sh functionality moves to cobbler measure; do-work.sh functionality moves to cobbler stitch. The scripts become obsolete.

### What Done Looks Like

A developer runs cobbler measure to assess project state. Cobbler reads the cupboard, analyzes existing work, and proposes new tasks. The developer reviews and approves. Cobbler writes approved tasks back to the cupboard.

The developer runs cobbler stitch. Cobbler picks a task, formulates a prompt from templates, invokes an AI agent, captures output, and updates the cupboard. For documentation tasks, the agent writes markdown. For code tasks, the agent writes implementation. Cobbler can run multiple tasks in sequence.

When issues arise, the developer runs cobbler inspect to evaluate recent work. If defects exist, cobbler mend attempts fixes. For larger structural changes, cobbler pattern proposes architectural updates.

The prototype scripts (make-work.sh, do-work.sh) are no longer used. All agent operation flows through cobbler.

### Implementation Phases

| Table 3 Implementation Phases |
|-------------------------------|

| Phase | Focus | Deliverables |
|-------|-------|--------------|
| 01.0 | Stitch for documentation | cobbler stitch executes documentation tasks; cupboard read/write via crumbs module; prompt templates for doc work |
| 02.0 | Stitch for code | cobbler stitch executes code tasks; git worktree management; test execution hooks |
| 03.0 | Measure | cobbler measure assesses project state and proposes tasks; replaces make-work.sh |
| 04.0 | Inspect, mend, pattern | cobbler inspect evaluates output; cobbler mend fixes issues; cobbler pattern proposes design changes |

### Risks and Mitigations

| Table 4 Risks |
|---------------|

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Crumbs module API changes | High | Medium | Pin crumbs version; update cobbler when crumbs releases |
| Agent output quality varies | Medium | High | Inspect and mend commands provide feedback loop; human approval gates |
| Path produces tangled code | High | Medium | Pattern detects structural problems early; cobbler breaks large refactors into agent-sized steps |
| Prompt template complexity | Medium | Medium | Start with simple templates; iterate based on agent performance |
| Git worktree edge cases | Low | Medium | Test worktree lifecycle thoroughly; graceful cleanup on failure |

## What This Is NOT

We are not a coding agent. Agents code; cobbler dispatches them.

We are not a planning agent. Agents plan; cobbler decomposes work and hands it off.

We are not a task tracker. Crumbs stores the work; cobbler reads, writes, and creates work items but does not replace crumbs.

We are not an IDE plugin. Cobbler runs from the terminal. We do not integrate with VS Code, JetBrains, or other editors.

We are not a CI system. We do not run on push, trigger builds, or gate merges. Cobbler runs when a developer invokes it.

We are not a recursive system yet. Cobbler is guided: a human sets direction and cobbler executes. The testbed explores how far cobbler can go before needing human input again.

We are not a workflow engine. We do not define DAGs, manage dependencies between jobs, or manage multi-service deployments. We operate a single agent on a single task at a time.

We are not an LLM wrapper or prompt library. We call AI agents through their existing interfaces (Claude Code). We do not abstract over model providers or manage API keys.

| Table 5 Comparison to Related Concepts |
|----------------------------------------|

| Concept | What it does | How cobbler differs |
|---------|--------------|---------------------|
| Task tracker (Jira, Linear) | Stores and manages work items | Cobbler uses crumbs for storage; does not implement its own store |
| CI system (GitHub Actions, Jenkins) | Runs jobs on events | Cobbler runs on developer command, not events |
| Agentic framework (LangChain, AutoGPT) | Provides agent abstractions | Cobbler operates existing agents; does not provide new abstractions |
| Workflow engine (Temporal, Airflow) | Manages DAGs of jobs | Cobbler runs single tasks sequentially |

## References

See ARCHITECTURE.md for component design and interfaces. See PRDs in docs/product-requirements/ for detailed requirements.
