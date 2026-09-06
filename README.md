<p align="center">
  <a href="https://r.uby.dev">
    <img
      src="rubydev.svg"
      width="400"
      height="200"
      border="0"
      alt="a r.uby.dev project"
     >
  </a>
</p>

> A [r.uby.dev](https://r.uby.dev/llm) project.

Welcome to the canonical llm.rb repository.

llm.rb is an advanced runtime for building agentic AI applications
on CRuby. It has zero runtime dependencies by default, supports
concurrent and parallel tool execution and has a single coherent API
that spans 14+ providers.

The easiest way to learn about llm.rb is to ask [the r.uby.dev chatbot](https://r.uby.dev)
a question. It is connected to the llm.rb GitHub repository, backed by
ActiveRecord and uses the builtin MCP feature to connect to GitHub. All
answers are grounded in the llm.rb source code.

## Install

```bash
gem install llm.rb
```

## Quick start

### Agents

The
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
class is the default high-level interface,
and it is recommended for most use-cases. It manages tool execution
automatically and guards against infinite loops,
manages conversation state, and much more.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
agent.talk "hello world"
```
<details>
<summary>Stream</summary>
<br>

Streams can be simple IO objects or subclasses of
[`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html)
with structured callbacks for content,
reasoning, tool calls, tool returns, and compaction.
Streams can also observe message transformers, which rewrite
outgoing messages before they reach the provider.

```ruby
class MyStream < LLM::Stream
  # Visible assistant output.
  def on_content(content)
    print content
  end

  # Reasoning output streamed separately from visible content.
  def on_reasoning_content(content)
    warn content
  end

  # A streamed tool call has been fully parsed.
  def on_tool_call(tool)
  end

  # Queued streamed tool work has returned.
  def on_tool_return(tool, result)
  end

  # Before a transformer rewrites an outgoing message.
  def on_transform(transformer)
  end

  # Aftter a transformer rewrites an outgoing message.
  def on_transform_finish(transformer)
  end

  # Before a compactor trims the conversation.
  def on_compaction(compactor)
  end

  # After a compactor trims the conversation.
  def on_compaction_finish(compactor)
  end

  # Before a skill's subagent runs.
  def on_skill_call(skill)
  end

  # After a skill's subagent runs.
  # The subagent that ran it, the skill, and its response are passed
  # through, so you can introspect the agent, tally skill usage, or
  # track costs.
  def on_skill_return(agent, skill, result)
  end

  # A request was rate limited or timed out and will be retried.
  def on_retry(error, attempt)
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: MyStream.new)
agent.talk "Explain Ruby fibers."
```
</details>

<details><summary>Tools</summary>
<br>

Subclasses of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
are plain Ruby classes with
an optional set of typed parameters. <br> The model can choose to
call them on your behalf, and they're one of the most powerful features
for extending the feature set or abilities of a model.

The runtime also ships with a catalog of built-in tools for
filesystem, search, and shell operations.

```ruby
class ReadFile < LLM::Tool
  name "read-file"
  description "Read a file"
  parameter :path, String, "The filename or path"
  required %i[path]

  def call(path:)
    {contents: File.read(path)}
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: [ReadFile], stream: $stdout)
agent.talk "summarize README.md"
```
</details>
<details>
<summary>Skills</summary>
<br>

A skill turns a markdown file into a callable tool. When the model
calls it, the runtime spawns a subagent with the skill's instructions
as its system prompt and the skill's own tool set. The subagent runs
one turn and returns the result, then is discarded. Each call
is fresh and stateless.

A [LLM::Stream](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html)
can be notified as a skill starts and when it returns. The `on_skill_return`
callback hands back the subagent that ran the skill, so you can inspect
its conversation, measure its usage, track costs or add a verification
step (eg `subagent.talk("verify your work")`).

##### summary.md

```markdown
---
name: summary
description: Reads recent git history and writes a summary
tools: all
---

Collect the recent git log, analyze each commit,
and write a summary to summary.txt.
```

##### agent.rb

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, skills: ["summary.md"])
agent.talk "Summarize the last week of work"
```
</details>

<details>
<summary>Concurrency</summary>
<br>

The runtime supports six different concurrency strategies that have
different attributes. The choice between all of them often depends
on the requirements of your application.

IO-bound tools are a good fit for the `:async`, `:thread`,
and `:fiber` strategies while true parallelism can be achieved
with the `:fork` and `:ractor` strategies. The
`:sequential` strategy runs tools one at a time and is the default.
The `:fork` strategy also provides a separate process that offers
isolation from its parent.

A couple of concurrency strategies require optional, opt-in dependencies.
The `async` strategy requires the [async](https://github.com/socketry/async)
gem and the `fork` strategy requires the [xchan.rb](https://github.com/0x1eef/xchan.rb)
gem. The `fiber` strategy requires a scheduler (`Fiber.scheduler`) but by
default Ruby does not provide one.

```ruby
require "llm"
require "llm/tools"

