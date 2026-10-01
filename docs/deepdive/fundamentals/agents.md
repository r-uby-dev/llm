
## Agents
### Introduction

#### Overview

[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
is the recommended entry point for most use-cases. It provides a
class-level DSL for defining reusable, preconfigured assistants
with defaults for model, tools, schema, and instructions. Under
the hood it delegates to
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html),
so it has the same runtime surface: message history, streaming,
serialization, compaction, and concurrency.

#### How it works

An agent holds a conversation with a model. You send input with
[`LLM::Agent#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#talk),
the model responds, and if it requests tools the agent
executes them automatically and feeds the results back. The tool
loop can be bounded with
[`LLM::Agent.tool_budget`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#tool_budget-class_method)
(see the Tool budget section). Instructions are injected once and
brought up to date from the agent before each request, unless the
prompt already carries a system message of the caller's own.

#### Why would I use it?

Agents manage the tool loop for you. They keep conversation state
across turns and let you define reusable configurations at the
class level. The loop runs until the model stops requesting tools
unless you bound it with `tool_budget` or a guard. If you need
manual control over the tool loop, use
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
directly instead.

#### Notes

Agents support the same concurrency strategies, compaction,
cancellation, and serialization as contexts. The trade-off between
a subclass and a direct instance is only in how the agent is
organized, not in what it can do. Tool loop execution can be
configured with `concurrency: :sequential`, `:thread`, `:async`,
`:fiber`, `:fork`, or `:ractor`.

### Class-based

#### Overview

A subclass of
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
gives you a reusable agent with its own behavior. You define the model, tools, and other
attributes at the class level, and each instance picks them up
as defaults. Attributes can be overridden per-instance, and they
can be plain values, blocks, or Symbols that resolve to methods.
The class becomes a self-contained worker that you can instantiate
and talk to from anywhere.

#### How it works

A subclass declares its defaults with
[`LLM::Agent.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#set-class_method).
Each key is a
class-level accessor: `name`, `description`, `model`, `tools`,
`skills`, `instructions`, `stream`, `tracer`, `concurrency`,
`schema`, `confirm`, `path`, `tool_budget`, `retry_budget`.
Keyword arguments in the constructor override these defaults.

```ruby
class Agent < LLM::Agent
  set model: "deepseek-v4-pro",
      description: "system administration agent",
      tools: [Exec]
end

llm = LLM.openai(key: ENV["KEY"])
agent = Agent.new(llm)
agent.talk "Run 'date'"
```

#### Why would I use it?

A subclass is useful when multiple parts of an application need to
call the same agent. The configuration and any helper methods live in one place. Define a
`research!` method that kicks off the agent's work. The subclass
becomes a self-contained worker.

#### Notes

Attributes passed to
[`LLM::Agent.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#set-class_method)
can be plain values, blocks, or
Symbols. A Symbol is evaluated as an instance method on the
subclass, so `tools: :tools` calls `tools` on the instance. A
block like `stream: -> { $stdout }` is evaluated when the attribute
is first accessed.

Set `path:` on a subclass or instance for automatic filesystem
persistence; the agent restores conversation history from the
file on startup and saves it back after every turn with no
manual
[`LLM::Agent#save`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#save)/
[`LLM::Agent#restore`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#restore)
calls. See the
[database deepdive](../features/database.md) for details.

### Object-based

#### Overview

An
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
instance is the simplest way to get started. You pass a provider and any configuration as keyword
arguments, and the agent runs the tool loop and manages state
just like a subclass would. This is the right choice when you
are prototyping, running a one-off task, or when the agent's
configuration is determined at runtime.

#### How it works

A direct instance takes the same attributes as keyword arguments
to
[`LLM::Agent.new`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#initialize-instance_method).
The first argument is always the provider.
Everything else is optional. The agent runs the tool loop
and manages state under the hood through a
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html).

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
agent.talk "Hello world"
```

#### Why would I use it?

A direct instance is the right choice for quick experiments, one-shot
tasks, or when defining a class would be overkill. It is also
the right choice when the agent's configuration is determined at
runtime and a class hierarchy adds unnecessary complexity.

#### Notes

Direct instances accept all the same options as subclasses. The
difference is only in how the agent is organized, not in what it
can do. Under the hood,
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
creates a
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
that manages the message history.

### Tool budget

#### Overview

[`LLM::Agent.tool_budget`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#tool_budget-class_method)
caps the number of tool calls allowed in a single turn. Once the
budget is spent, the agent sends an in-band advisory message back
through the model instead of running more tools. By default no
budget is set, so the feature is disabled.

#### How it works

When you want to bound how many tools an agent can call in one
turn, set the budget with
[`LLM::Agent.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#set-class_method).
The budget can be a plain number or a block evaluated against the
agent instance. Once the agent has made the budgeted number of tool
calls, it stops and returns an in-band advisory message describing
the spent budget. A model will usually change course afterwards:

```ruby
class Researcher < LLM::Agent
  set model: "deepseek-v4-pro",
      tools: [FetchNews, FetchStocks],
      tool_budget: 5
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = Researcher.new(llm)
agent.talk "Research the market"
```

#### Why would I use it?

A tool budget prevents runaway tool loops. A misbehaving model can
otherwise keep calling tools, spending tokens on every round trip.
Capping the budget turns that into a bounded conversation: after
the cap, the model is told it has run out of tool calls and must
respond from what it has.

#### Notes

The budget is disabled by default (`nil`). Set it on a subclass
with the `tool_budget` DSL, through
[`LLM::Agent.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#set-class_method)
with `tool_budget:`, or per-instance with the `tool_budget:` keyword
argument to
[`LLM::Agent.new`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#initialize-instance_method).
This replaces the previous `tool_attempts` parameter, which is no
longer used.

### Retry budget

#### Overview

[`LLM::Agent.retry_budget`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#retry_budget-class_method)
is the maximum number of times an agent retries a failed request
before giving up. It is enabled by default at five retries, so
most agents survive a transient 429 or a dropped connection without
any configuration. Only a raw
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
disables it by default.

#### How it works

When you want to control how many times a failed request is
retried, set the budget with
[`LLM::Agent.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#set-class_method)
or per-instance with the `retry_budget:` keyword argument. Each
retry notifies your stream through `on_retry` and sleeps a
growing interval (2s, 4s, 6s, ...). Once the budget is spent, the
agent re-raises the error instead of blocking forever:

```ruby
class Chat < LLM::Agent
  set model: "deepseek-v4-pro",
      retry_budget: 5
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = Chat.new(llm)
agent.talk "Hello"
```

#### Why would I use it?

Providers rate-limit requests often, and a bare request fails the
moment you hit one. A retry budget turns a transient 429 into a
brief pause and a successful call. The growing backoff also bounds
the total wait, so an exhausted budget surfaces the error instead
of hanging.

#### Notes

The retry budget applies to rate-limited requests
(`LLM::RateLimitError`) and timeouts (`Timeout::Error`, covering
`Net::OpenTimeout` and `Net::ReadTimeout`); other errors are never
retried. The budget lives on the provider, where it defaults to five
(eight on Alibaba, which rate limits more often), and an agent that
sets none of its own takes the provider's. A raw
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
defaults to zero (`retry_budget: 0`), so retries are opt-in there. A
429 is refused before any content streams, so retrying the same
request loses nothing. Pass `retry_budget: 0` to disable retries on
an agent.
