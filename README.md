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

> [r.uby.dev](https://r.uby.dev/llm) project.

Welcome to the canonical llm.rb repository.

llm.rb is a runtime for building agentic AI applications
on CRuby. It has zero runtime dependencies by default, supports
concurrent and parallel tool execution and has a single coherent API
that spans 14+ providers.
The README covers the common cases. For everything else there is the
[deepdive](docs/deepdive.md), a reference with a chapter for each
topic, and for what changes between releases there is the
[changelog](CHANGELOG.md).

[The r.uby.dev website](https://r.uby.dev) hosts
an agentic platform that provides users with
personalized agents who can access GitHub, and
other services. It is built with llm.rb. Check it
out if curious. **Still in early development.**

## Install

llm.rb requires Ruby 3.4 or later.

```bash
gem install llm.rb
```

## Quick start

### Agents

The
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
class is the default high-level interface,
and it is recommended for most use-cases. It manages the tool loop
and provides configurable features on top of it. For example you can
manage the tool loop with a retry budget alongside a tool call budget,
among other features.

The runtime is designed to keep the tool loop alive and it will
avoid exceptions. When an error is encountered in a tool or during
the lifecycle of an agent it is almost always reported back to the
model as an in-band error that allows the model to correct course.

A lot of care also goes into keeping the tool loop from entering
an invalid state that would lead to API-level errors. For example,
when a tool call is interrupted it could leave an unanswered tool
call that a model will reject on the next turn. The runtime closes
every tool call that has no return before the next request is sent,
and each one is answered with an in-band return of its own. The
conversation a provider sees is therefore always valid, and a
cancelled call is something the model is told about rather than
something that quietly disappears.

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
reasoning, tool calls, tool returns, steps in a turn, and compaction.
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

  # A request has completed: the response is in the conversation, and
  # any tools it asked for run after this.
  def on_step(ctx, res)
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
filesystem, search, and shell operations, and providers expose
platform-native tools such as web search and code execution that run
on the provider's side.

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
gem and the `fork` strategy requires the [xchan.rb](https://github.com/r-uby-dev/xchan.rb)
gem (`~> 0.24`). The `fiber` strategy requires a scheduler (`Fiber.scheduler`) but by
default Ruby does not provide one.

The `:ractor` strategy is the least interchangeable of the six. It runs
class-based tools only, and a tool's arguments have to be
ractor-shareable.

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

It is possible to abort a request mid-stream and interrupt
running tool calls with
[`LLM::Agent#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#interrupt!)
(or `cancel!`).

A cancel is aimed at the tool rather than at whatever happens to be
running. A call that is running is entered, and
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
is raised inside it, so its own `rescue` sees it and it can free
resources before it dies - on every concurrency strategy alike. The
socket a request is waiting on is closed before the raise, so a
cancelled request stops burning tokens, and the request itself is a
fiber that is interrupted like any other. A call that has not started
is not skipped: the cancel is held and delivered inside the call once
it opens, so a tool that was asked about before it began is still the
one that cleans up. A call that has already answered is a no-op that
leaves the result alone, and a cancel that arrives between two
requests ends the turn where it is.

The raise sits outside `StandardError`, so a bare `rescue`, or a
`rescue => e`, passes a cancel through instead of swallowing it. A
tool that means to handle one names it: `rescue LLM::Interrupt`.

A tool can also implement `#on_interrupt` to be told. The hook runs
before the raise lands, so a tool that releases a resource has
released it by the time the interrupt arrives, and it runs on the
thread or fiber the call runs on.

Two of the six strategies have a shape of their own, and both are
about where a raise can be placed. `:fiber` and `:async` ask the
fiber scheduler for the raise, so a tool that never suspends is one
the raise cannot reach - the call completes, the caller is given its
result, and the tool is told it was asked about. `:sequential` runs
the tool in the caller's own thread, so the hook is what tells it,
and nothing is raised into the call.

```ruby
class Search < LLM::Tool
  name "search"
  description "Search many files"

  def call(pattern:)
    search(pattern)
  rescue LLM::Interrupt
    ##
    # The cancel is raised inside the call, so this rescue runs.
    cleanup
    raise
  end

  ##
  # Told before the raise lands, on the thread or fiber the
  # call runs on. A tool that only wants the notification
  # implements this and nothing else.
  def on_interrupt
    cleanup
  end

  private

  def cleanup
    # Release a file, a socket, or a lock here.
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: [Search])
Thread.new { sleep(1); agent.cancel! }

begin
  agent.talk "find every TODO in the repository", stream: $stdout
rescue LLM::Interrupt
  puts "cancelled"
end
```
</details>
<details>
<summary>Console (<code>binding.irb</code> for agents)</summary>
<br>

The [LLM::Agent#console](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#console-instance_method)
method drops you into an interactive console that is built on
top of curses. It can help you debug agents, test your tools,
connect to MCP servers, and other A2A agents. The console stands
out because it connects to the surrounding runtime and it can
be extended by your code. Think of it as `binding.irb` but
for agents.

##### Demo

![llm.rb console demo](demo.gif)


##### Installation

The console is distributed with llm.rb but it requires a number
of optional dependencies to be installed separately. The following
gems provide the full experience:

    gem install unicode-display_width curses kramdown xchan.rb test-cmd.rb

For convenience it is also possible to just use the following, it
is a metagem that depends on llm.rb and all the dependencies it requires
to run the console:

    gem install llm-shell

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
llm.rb                     # auto-detect from $PROVIDER_API_KEY
llm.rb -p openai           # use OpenAI explicitly
llm.rb -m gpt-5.6          # use a model other than the provider default
llm.rb -c thread           # run tool calls on a separate thread
llm.rb -n curb             # use libcurl as the HTTP transport
llm.rb -x 900              # read timeout of 15 minutes
llm.rb -t                  # temporary session, no persistence
llm.rb -v                  # print the version
llm.rb -h                  # print usage
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

```ruby
require "active_record"
require "llm"
require "llm/active_record"

##
# The Robert agent.
class Robert < ActiveRecord::Base
  acts_as_agent(format: :jsonb) do |agent|
    agent.set name: "robert",
              description: "robert is an agent that has access to the official " \
                            "r.uby.dev GitHub repositories. He can access the repositories " \
                            "to answer your question(s) about r.uby.dev projects.",
              instructions: proc { File.read(File.join(__dir__, "robert", "prompt.md")) },
              tools: :tools,
              concurrency: :async,

              ##
              # The maximum number of tool calls per-turn.
              tool_budget: 25,

              ##
              # The default tracer that all agents have associated
              # with them. The tracer exports a trace to a couple of
              # SQL tables.
              tracer: proc { Raven::Tracer::SQL.new(llm, agent: self) }
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

agent = Robert.create!

##
# Every call to `talk` automatically persists
# to the database.
agent.talk "what's new on the llm.rb repository?"

##
# The conversation was persisted to database. A
# fresh instance restores it and continues where
# we left off
agent = Robert.find(agent.id).talk "and what about roda-llm?"

##
# Start an agent console.
# Query agent's state, debug, etc.
# The console does not persist back to the database.
agent.console
```
</details>
<details>
<summary> SQL optimizations </summary>
<br>

In a database environment the runtime optimizes for
the PostgreSQL database and its builtin support for
the `jsonb` column type. An agent fits in a single
column, on a single row, and that column carries
everything it has done: messages, tool calls,
context usage, and so on. It works well in practice
and means you can store an agent almost anywhere.

For scenarios where performance matters most the runtime
ships with virtual ActiveRecord classes that never materialize
in your database but provide a SQL view into the column where
an agent stores its runtime state. They return
[`ActiveRecord::Relation`](https://api.rubyonrails.org/classes/ActiveRecord/Relation.html)
objects, so the filtering happens in the database.

```ruby
class Agent < ActiveRecord::Base
  acts_as_agent(format: :jsonb) do |agent|
    agent.set name: "activerecord agent"
  end
end

##
# Find an instance of your agent
agent = Agent.find_by(id: 1)

##
# Returns a relation over the agent's messages.
# It is scoped to the agent, and it yields one
# instance of LLM::ActiveRecord::Message per
# message the agent has produced.
messages = LLM::ActiveRecord::Message.for(agent:)

##
# The relation chains like any other
messages.where(role: "assistant")
        .order(position: :desc)
        .limit(10)

##
# Count, too
messages.count
```

**Schema**

Each row carries a message, flattened into columns:

| column | contents |
| --- | --- |
| `agent_id` | the agent a message belongs to |
| `id` | the message id |
| `role` | the message role |
| `content` | the message content |
| `tools` | the tool calls a message carries |
| `position` | the position of a message in the conversation |
| `data` | the whole message, as the runtime stores it |

**Indexes**

The queries the view runs are already covered. They expand
one agent, found by primary key, so they are index scans.
There is nothing to add for
`LLM::ActiveRecord::Message.for(agent:)`.

The queries you write on top of it are not. Once a question
is asked of every agent, the column is expanded row by row
and no index helps the view itself. Index the column for
those questions instead:

```sql
CREATE INDEX index_agents_on_data
  ON agents USING gin (data jsonb_path_ops);

CREATE INDEX index_agents_on_context_used
  ON agents (((data ->> 'context_used')::int));
```

The first serves containment (`@>`) and path queries over
the state as a whole. The second serves a scalar key, and
the runtime already writes `context_used` and
`context_window` at the top level, so "sessions over 80%
full" becomes cheap. Both assume `format: :jsonb`.

**However:** an agent's whole conversation lives in one
value, so every save rewrites it, and a GIN index is
maintained with it. Prefer an index on a key or two over
the whole column.

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

Agents and contexts use
[`LLM::Guard::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard/Null.html)
by default, so a guard only runs when you configure one. To
write your own guard, subclass
[`LLM::Guard`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html)
and implement
[`LLM::Guard#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html#call-instance_method).
The pending call arrives as `function:`. Return a value to close
the call, or `nil` to let it run:

```ruby
class PolicyGuard < LLM::Guard
  def call(function:)
    if function.name == "exec"
      function.return(error: true, type: "policy_error",
                      message: "exec is disabled")
    end
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: [LLM::Tool::Exec, ReadFile], guard: PolicyGuard)
```
</details>

<details>
<summary>Transformers</summary>
<br>

It is possible to rewrite outgoing messages before they reach the provider with
[`LLM::Transformer`](https://r.uby.dev/api-docs/llm.rb/LLM/Transformer.html). Create a subclass and implement `call(message:)` to scrub sensitive data,
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
<summary>Usage and cost</summary>
<br>

Every context and agent reports what a conversation has spent and how
much room is left, and the numbers answer different questions. A
`token_usage` is the whole conversation, summed as an
[LLM::Usage](https://r.uby.dev/api-docs/llm.rb/LLM/Usage.html), and it
is what [LLM::Cost](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html)
prices against the model registry:

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm)
agent.talk "Hello"

agent.token_usage  # => LLM::Usage for the whole conversation
agent.cost         # => LLM::Cost, priced from the registry
```

A `context_used` is one turn's worth - the live size of the most recent
assistant message - so it is what a context window is really being
spent on, and `context_usage` is that as a fraction of the window:

```ruby
agent.context_used    # => tokens in the latest turn
agent.context_window  # => the model's limit, or nil when unknown
agent.context_usage   # => Rational, eg Rational(100, 10_000)
```

</details>


<details>
<summary>Observability</summary>
<br>

It is possible to trace what an agent is doing by attaching a
tracer. A tracer can hook into requests, tool calls, and other
runtime events to debug an agent, provide insights, monitor latency,
or export spans to an observability backend. All built-in tracers
share one interface, so switching between them means changing a
factory method:

* [`LLM::Tracer.pretty_logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#pretty_logger-class_method): human-readable single-line logs to stderr, ideal during development.
* [`LLM::Tracer.telemetry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#telemetry-class_method):
exports spans via OTLP for OpenTelemetry in production.
* [`LLM::Tracer.logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#logger-class_method):
structured JSON to stdout or a file.

It is also possible to create your own tracer by creating a subclass
of [`LLM::Tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html)
that implements a number of callbacks that cover an agent's lifecycle.
The tracer feature provides visibility into what the runtime is doing,
and the tracer API lets other code hook into that feature.

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tracer: LLM::Tracer.pretty_logger(llm))
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
llm = LLM.google
llm = LLM.deepseek
llm = LLM.deepinfra
llm = LLM.xai
llm = LLM.zai
llm = LLM.moonshot
llm = LLM.openrouter
llm = LLM.alibaba  # also: LLM.aliyun
llm = LLM.mistral
llm = LLM.bedrock
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
llm = LLM.google(key: ENV["GOOGLE_API_KEY"])
llm = LLM.deepseek(key: ENV["DEEPSEEK_API_KEY"])
llm = LLM.deepinfra(key: ENV["DEEPINFRA_API_KEY"])
llm = LLM.xai(key: ENV["XAI_API_KEY"])
llm = LLM.zai(key: ENV["ZHIPU_API_KEY"])
llm = LLM.moonshot(key: ENV["MOONSHOT_API_KEY"])
llm = LLM.openrouter(key: ENV["OPENROUTER_API_KEY"])
llm = LLM.alibaba(key: ENV["DASHSCOPE_API_KEY"]) # also: LLM.aliyun
llm = LLM.mistral(key: ENV["MISTRAL_API_KEY"])
llm = LLM.bedrock(
  access_key_id: ENV["AWS_ACCESS_KEY_ID"],
  secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
  region: ENV["AWS_REGION"]
)
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
cheapest = registry.models.sort.first  # => LLM::Registry::Model
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

The [r.uby.dev](https://r.uby.dev) website.

</details>
<details>
<summary>What about local LLM support?</summary>
<br>

The following providers can be run used with models that
are running on your own hardware.

* Ollama
* Llamacpp
</details>

<details>
<summary>I have a limited budget. What should I do?</summary>
<br>

There are a few options. The first option is to host
your own model, and use the ollama or llamacpp
providers. This can be difficult though because
a capable model requires hardware that can
match it. If you have the ability to self-host,
this would be my first option.

The second option is DeepSeek. <br>
The deepseek-v4-flash model costs pennies to use. <br>
And llm.rb has been optimized for deepseek. For example,
DeepSeek does not have image generation capabilities
but on the llm.rb runtime it does (vector graphics only,
though).

The same is true for structured outputs. DeepSeek does
not support structured outputs in the same way as OpenAI or
Google, but the llm.rb runtime makes it appear as
though it does, through the `json_object` response
type.

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

The llm.rb project was started more than three
years ago by
[@altruby](https://github.com/altruby) and
[@antaz](https://github.com/altruby). The primary
maintainer is [@altruby](https://github.com/altruby).
Over those three years multiple other contributors have
contributed to llm.rb as well, and new contributors are
always welcome.
</details>

<details>
<summary>How well tested is llm.rb?</summary>
<br>

It is battle tested daily.

The console that is distributed with llm.rb is used
to build llm.rb so there is a healthy, active feedback
loop. It also powers the [r.uby.dev](https://r.uby.dev)
website where multiple llm.rb agents are deployed. I'm
aware of at least one production Rails deployment
at a large-ish company.

And this git repository includes llm.rb agents that help me
maintain the documentation and perform other repository
maintainence. The feedback loop is constant. Outside of that
there is a large test suite that covers live requests (recorded
by VCR) and database interactions.
</details>

## License

This software is released under the terms of the MIT license. <br>
See [LICENSE](./LICENSE) for details.