llm   = LLM.deepseek(key: ENV["KEY"])
tools = LLM::Tool.subclasses
agent = LLM::Agent.new(llm, tools:, concurrency: :fork)
agent.talk "Run the tools in parallel"
```

</details>
<details>
<summary>Cancellation</summary>
<br>

Abort a request mid-stream and interrupt any running tools with
[`LLM::Agent#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#interrupt!)
(or `cancel!`), from any thread. The runtime raises
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
on the caller and on every active tool. A forked tool gets interrupted over
the control channel, a ractor via message passing, and pending tools
are stopped before they run. The in-flight HTTP request is closed
too, so a turn you no longer want stops without burning tokens.

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm)
Thread.new { sleep(1); agent.cancel! }

begin
  agent.talk "write a very long poem", stream: $stdout
rescue LLM::Interrupt
  puts "cancelled"
end
```
</details>
<details>
<summary>Console (<code>binding.irb</code> for agents)</summary>
<br>

The [LLM::Agent#console](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#console-instance_method)
method drops you into a highly capable interactive console
that is built on top of curses. It can help you debug agents,
test your tools, connect to MCP servers, and even A2A agents.
The console stands out because it connects to the surrounding
runtime and it can be extended by your code. Think of it as
`binding.irb` but for agents.

##### Demo

[Watch in high quality on asciinema](https://asciinema.org/a/OsS8wwaasKasoDDz)

![llm.rb console demo](demo.gif)


##### Installation

The console is distributed with llm.rb so you don't have to install
a separate gem but it requires a number of optional dependencies
to be installed separately. The following gems provide the full
experience:

    gem install unicode-display_width curses kramdown xchan.rb test-cmd.rb

##### Persistence

the `path:` option can be set on an agent for automatic persistence
across console sessions. The `tools:` option attaches extra tools
for the duration of the session. Recall previous turns with Ctrl+P and
Ctrl+N.

```ruby
require "llm"
require "llm/tools"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, name: "my-agent", path: "agent.json")
agent.console(tools: LLM::Tool.subclasses)
```

##### CLI

The `llm.rb` executable is available on your PATH after installation.
It starts a console session from any directory. The CLI auto-detects your
provider from standard environment variables (`DEEPSEEK_API_KEY`,
`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.). Persistent sessions are
stored under `~/.llm.rb/` and restored automatically on your next visit.

```bash
llm.rb                     # auto-detect from $DEEPSEEK_API_KEY
llm.rb -p openai           # use OpenAI explicitly
llm.rb -t                  # temporary session, no persistence
```
</details>
<details>
<summary>Persistence</summary>
<br>

Set `path:` on an agent for automatic filesystem persistence:
the agent restores conversation history from the file on startup
and saves it back after every turn, with no manual serialization
code. For database-backed persistence, ActiveRecord and Sequel
integrations are also available. All persistence options use the same
underlying serialization.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, path: "session.json")
agent.talk "remember my name is robert"

