<p align="center">
  <a href="https://r.uby.dev">
    <img
      src="https://github.com/r-uby-dev/llm.rb/raw/main/rubydev.svg"
      width="400"
      height="200"
      border="0"
      alt="a r.uby.dev project"
     >
  </a>
</p>

> A [r.uby.dev](https://r.uby.dev) project.

Ruby's capable AI runtime.

It provides one Ruby interface for building with large language models:
providers, agents, tools, skills, MCP, A2A, RAG, streaming, files, and                 persisted conversation state all share the same runtime.

The gem runs on Ruby's standard library by default and loads optional
integrations only when needed. It supports OpenAI, OpenAI-compatible
endpoints, Anthropic, Google Gemini, DeepSeek, xAI, Z.ai, AWS Bedrock,
Ollama, and llama.cpp, with built-in ActiveRecord and Sequel support.

## Services

llm.rb is a [r.uby.dev](https://r.uby.dev) project
that is part of a growing family of AI-related
projects that also includes publically accessible
SSH services.

#### matz - the mruby expert

> ssh matz@r.uby.dev

See [https://r.uby.dev/matz](https://r.uby.dev/matz) for more information.

#### robert - the freebsd expert

> ssh robert@4.4bsd.dev

See [https://4.4bsd.dev/robert](https://4.4bsd.dev/robert) for more information.

## Quick start

#### LLM::Context

The
[LLM::Context](https://0x1eef.github.io/x/llm.rb/LLM/Context.html)
object is at the heart of the runtime. Almost all other features build
on top of it. It is a low-level interface to a model, and requires tool
execution to be managed manually. The
[LLM::Agent](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html)
class is almost the same as
[LLM::Context](https://0x1eef.github.io/x/llm.rb/LLM/Context.html)
but it manages tool execution for you - we'll cover agents next:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
ctx = LLM::Context.new(llm, stream: $stdout)
ctx.talk "Hello world"
```

#### LLM::Agent

The
[LLM::Agent](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html)
object is implemented on top of
[LLM::Context](https://0x1eef.github.io/x/llm.rb/LLM/Context.html).
It provides the same interface, but manages tool execution for you. It
also has builtin features such as a loop guard that detects repeated
tool call patterns, and another guard that detects infinite tool call
loops. Both guards advise the model to change course rather than raise
an error:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
agent.talk "Hello world"
```

#### Agents (Advanced)

An agent can be configured to require confirmation before a tool is
executed. When a matching tool is called, llm.rb runs
`on_tool_confirmation`. That callback must decide whether to cancel the
tool call or approve it and execute it by calling
`fn.spawn(strategy).wait`, and it must always return an instance of
[`LLM::Function::Return`](https://0x1eef.github.io/x/llm.rb/LLM/Function/Return.html):

```ruby
require "llm"

class Agent < LLM::Agent
  tools DeleteFile
  confirm "delete-file"

  def on_tool_confirmation(fn, strategy)
    path = fn.arguments.path
    if path.start_with?("/tmp/")
      fn.spawn(strategy).wait
    else
      fn.cancel(reason: "Deletion requires approval")
    end
  end
end

llm = LLM.openai(key: ENV["KEY"])
Agent.new(llm, stream: $stdout).talk("Delete /tmp/example.txt.")
```

#### Tools

The
[LLM::Tool](https://0x1eef.github.io/x/llm.rb/LLM/Tool.html)
class can be subclassed to implement your own tools that can extend the
abilities of a model:

```ruby
class ReadFile < LLM::Tool
  name "read-file"
  description "Read a file"
  parameter :path, String, "The filename or path"
  required %i[path]

  def call(path:)
    { contents: File.read(path) }
  end
end
```

#### MCP

The
[LLM::MCP](https://0x1eef.github.io/x/llm.rb/LLM/MCP.html)
object lets llm.rb use tools provided by an MCP server. Those tools are
exposed through the same runtime as local tools, so you can pass them
to either
[LLM::Context](https://0x1eef.github.io/x/llm.rb/LLM/Context.html)
or
[LLM::Agent](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html).
In this example, the MCP server runs over stdio and
[LLM::Agent](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html)
manages the tool loop. For **stdio**, `mcp.session` is the preferred
pattern because it keeps one MCP session alive across discovery and
tool calls:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
mcp = LLM::MCP.stdio(argv: ["ruby", "server.rb"])

mcp.session do
  agent = LLM::Agent.new(llm, stream: $stdout, tools: mcp.tools)
  agent.talk "Use the available tools to inspect the environment."
end
```

MCP can also be used without `session`. Although it works it is generally
not recommended for the **stdio** transport because it is inefficient
to start and stop a fresh MCP process for tool discovery and each tool
call:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
mcp = LLM::MCP.stdio(argv: ["ruby", "server.rb"])

agent = LLM::Agent.new(llm, tools: mcp.tools)
agent.talk("Use the available tools to inspect the environment.")
```

The HTTP transport can be used with or without the `session` method,
and unlike the stdio transport it can remain efficient without the
`session` method through a persistent connection pool that is available
through the
[LLM::Transport.net_http_persistent](https://0x1eef.github.io/x/llm.rb/LLM/Transport.html#method-c-net_http_persistent)
transport:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
mcp = LLM::MCP.http(
  url: "https://remote-mcp.example.com",
  transport: :net_http_persistent
)

agent = LLM::Agent.new(llm, tools: mcp.tools)
agent.talk("Use the available tools to inspect the environment.")
```

#### A2A (Agent 2 Agent)

The
[LLM::A2A](https://0x1eef.github.io/x/llm.rb/LLM/A2A.html)
object lets llm.rb use skills provided by a remote A2A agent. Those
skills are exposed through the same runtime as local tools, so you can
pass them to either
[LLM::Context](https://0x1eef.github.io/x/llm.rb/LLM/Context.html)
or
[LLM::Agent](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html).

Use remote skills as local tools:

```ruby
require "llm"

a2a = LLM::A2A.rest(
  url: "https://remote-agent.example.com",
  headers: { "Authorization" => "Bearer token" }
)
llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: a2a.skills)
agent.talk "Analyze this CSV and summarize the trends."
```

Use persistent HTTP connections:

```ruby
require "llm"

a2a = LLM::A2A.rest(
  url: "https://remote-agent.example.com",
  transport: :net_http_persistent
)
```

For more on direct messaging, task operations, push notification
configs, and JSON-RPC, see the
[LLM::A2A API docs](https://0x1eef.github.io/x/llm.rb/LLM/A2A.html).

#### Transports

Providers use Ruby's standard library Net::HTTP transport by default.
You can opt into persistent Net::HTTP connections with `persistent: true`,
or provide a transport shortcut when you want a different backend.
`transport: :curb` uses libcurl through the optional `curb` gem.

Custom transports can implement the
[LLM::Transport](https://0x1eef.github.io/x/llm.rb/LLM/Transport.html)
interface and receive transport-agnostic
[LLM::Transport::Request](https://0x1eef.github.io/x/llm.rb/LLM/Transport/Request.html)
objects from providers.

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"], persistent: true)
llm = LLM.openai(key: ENV["KEY"], transport: :net_http_persistent)
llm = LLM.openai(key: ENV["KEY"], transport: :curb)
```

#### Skills

Skills are reusable instructions loaded from a `SKILL.md` directory. They let
you package behavior and tool access together, and they plug into the
same runtime as tools, agents, MCP, and A2A. When a skill runs, llm.rb
spawns a subagent with the skill instructions, access to only the tools
listed in the skill, and recent conversation context:

```yaml
---
name: release
description: Prepare a release
tools: ["search-docs", "git"]
---

## Task

Review the release state, summarize what changed, and prepare the release.
```

```ruby
require "llm"

class ReleaseAgent < LLM::Agent
  model "gpt-5.4-mini"
  skills "./skills/release"
end

llm = LLM.openai(key: ENV["KEY"])
ReleaseAgent.new(llm, stream: $stdout).talk("Prepare the next release.")
```

A skill can also have its sub-agent inherit the parents tools through the
`inherit` directive. The `inherit` directive has coverage for the "classic"
tools (a subclass of [LLM::Tool](https://0x1eef.github.io/x/llm.rb/LLM/Tool.html)),
MCP tools, and A2A tools that a parent context or agent has access to:

```yaml
---
  name: release
  description: Prepare a release
  tools: inherit
---
```

#### LLM::Stream

The
[LLM::Stream](https://0x1eef.github.io/x/llm.rb/LLM/Stream.html)
object lets you observe output and runtime events as they happen. You
can subclass it to handle streamed content in your own application:

```ruby
require "llm"

class Stream < LLM::Stream
  def on_content(content)
    $stdout << content
  end
end

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: Stream.new)
agent.talk "Write a haiku about Ruby."
```

#### LLM::Stream (advanced)

The
[LLM::Stream](https://0x1eef.github.io/x/llm.rb/LLM/Stream.html)
object can also resolve tool calls while output is still streaming. In
`on_tool_call`, you can spawn the tool, push the work onto the stream
queue, and later drain it with `wait`:

```ruby
require "llm"

class Stream < LLM::Stream
  def on_content(content)
    $stdout << content
  end

  def on_tool_call(tool, error)
    return queue << error if error
    queue << ctx.spawn(tool, :thread)
  end
end

llm = LLM.openai(key: ENV["KEY"])
ctx = LLM::Context.new(llm, stream: Stream.new, tools: [ReadFile])
ctx.talk "Read README.md and summarize the quick start."
ctx.talk(ctx.wait) while ctx.functions?
```

#### Concurrency

llm.rb can run tool work concurrently. This is useful when a model calls
multiple tools and you want to resolve them in parallel instead of one
at a time. On
[LLM::Agent](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html),
you can enable this with `concurrency`. Common options are `:call` for
sequential execution, `:thread`, or `:task` for concurrent IO-bound work, and
`:ractor` or `:fork` for more isolated CPU-bound work:

```ruby
require "llm"

class Agent < LLM::Agent
  model "gpt-5.4-mini"
  tools ReadFile
  concurrency :thread
end

llm = LLM.openai(key: ENV["KEY"])
agent = Agent.new(llm, stream: $stdout)
agent.talk "Read README.md and CHANGELOG.md and compare them."
```

#### Serialization

The [`LLM::Agent`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html)
object can be serialized to JSON, which makes it suitable for storing
in a file, a database column, or a Redis queue. The built-in
ActiveRecord and Sequel plugins are built on top of the same underlying
serialization feature:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])

# Serialize an agent
agent1 = LLM::Agent.new(llm)
agent1.talk "Remember that my favorite language is Ruby"
string = agent1.to_json

# Restore an agent (from JSON)
agent2 = LLM::Agent.new(llm, stream: $stdout)
agent2.restore(string:)
agent2.talk "What is my favorite language?"
```

#### ask

[`LLM::Agent`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html)
also provides `ask`, a convenience interface that is compatible with
RubyLLM's `ask` method. It accepts a prompt, an optional `with:`
attachment path or paths, an optional `stream:` target, and an optional
block that chunks are yielded to. It returns an
[`LLM::Response`](https://0x1eef.github.io/x/llm.rb/LLM/Response.html),
so use `.content` when you want the text directly:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm)

puts agent.ask("Hello world").content
puts agent.ask("Summarize this document.", with: "README.md").content
agent.ask("Stream this reply.") { $stdout << _1 }
```

## Installation

```bash
gem install llm.rb
```

## Examples

#### REPL

This example uses [`LLM::Agent`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html)
for an interactive REPL. <br> See the
[deepdive (web)](https://r.uby.dev/llm/) or
[deepdive (markdown)](resources/deepdive.md) for more examples.

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)

loop do
  print "> "
  agent.talk(STDIN.gets || break)
  puts
end
```

#### Multimodal: Local Files

In llm.rb, a prompt can be a string, an [`LLM::Prompt`](https://0x1eef.github.io/x/llm.rb/LLM/Prompt.html), or an array.
When you use an array, each element can be plain text or a tagged object such as
[`agent.image_url(...)`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html#image_url-instance_method),
[`agent.local_file(...)`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html#local_file-instance_method),
or [`agent.remote_file(...)`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html#remote_file-instance_method).
Those tagged objects carry the metadata the provider adapter needs to turn one
Ruby prompt into the provider-specific multimodal request schema.

If the model understands that file type, you can attach a local file directly
with `agent.ask(..., with: path)` instead of uploading it first through a
provider Files API. Under the hood, llm.rb tags the path as a
[`agent.local_file(...)`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html#local_file-instance_method)
object:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm)
puts agent.ask("Summarize this document.", with: "README.md").content
```

#### Context Compaction

This example uses [`LLM::Agent`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html),
[`LLM::Compactor`](https://0x1eef.github.io/x/llm.rb/LLM/Compactor.html), and
[`LLM::Stream`](https://0x1eef.github.io/x/llm.rb/LLM/Stream.html) together so
long-lived conversations can summarize older history and expose the lifecycle
through stream hooks. This approach is inspired by General Intelligence
Systems. The
compactor can also use its own `model:` if you want summarization to run on a
different model from the main conversation. `token_threshold:` accepts either a
fixed token count or a percentage string like `"90%"`, which resolves
against the active model context window and triggers compaction once total
token usage goes over that percentage. See the
[deepdive (web)](https://r.uby.dev/llm/) or
[deepdive (markdown)](resources/deepdive.md) for more examples.

```ruby
require "llm"

class Stream < LLM::Stream
  def on_compaction(ctx, compactor)
    puts "Compacting #{ctx.messages.size} messages..."
  end

  def on_compaction_finish(ctx, compactor)
    puts "Compacted to #{ctx.messages.size} messages."
  end
end

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(
  llm,
  stream: Stream.new,
  compactor: {
    token_threshold: "90%",
    retention_window: 8,
    model: "gpt-5.4-mini"
  }
)
```

#### Reasoning

This example uses [`LLM::Stream`](https://0x1eef.github.io/x/llm.rb/LLM/Stream.html)
with the OpenAI Responses API so reasoning output is streamed separately from
visible assistant output. See the
[deepdive (web)](https://r.uby.dev/llm/) or
[deepdive (markdown)](resources/deepdive.md) for more examples.

To use the Responses API (OpenAI-specific), initialize an agent with
`mode: :responses` and keep using `talk` for turns.

```ruby
require "llm"

class Stream < LLM::Stream
  def on_content(content)
    $stdout << content
  end

  def on_reasoning_content(content)
    $stderr << content
  end
end

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(
  llm,
  model: "gpt-5.4-mini",
  mode: :responses,
  reasoning: { effort: "medium" },
  stream: Stream.new
)
agent.talk("Solve 17 * 19 and show your work.")
```

#### Request Cancellation

Need to cancel a stream? llm.rb has you covered through
[`LLM::Agent#interrupt!`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html#interrupt-21-instance_method).
<br> See the [deepdive (web)](https://r.uby.dev/llm/)
or [deepdive (markdown)](resources/deepdive.md) for more examples.

```ruby
require "llm"
require "io/console"

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
worker = Thread.new do
  agent.talk("Write a very long essay about network protocols.")
rescue LLM::Interrupt
  puts "Request was interrupted!"
end

STDIN.getch
agent.interrupt!
worker.join
```

#### Sequel (ORM)

The `plugin :llm` integration wraps
[`LLM::Context`](https://0x1eef.github.io/x/llm.rb/LLM/Context.html) on a
`Sequel::Model` and keeps tool execution explicit. Like the ActiveRecord
wrappers, its built-in persistence contract is the serialized `data` column,
while `provider:` resolves a real `LLM::Provider` instance and `context:`
injects defaults such as `model:`. <br> See the
[deepdive (web)](https://r.uby.dev/llm/) or
[deepdive (markdown)](resources/deepdive.md) for more examples.

```ruby
require "llm"
require "net/http/persistent"
require "sequel"
require "sequel/plugins/llm"

class Context < Sequel::Model
  plugin :llm, provider: :set_provider, context: :set_context

  private

  def set_provider
    LLM.openai(key: ENV["OPENAI_SECRET"], persistent: true)
  end

  def set_context
    { model: "gpt-5.4-mini", mode: :responses, store: false }
  end
end

ctx = Context.create
ctx.talk("Remember that my favorite language is Ruby")
puts ctx.talk("What is my favorite language?").content
```

#### ActiveRecord (ORM): acts_as_llm

The `acts_as_llm` method wraps [`LLM::Context`](https://0x1eef.github.io/x/llm.rb/LLM/Context.html) and
provides full control over tool execution. Its built-in persistence contract is
one serialized `data` column. If your app has provider, model, or usage
columns, provide them to llm.rb through `provider:` and `context:` instead of
relying on reserved wrapper columns.

See the [deepdive (web)](https://r.uby.dev/llm/)
or [deepdive (markdown)](resources/deepdive.md) for more examples.

```ruby
require "llm"
require "active_record"
require "llm/active_record"

class Context < ApplicationRecord
  acts_as_llm provider: :set_provider, context: :set_context

  private

  def set_provider
    LLM.openai(key: ENV["OPENAI_SECRET"])
  end

  def set_context
    { model: "gpt-5.4-mini", mode: :responses, store: false }
  end
end

ctx = Context.create!
ctx.talk("Remember that my favorite language is Ruby")
puts ctx.talk("What is my favorite language?").content
```

```ruby
require "llm"
require "active_record"
require "llm/active_record"

class Context < ApplicationRecord
  acts_as_llm provider: :set_provider, context: :set_context

  # Optional application columns can still provide the provider and context.
  # For example, `provider_name` and `model_name` can be normal columns.

  private

  def set_provider
    LLM.public_send(provider_name, key: provider_key)
  end

  def set_context
    { model: model_name, mode: :responses, store: false }
  end
end
```

#### ActiveRecord (ORM): acts_as_agent

The `acts_as_agent` method wraps [`LLM::Agent`](https://0x1eef.github.io/x/llm.rb/LLM/Agent.html) and
manages tool execution for you. Like `acts_as_llm`, its built-in persistence
contract is one serialized `data` column. If your app has provider or model
columns, provide them to llm.rb through your hooks and agent DSL.

See the [deepdive (web)](https://r.uby.dev/llm/)
or [deepdive (markdown)](resources/deepdive.md) for more examples.

```ruby
require "llm"
require "active_record"
require "llm/active_record"

class Ticket < ApplicationRecord
  acts_as_agent provider: :set_provider, context: :set_context
  model "gpt-5.4-mini"
  instructions "You are a concise support assistant."
  tools SearchDocs, Escalate
  concurrency :thread

  private

  def set_provider
    LLM.openai(key: ENV["OPENAI_SECRET"])
  end

  def set_context
    { mode: :responses, store: false }
  end
end

ticket = Ticket.create!
puts ticket.talk("How do I rotate my API key?").content
```

```ruby
require "llm"
require "active_record"
require "llm/active_record"

class Ticket < ApplicationRecord
  acts_as_agent provider: :set_provider, context: :set_context
  model "gpt-5.4-mini"
  instructions "You are a concise support assistant."

  private

  def set_provider
    LLM.public_send(provider_name, key: provider_key)
  end

  def set_context
    { mode: :responses, store: false }
  end
end
```

#### MCP

This example uses [`LLM::MCP`](https://0x1eef.github.io/x/llm.rb/LLM/MCP.html)
over HTTP so remote GitHub MCP tools run through the same
`LLM::Agent` tool path as local tools. It expects a GitHub token in
`ENV["GITHUB_PAT"]`. See the
[deepdive (web)](https://r.uby.dev/llm/) or
[deepdive (markdown)](resources/deepdive.md) for more examples.

```ruby
require "llm"
require "net/http/persistent"

llm = LLM.openai(key: ENV["KEY"], persistent: true)
mcp = LLM::MCP.http(
  url: "https://api.githubcopilot.com/mcp/",
  headers: { "Authorization" => "Bearer " + ENV["GITHUB_PAT"].to_s },
  persistent: true
)

agent = LLM::Agent.new(llm, stream: $stdout, tools: mcp.tools)
agent.talk("Pull information about my GitHub account.")
```

## Resources

- [deepdive (web)](https://r.uby.dev/llm/) and
  [deepdive (markdown)](resources/deepdive.md) are the examples guide.
- [relay](https://github.com/llmrb/relay) shows a real application built on
  top of llm.rb.
- [doc site](https://0x1eef.github.io/x/llm.rb?rebuild=1) has the API docs.

## License

[BSD Zero Clause](https://choosealicense.com/licenses/0bsd/)
<br>
See [LICENSE](./LICENSE)