# Next time, the conversation is restored automatically:
agent = LLM::Agent.new(llm, path: "session.json")
agent.talk "what's my name?"
```
</details>
<details><summary>ActiveRecord | Sequel</summary>
<br>

Because both
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html) and
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
can be serialized to JSON and stored in a simple string, both ActiveRecord
and Sequel support can be implemented within a single column on a single row.

The runtime includes first-class support for both ActiveRecord / Sequel, and
for both Rack-based / Rails-based applications. On databases
where it is supported, such as PostgreSQL, the column can be optimized by using
the `jsonb` type.

The following example is based on the agent used to power the
[r.uby.dev chatbot](https://r.uby.dev).

```ruby
require "active_record"
require "llm"
require "llm/active_record"

class Raven < ActiveRecord::Base
  acts_as_agent(format: :jsonb) do |agent|
    agent.set name: "raven",
              description: "a chatbot for the r.uby.dev website",
              instructions: proc { File.read(File.join(__dir__, "raven", "prompt.md")) },
              tools: :tools,
              concurrency: :async
  end

  def research_issues
    talk("research open pull requests on r-uby-dev/llm")
  end

  def research_codebase
    talk("research the codebase on r-uby-dev/llm")
  end

  ##
  # @return [LLM::MCP]
  def github
    @github ||= LLM::MCP.http(
      url: "https://api.githubcopilot.com/mcp/",
      headers: {"Authorization" => "Bearer #{ENV['GITHUB_RUBYDEV_PAT']}"},
      transport: :net_http_persistent
    )
  end

  ##
  # @return [Array<LLM::Tool>]
  def tools
    github.tools.select { allowlist.include?(_1.name.to_s) }
  end

  private

  def set_provider
    LLM.deepseek
  end

  def allowlist
    %w[
        get_commit
        get_file_contents
        list_branches
        list_commits
        search_code
        search_commits
        search_repositories
        search_issues
        pull_request_read
        list_pull_requests
        list_issues
        issue_read
    ].freeze
  end
end

agent = Raven.create!

##
# Every call to `talk` automatically persists
# to the database (under the hood research_issues
# calls the talk method)
agent.research_issues

##
# The conversation was persisted to database. A
# fresh instance restores it and continues where
# we left off
agent = Raven.find(agent.id).tap(&:research_codebase)

##
# Start an agent console.
# Query agent's state, debug, etc.
# The console does not persist back to the database.
agent.console
```
</details>

<details><summary>MCP</summary>
<br>

The Model Context Protocol (MCP) has first-class support
in llm.rb. The stdio and http transports work out of the
box. MCP tools are translated into subclasses of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html) that can be
used with
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html) or
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
mcp   = LLM::MCP.stdio(argv: ["ruby", "server.rb"])
agent = LLM::Agent.new(llm, stream: $stdout, tools: mcp.tools)
agent.talk "Run the tool"
```
</details>
<details><summary>A2A</summary>
<br>

The Agent 2 Agent (A2A) protocol has first-class support
in llm.rb. The http and jsonrpc transports work out of the
box. A2A skills are translated into subclasses of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html) that can be
used with
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html) or
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
a2a   = LLM::A2A.rest(url: "https://remote-agent.example.com")
agent = LLM::Agent.new(llm, stream: $stdout, tools: a2a.skills)
agent.talk "Run the skill"
```
</details>

<details><summary>Structured outputs</summary>
<br>

[`LLM::Schema`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html)
subclasses produce typed, structured
output from any model call. Pass a schema to
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk-instance_method),
[`LLM::Agent#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#talk-instance_method),
or
[`LLM::Provider#complete`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#complete-instance_method)
to receive validated JSON instead of free text. Schemas work alongside tools and streams.

[`LLM::Schema`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html)
can define objects, arrays, enums, nested schemas,
and more. It is also used internally by
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html) for parameter
definitions, so you already benefit from it when you declare tool
parameters.

The
[`LLM::DeepSeek`](https://r.uby.dev/api-docs/llm.rb/LLM/DeepSeek.html)
provider includes runtime-level optimisations such as structured
output support (despite no official structured outputs API) and
SVG image generation. This example uses
[`LLM::Schema`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html) with
DeepSeek:

```ruby
class Weather < LLM::Schema
  property :city, String, "The city name"
  property :temperature, Number, "Current temperature"
  property :conditions, String, "Weather conditions"
  required %i[city temperature conditions]
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, schema: Weather)
res = agent.talk "Weather in Paris?"
res.content!  # => {city: "Paris", temperature: 15.0, conditions: "Cloudy"}
```
</details>
<details><summary>Guards</summary>
<br>

[`LLM::Guard`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html)
is the hook that sees every tool call before it runs. A guard
can let a call through, cancel it, block it with an error, or
even answer for it. Because it runs before the tool, anything
it intercepts never executes. Policy, validation, quotas, and
cost ceilings all live here.

[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
enables
[`LLM::Guard::Loop`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard/Loop.html)
by default, so agents get loop protection out of the box. To
write your own guard, subclass
[`LLM::Guard`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html)
and implement
[`LLM::Guard#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html#call-instance_method).
The pending call arrives as `function:`. Return a value to close
the call, or `nil` to let it run:

```ruby
class PolicyGuard < LLM::Guard
  def call(function:)
    if function.name == "shell"
      function.return(error: true, type: "policy_error",
                      message: "shell is disabled")
    end
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: [Shell, ReadFile], guard: PolicyGuard)
```
</details>

<details>
<summary>Transformers</summary>
<br>

It is possible to rewrite outgoing messages before they reach the provider with
[`LLM::Transformer`](https://r.uby.dev/api-docs/llm.rb/LLM/Transformer.html).
Create a subclass and implement `call(message:)` to scrub sensitive data,
inject context, or normalize content. The transform runs automatically
on every turn, so you never have to change your prompt code.

```ruby
class RedactEmails < LLM::Transformer
  def call(message:)
    content = message.content.to_s.gsub(/[\w.+-]+@[\w-]+\.[\w.]+/, "[EMAIL]")
    LLM::Message.new(message.role, content, message.extra)
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, transformer: RedactEmails)
agent.talk "Contact support@example.com for help"
```
</details>

<details>
<summary>Compactors</summary>
<br>

Every model has a context window: the finite number of tokens it can
consider in a single request. Generally a compactor will drop or
summarize older messages to keep the conversation within that window,
and it runs automatically before every turn. By default it is disabled
so it is a feature you must opt into.

[`LLM::Compactor::Truncate`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor/Truncate.html)
keeps the most recent messages via an integer count or a percentage like
`"80%"`. It preserves tool call and return pairs so the conversation
never contains an orphaned result. It is also possible to subclass
[`LLM::Compactor`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor.html)
to implement your own compactor with its own logic. Streams can observe the
process through the
[`LLM::Stream#on_compaction`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_compaction)
and
[`LLM::Stream#on_compaction_finish`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_compaction_finish)
callbacks.

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(
  llm,
  compactor: LLM::Compactor::Truncate,
  compactor_options: {keep: 64}
)
agent.talk "Hello"
```
</details>

<details>
<summary>Automatic retries</summary>
<br>

Rate-limited requests are retried automatically by default. Agents
retry a 429 up to five times with a growing backoff before giving
up, so most request failures resolve on their own. Connection and
read timeouts are retried the same way. Set `retry_budget`
to change the number of retries, or `retry_budget: 0` to disable
them.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, retry_budget: 0)
agent.talk "Hello"
```

</details>


<details>
<summary>Observability</summary>
<br>

Trace what an agent is doing by attaching a tracer. Hook into
requests, tool calls, and other runtime events to debug a
misbehaving agent, monitor latency, or export spans to an
observability backend. All built-in tracers share one interface,
so switching between them means changing a class name:

* [`LLM::Tracer::PrettyLogger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/PrettyLogger.html): human-readable single-line logs to stderr, ideal during development.
* [`LLM::Tracer::Telemetry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Telemetry.html):
exports spans via OTLP for OpenTelemetry in production.
* [`LLM::Tracer::Logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html):
structured JSON to stdout or a file.

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tracer: LLM::Tracer::PrettyLogger.new(llm))
agent.talk "Hello"
```
</details>

<details>
<summary>As a subclass</summary>
<br>

[`LLM::Agent.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#set-class_method)
is a class-level DSL that accepts a Hash of properties. Each key resolves to a
corresponding class accessor: `name`, `description`, `model`, `tools`,
`instructions`, `schema`, `stream`, `tracer`, `concurrency`, `confirm`,
`path`, `skills`, `tool_budget`, and `retry_budget`. All options are
optional; zero or more can be set.
An error is raised for unknown keys so that typos are caught early.

```ruby
require "llm"
require "llm/tools"

class Agent < LLM::Agent
  set name: "sysadmin",
      description: "system administration agent",
      model: "deepseek-v4-pro",
      tools: [LLM::Tool::Exec]
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = Agent.new(llm)
agent.talk "Run 'date'"
```
</details>

### Providers

Each provider is constructed with a class-level factory method on
`LLM`, and the resulting instance is passed to
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
or
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html). The
same API drives every one of them, so switching providers is a one-line
change.

#### What providers does llm.rb support?

* **Anthropic** (`LLM.anthropic`)
* **Google** (`LLM.google`)
* **OpenAI** (`LLM.openai`)
* **DeepSeek** (`LLM.deepseek`)
* **DeepInfra** (`LLM.deepinfra`)
* **xAI** (`LLM.xai`)
* **Z.ai** (`LLM.zai`)
* **Moonshot (Kimi)** (`LLM.moonshot`)
* **OpenRouter** (`LLM.openrouter`)
* **Alibaba (Qwen3)** (`LLM.alibaba`, also `LLM.aliyun`)
* **Mistral** (`LLM.mistral`)
* **AWS Bedrock** (`LLM.bedrock`)
* **Ollama** (`LLM.ollama`)
* **llama.cpp** (`LLM.llamacpp`)

<details>
<summary>Implicit</summary>
<br>

Cloud providers can infer their API key automatically
from a set of common defaults that are defined by
the [models.dev](https://models.dev) registry that
is also distributed with llm.rb.

```ruby
llm = LLM.openai
llm = LLM.anthropic
llm = LLM.deepseek
llm = LLM.alibaba  # also: LLM.aliyun
llm = LLM.moonshot
llm = LLM.openrouter
llm = LLM.mistral
```
</details>
<details>
<summary>Explicit</summary>
<br>

The `key` option can also be providied explicitly, and certain
providers (eg ollama, llamacpp) usually do not require an API
key at all.

```ruby
llm = LLM.openai(key: ENV["OPENAI_API_KEY"])
llm = LLM.anthropic(key: ENV["ANTHROPIC_API_KEY"])
llm = LLM.deepseek(key: ENV["DEEPSEEK_API_KEY"])
llm = LLM.alibaba(key: ENV["DASHSCOPE_API_KEY"]) # also: LLM.aliyun
llm = LLM.moonshot(key: ENV["MOONSHOT_API_KEY"])
llm = LLM.openrouter(key: ENV["OPENROUTER_API_KEY"])
llm = LLM.mistral(key: ENV["MISTRAL_API_KEY"])
```
</details>

<details>
<summary>Model Registry</summary>
<br>

Each provider ships its model catalog, pricing, limits, and
modalities with the gem, sourced from [models.dev](https://models.dev).
Reach it from any provider, context, or agent, enumerate models, or
sort them by price.

```ruby
require "llm"

llm      = LLM.openai
registry = llm.registry                # => LLM::Provider#registry
cheapest = registry.models.sort.first  # => LLM::Model
cheapest.id                            # => "text-embedding-3-small"
cheapest.context_window                # => 8191
cheapest.structured_output?            # => false
```
</details>

<details>
<summary>Transports</summary>
<br>

The `transport:` option selects which HTTP library a provider uses for
network communication. Three backends ship out of the box: `net/http`
is always available and the default, `net/http/persistent` pools
connections for many requests to the same host, and `curb` wraps
libcurl. They share one interface, so switching is a one-word change.

```ruby
llm = LLM.deepseek(
  key: ENV["KEY"],
  transport: :net_http_persistent
)
```
</details>

<details>
<summary>Timeouts</summary>
<br>

Providers accept two timeouts:

* `connect_timeout` - opening the connection. Defaults to 5 seconds.
* `read_timeout` - waiting for a response on an idle connection.
  Defaults to 600 seconds (10 minutes).

The longer read timeout leaves room for slow reasoning models and
local models. The legacy `timeout:` option remains as a shorthand for
`read_timeout`. Timeouts are retriable:
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
retries a timed out request up to its
[`retry_budget`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#retry_budget-class_method)
(five by default), so a dropped connection or a slow first token
is often something we can recover from.

```ruby
llm = LLM.deepseek(
  connect_timeout: 5,   # opening the connection
  read_timeout: 600     # waiting for the next bytes
)
```
</details>

<details>
<summary>Headers</summary>
<br>

Providers can accept a custom set of headers with
the [`LLM::Provider#with`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#with-instance_method) method.
For example, you could set a custom User-Agent header,
or provide headers that carry special meaning to
certain providers (eg OpenAI, OpenRouter).

```ruby
llm = LLM.openrouter
llm = llm.with("HTTP-Referer" => "https://example.com")
llm = llm.with("X-OpenRouter-Title" => "Example App")
```

</details>

### RAG

Most providers offer an embedding model that can be
used for semantic search, or similarity search. An
embedding model can generate embeddings that can then
be stored in a database that is optimized for storing
and querying vectors, such as SQLite's [sqlite-vec](https://github.com/asg017/sqlite-vec)
or PostgreSQL's [pg-vector](https://github.com/pgvector/pgvector).

llm.rb also includes support for OpenAI's vector store API. It
provides a vector database as a HTTP service but we won't cover
that here.

```ruby
require "llm"

llm  = LLM.openai(key: ENV["KEY"])
body = "llm.rb is Ruby's capable AI runtime."
embedding = llm.embed([body]).embeddings.first

# Document is your ActiveRecord or Sequel model
# with a vector column (e.g. sqlite-vec or pgvector)
Document.create!(
  title: "llm.rb",
  body:,
  embedding:,
)
```

### Images

A handful of providers can generate images from a text prompt.
OpenAI, Google, xAI, and DeepInfra all support it. The API is
the same across providers:

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
res = llm.images.create(prompt: "a dog on a rocket to the moon")
IO.copy_stream res.images[0], "rocket.png"
```

##### DeepSeek

DeepSeek does not have a dedicated image model, but the runtime
generates SVG vector graphics through its text model. Each
generation produces a valid SVG document that can be converted
to PNG with tools like `rsvg-convert`. Pass an existing agent
to maintain a session across generations:

```ruby
require "llm"
llm = LLM.deepseek(key: ENV["KEY"])

##
# First generation
res = llm.images.create(prompt: "a rocket on the moon")
IO.copy_stream res.images[0], "rocket.svg"

##
# Refine with follow-up prompts (shares context)
res = llm.images.create(prompt: "add a dog next to the rocket",
                        agent: res.agent)
IO.copy_stream res.images[0], "rocket-with-dog.svg"
```

## FAQ

<details>
<summary>Where can I see llm.rb in action?</summary>
<br>
<p>

The [r.uby.dev](https://r.uby.dev) website is powered
by llm.rb and its builtin MCP feature. It is connected
to this very GitHub repository. It is designed to help
you learn and troubleshoot llm.rb.
</p>
<p>

The [4.4bsd.dev](https://4.4bsd.dev) website is also powered
by llm.rb but serves a different purpose: it is running a
system powered by FreeBSD and has access to the FreeBSD
manual pages and source code. It is designed to help you
learn and troubleshoot FreeBSD.
</details>
<details>
<summary>What about local LLM support?</summary>
<br>
<p>
The following providers can be run used with models that
are running on your own hardware. They're reasonably well
tested but not my main driver:
</p>

* Ollama
* Llamacpp
</details>

<details>
<summary>I have a limited budget. What should I do?</summary>
<br>
<p>
There are a few options. The first option is to host
your own model, and use the ollama or llamacpp
providers. This can be difficult though because
a capable model requires hardware that can
match it. If you have the ability to self-host,
this would be my first option.
</p>
<p>
The second option is DeepSeek. <br>
The deepseek-v4-flash model costs pennies to use. <br>
And llm.rb has been optimized for deepseek. For example,
DeepSeek does not have image generation capabilities
but on the llm.rb runtime it does (vector graphics only,
though).
</p>
<p>
The same is true for structured outputs. DeepSeek does
not support structured outputs in the same way as OpenAI or
Google, but the llm.rb runtime makes it appear as
though it does, through the `json_object` response
type.
</p>
If you're on a budget, DeepSeek is hard to beat.
</details>
<details>
<summary>Sources other than GitHub?</summary>
<br>
<p>
We are on the <a href="https://radicle.network">radicle.network</a> as well.
<br>
Every commit that lands on GitHub also lands on Radicle.
<br>
Our repository ID is z2PtfQ6dYwyYaW2aGrztG1sMyDmCE.
<br>
Browse on <a
href="https://radicle.network/nodes/iris.radicle.network/z2PtfQ6dYwyYaW2aGrztG1sMyDmCE">the
web</a>.
</p>
</details>

<details>
<summary>Who maintains llm.rb?</summary>
<br>

The llm.rb project is maintained primarily by one
person. llm.rb has been in active development for more
than three years and over that time multiple other
contributors have contributed to llm.rb as well. New
contributors are always welcome.

I use the console that is distributed with llm.rb to build
llm.rb itself so there is a healthy feedback loop and
llm.rb has also been battle tested in production
environments.

I have also also written llm.rb agents within the
repository that help me maintain the documentation,
and backport changes to the mruby-llm runtime as well.

I am constantly focused on improving llm.rb by using
it as my primary driver for development.
</details>

## See also

The [r.uby.dev chatbot](https://r.uby.dev) is connected
to this very GitHub repository. It can read documentation,
source code, issues, and pull requests. The [4.4bsd chatbot](https://4.4bsd.dev)
is also a llm.rb agent that is backed by ActiveRecord. It is
specialized in answering questions about FreeBSD and runs
on a FreeBSD system.

The [roda-llm](https://github.com/r-uby-dev/roda-llm#readme) project
is how I deploy multiple ActiveRecord-backed llm.rb agents over HTTP.
Each agent has an identical interface at a unique path that provide
CRUD operations and stream support (via SSE - Server Side Events).
It lets you focus on implementing agents rather than the glue that
brings them together. It is implemented as a Roda plugin that could
be hosted within a Rails application or other Rack-based applications.

The [docs/](docs/) directory contains the full documentation and
the chatbot can find the answers to your questions there. Or you
can read them yourself.

## License

This software is released under the terms of the MIT license. <br>
See [LICENSE](./LICENSE) for details.
