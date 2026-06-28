<p align="center">
  <a href="https://r.uby.dev/llm/">
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

## Welcome

Welcome to the llm.rb deepdive. You are reading this document
in the markdown format. An optimized version exists
at [https://r.uby.dev/llm/deepdive](https://r.uby.dev/llm/deepdive)
and it is both easier to read and navigate.

This document is a continuation of the [homepage documentation](https://r.uby.dev/llm).
It assumes you are familiar with the basics already, and focuses on
features that didn't make it into the homepage documentation.

## Table of contents

- [Agents](#agents)
  - [As a subclass](#as-a-subclass)
  - [As an object](#as-an-object)
- [Skills](#skills)
  - [SKILL.md](#skillmd)
  - [Run it](#run-it)
- [MCP](#mcp)
  - [stdio](#stdio)
  - [http](#http)
- [A2A](#a2a)
  - [rest](#rest)
  - [jsonrpc](#jsonrpc)
- [Transports](#transports)
  - [net/http](#nethttp)
  - [net/http/persistent](#nethttppersistent)
  - [curb](#curb)
- [Stream](#stream)
  - [IO-like object](#io-like-object)
  - [LLM::Stream](#llmstream)
- [ORM](#orm)
  - [ActiveRecord](#activerecord)
  - [Sequel](#sequel)
- [Schema](#schema)
  - [Estimation](#estimation)
- [Cancellation](#cancellation)
  - [Cancel a request](#cancel-a-request)
- [Tracer](#tracer)
  - [Provider-wide tracer](#provider-wide-tracer)
  - [Agent-local tracer](#agent-local-tracer)
- [Images](#images)
  - [Generation](#generation)
  - [Edits](#edits)

## Agents

An agent is represented by the
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
class, and it is built on top of
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html) -
the heart of the runtime. An agent manages the tool loop automatically,
implements a tool loop guard for misbehaving models, and
it can use five different concurrency strategies to execute
tools.

An agent can be a subclass of
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html),
or a direct
instance of it. The subclass approach is useful when you
want reusable agents that can attach behavior (as methods)
to their own class.

#### As a subclass

A subclass of
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
can define its model, tools,
and other attributes at the class-level. All of these
attributes are optional, and they act as defaults that
can be overriden on the instance level.

The example uses the `:fork` concurrency model. It has
two primary benefits: tools are run in parallel, and in
a separate process with a separate memory address space.

The example purposefully demonstrates how the attributes
can be lazily defined with a block, or a Symbol that is
evaluated as an instance method on the subclass. It is
not strictly neccessary, though, and the example would
be simpler without it.

```ruby
class Agent < LLM::Agent
  model "deepseek-v4-pro"
  tools { [DoResearch, FinalizeResearch, ActOnResearch] }
  stream { $stdout }
  tracer :set_tracer
  concurrency :fork

  def research!
    talk "start the research"
  end

  private

  def set_tracer
    LLM::Tracer::Logger.new(llm, io: $stderr)
  end
end
llm   = LLM.deepseek(key: ENV["KEY"])
agent = Agent.new(llm).tap(&:research!)
agent.talk "How did the research go?"
```

#### As an object

The more direct, and sometimes more convienent approach, is to
create an instance of
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
directly. The same attributes can be provided as the
second argument given to
[`LLM::Agent.new`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html),
and the same lazy evaluation rules apply. This approach can be
great for prototyping quickly, and you can always turn to a
subclass later if that makes more sense.

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
agent.talk "Hello, fellow agent"
```

[Back to top](#table-of-contents)

## Tools

A tool extends the capabilities of a model. <br>
A tool is a subclass of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
that has a name,
a description, and an optional set of typed parameters.

A tool also has a method associated with it, and when the
model calls a tool it will do so through this method &ndash;
alongside any parameters the tool might have defined.

In other words, a tool provides a way for a model to
call a method you have written, and it returns a value
to the model that is considered the tool's response.
The model then proceeds to process the tool's response,
and then might generate its own response, or perhaps call
another tool.

#### LLM::Tool

A tool can be defined by subclassing
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
with
a name, description, and optional set of parameters. The
tool name, and description should be informative so the
model can understand what the tool does and how it can
serve a user's query.

```ruby
require "llm"
require "shellwords"

class Shell < LLM::Shell
  name "shell"
  description "execute a shell command"
  parameter :name, String, "the command's name"
  parameter :arguments, Array[String], "One or more arguments"
  required %i[name]
  defaults arguments: []

  def call(name:, arguments:)
    out = `#{name.shellscape} #{arguments.map(&:shellescape).join(" ")}`
    {ok: $?.success, out:}
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: [Shell], stream: $stdout)
agent.talk "What files are in the current working directory?"
```

#### Errors

Exceptions that might be raised by a tool are automatically
rescued and returned to the model as a structured error.
Otherwise &ndash; the conversation's history could be left
in an invalid state.

That's because a tool call must complete with a tool response,
that's the only valid response a model expects, so even in the
case of an error, something must be returned that communicates
what happened.

```ruby
class Error < LLM::Tool
  name "error"
  description "demo how errors are handled"

  ##
  # Returns
  # {error: true, kind: "RuntimeError", message: "boom"}
  def call
    raise "boom"
  end
end
```

## Skills

The skill concept is borrowed from tools like Claude and
Codex, but llm.rb gives it a runtime of its own. A skill
is a directory with a `SKILL.md` file. That file contains
frontmatter where the skill's name, description, and tools
can be declared.

#### SKILL.md

The `SKILL.md` file can look like this. When a skill runs,
the runtime spawns a subagent with its own context window
and message history. Some context is inherited from the
parent agent, though.

By default the subagent can only access the tools declared
by the skill. The `inherit` directive lets it inherit the
parent agent's tools instead, including A2A and MCP tools.

```markdown
---
name: git-skill
description: reads my git history and writes a summary
tools: ['git-log', 'git-show', 'write-file']
---

## Task

Collect a log of recent history.
Analyze each commit.
Write a summary to summary.txt
```

#### Run it

Given the skill above, llm.rb only needs the path to the
directory that contains `SKILL.md`. Under the hood, a skill
is represented as a tool the model can call. That means
a skill can be called whenever it satisfies the user's
request &ndash; in the same way that a regular tool can.

This feature also works with both the ActiveRecord, and
Sequel integrations.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, skills: [__dir__])
agent.talk "run the git skill"
```

[Back to top](#table-of-contents)

## MCP

#### stdio

The stdio transport connects to an MCP server that is launched as a
separate process, and both its standard input and standard output
streams are used for communication. It is recommended but not
required to execute commands for a stdio transport over a
persistent session via the
[`LLM::MCP#session`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#session-instance_method)
method &ndash; otherwise
you could end up launching the same process multiple times.

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
mcp   = LLM::MCP.stdio(argv: ["npx", "-y", "@forgejo/mcp-server"])
agent = LLM::Agent.new(llm)

mcp.session do
  agent.talk "What's happening on forgejo?", tools: mcp.tools
end
```

#### http

The http transport connects to an MCP server over HTTP, and unlike
the stdio transport, the MCP server does not have to be running
locally. Popular services like GitHub provide their own MCP server
over HTTP, and it is one of the most capable MCP servers I have
used.

Unlike the stdio transport,
[`LLM::MCP#session`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#session-instance_method)
carries little benefit for the http transport and it can be
omitted.  It is recommended to consider the `net_http_persistent`
transport for MCP interactions that run over HTTP, otherwise
you could end up tearing down and setting up the same connection
multiple times.

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
mcp   = LLM::MCP.http(
  url: "https://api.githubcopilot.com/mcp/",
  headers: {
    "Authorization" => "Bearer #{ENV.fetch('GITHUB_PAT')}"
  },
  transport: :net_http_persistent
)
agent = LLM::Agent.new(llm)
agent.talk "What's happening on GitHub?", tools: mcp.tools
```

[Back to top](#table-of-contents)

## A2A

#### rest

The rest transport communicates with other agents via A2A
endpoints that speak both HTTP and JSON. The skills advertised
by an agent become subclasses of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
that can be used by both
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html),
and [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
&ndash; similar to how MCP tools become subclasses of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html).

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
a2a   = LLM::A2A.rest(url: "https://agent.example.com")
agent = LLM::Agent.new(llm, tools: a2a.skills)
agent.talk "What's happening, fellow agent?"
```

#### jsonrpc

The jsonrpc transport communicates with other agents via HTTP
and a protocol known as jsonrpc. Sometimes an agent will
implement both, or just one of each. An agent's card, which
is represented by an instance of
[`LLM::A2A::Card`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A/Card.html),
can be
used to discover available transports via the
[`LLM::A2A::Card#interfaces`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A/Card.html#interfaces-instance_method)
method.

```ruby
require "llm"
llm   = LLM.deepseek(key: ENV["KEY"])
a2a   = LLM::A2A.jsonrpc(url: "https://agent.example.com")
agent = LLM::Agent.new(llm, tools: a2a.skills)
agent.talk "What's happening, fellow agent?"
```

[Back to top](#table-of-contents)

## Transports

The [`LLM::Provider`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html),
[`LLM::MCP`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html), and
[`LLM::A2A`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A.html) classes
all accept a `transport` option that decides which library
will be used for HTTP communication. There are three options out
of the box:
[`net-http`](https://github.com/ruby/net-http),
[`net-http-persistent`](https://github.com/drbrain/net-http-persistent),
and [`curb`](https://github.com/taf2/curb).

#### net/http

The [`net/http`](https://github.com/ruby/net-http) transport is represented by the symbol `:net_http`. <br>
It is the default transport.

```ruby
require "llm"

llm = LLM.deepseek(key: "...", transport: :net_http)
mcp = LLM::MCP.http(url: "...", transport: :net_http)
a2a = LLM::A2A.rest(url: "...", transport: :net_http)
```

#### net/http/persistent

The [`net/http/persistent`](https://github.com/drbrain/net-http-persistent) transport is represented by the symbol `:net_http_persistent`. <br>
It maintains a connection pool so the cost of tearing down and
setting up a connection repeatedly is kept low, and it is built
on top of [`net/http`](https://github.com/ruby/net-http).

```ruby
require "llm"

llm = LLM.deepseek(key: "...", transport: :net_http_persistent)
mcp = LLM::MCP.http(url: "...", transport: :net_http_persistent)
a2a = LLM::A2A.rest(url: "...", transport: :net_http_persistent)
```

#### curb

The [`curb`](https://github.com/taf2/curb) transport is represented by the symbol `:curb`. <br>
It provides bindings for libcurl &ndash; a widely used, highly portable
and feature-rich HTTP library written in C.

```ruby
require "llm"

llm = LLM.deepseek(key: "...", transport: :curb)
mcp = LLM::MCP.http(url: "...", transport: :curb)
a2a = LLM::A2A.rest(url: "...", transport: :curb)
```

[Back to top](#table-of-contents)

## Stream

#### IO-like object

Any object that implements the `#<<` method can receive
chunks from a stream. That includes objects like `$stdout`.
This form of streaming is simple and limited. It is the
equivalent of
[`LLM::Stream#on_content`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_content-instance_method),
and doesn't include
any of the other
[`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html)
hooks.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
agent.talk "hello world"
```

#### LLM::Stream

The [`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html)
class provides many hooks that a subclass
can implement. They range from being notified when a tool call
starts to when a tool call finishes, or when a conversation is
due to be compacted because the context window exceeded a defined
limit. All these callbacks support a responsive user interface
where the user is always aware of what is happening behind the
scenes.

```ruby
class Stream < LLM::Stream
  def on_content(content)
    puts content
  end

  def on_reasoning_content(content)
    puts content
  end

  def on_tool_call(tool, error)
    # this callback can be used to either log a tool call,
    # or execute a tool call during a stream.
  end

  def on_tool_return(tool, result)
  end

  def on_compaction(ctx, compactor)
    # this callback is called *before* a compact happens
  end

  def on_compaction_finish(ctx, compactor)
    # this callback is called *after* a compact happens
  end
end
```

[Back to top](#table-of-contents)

## ORM

Both ActiveRecord, and Sequel have first-class support on the
llm.rb runtime. In both cases an ActiveRecord or Sequel model
can be turned into a model that has the same capabilities as
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html),
or [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).

The main difference is that the runtime persists directly into
the database with no requirements beyond a single column on a
single row. That means it is usually trivial to turn an existing
model into an AI-aware model.

#### ActiveRecord

The ActiveRecord interface for
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
is
[`acts_as_agent`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/ActsAsAgent.html).
It yields an instance of
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html),
and that can be used
to configure the agent (eg which model, instructions, skills,
tools, etc).

An interesting option is the `format` option, by default it
defaults to `:string` but it can also be changed to `:json`
or `:jsonb` depending on the configuration and type of underlying
column. The JSONB column type is recommended.

```ruby
require "active_record"
require "llm"
require "llm/active_record"

class Agent < ApplicationRecord
  acts_as_agent(format: :jsonb) do |agent|
    agent.model "deepseek-v4-pro"
    agent.instructions "solve the user's query"
    agent.tools [Research, FinalizeResearch, ActOnResearch]
  end

  private

  ##
  # By convention, this method defines the provider
  # for a model. If neccessary, it can be renamed and
  # configured via `provider: :your_method` instead.
  def set_provider
    LLM.deepseek(key: ENV["KEY"])
  end

  ##
  # By convention, this method should return what is
  # given as the second argument to `LLM::Context` or
  # `LLM::Agent`.
  #
  # Often, there is no need to set it, so it can be left
  # undefined or it can be reassigned in the same way as
  # `set_provider`. For example: `context: :your_method`
  def set_context
    {}
  end
end

agent = Agent.create!
agent.talk "perform research"
```

#### Sequel

The following is a Sequel equivalent to the ActiveRecord example,
but to keep it interesting and informative, this example also
configures a per-model tracer that logs to `$stdout`. Works the
same for ActiveRecord.

```ruby
require "sequel"
require "llm"
require "llm/sequel/plugin"

class Agent < Sequel::Model
  plugin(:agent, format: :jsonb) do |agent|
    agent.model "deepseek-v4-pro"
    agent.instructions "solve the user's query"
    agent.tools [Research, FinalizeResearch, ActOnResearch]
    agent.tracer { LLM::Tracer::Logger.new(llm, io: $stdout) }
  end

  private

  def set_provider
    LLM.deepseek(key: ENV["KEY"])
  end
end

agent = Agent.create
agent.talk "perform research"
```

[Back to top](#table-of-contents)

## Schema

The [`LLM::Schema`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html)
class can be subclassed to describe
the shape of a JSON object or objects that you expect
the model to respond with.

It can be useful for a wide range of use cases but the
most popular might be classification, data extraction,
and transferring structured data between different software
rather than blobs of text that a machine cannot easily parse
in a structured way.

#### Estimation

The following example asks the model to estimate the age
of a person in a photo. The model provides a structured response
that's represented by an instance of
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html).

The object returned by
[`LLM::Response#content!`](https://r.uby.dev/api-docs/llm.rb/LLM/Contract/Completion.html#content!-instance_method)
has methods that can access the age, confidence, and comments
properties.
This approach can also work for extracting data or an analysis
from a PDF, and other file types.

```ruby
require "llm"
require "pp"

class Estimation < LLM::Schema
  property :age, Integer, "The estimated age of the person"
  property :confidence, Number, "Your confidence in the estimate"
  property :applicable, Boolean, "True when the photo contains a person"
  property :comments, String, "Any additional comments or input"
  required %i[age confidence applicable comments]
end

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm, schema: Estimation)
res = agent.ask "Given this photo, provide an age estimate", with: "photo.jpg"

##
# Coerces the model's response from a JSON string
# to an instance of LLM::Object.
estimate = res.content!

##
# Let's print the estimate
if estimate.applicable
  print "The person is approx ", estimage.age, " years old", "\n"
  print "I have a confidence rating of ", estimate.confidence.to_s, "\n"
else
  print "This photo is not applicable:", "\n"
  print estimate.comments
end
```

[Back to top](#table-of-contents)

## Cancellation

#### Cancel a request

A common scenario when communicating with a model is to
want to cancel the request mid-stream. This could be done
for a number of different reasons, most often because the
user made a mistake, or the model is making a mistake and
the user wants to cancel the action.

The runtime has built-in support for cancellation. So for
example it is possible to cancel a request on the main
thread from a secondary thread. A number of things happen
when a request is cancelled. First the request is cancelled
at the transport level, and each transport handles it a little
differently. The net effect in every case is that the connection
is closed.

The runtime then notifies the rest of the system. so for example,
if a tool was running, it will receive the `on_interrupt` / `on_cancel`
callback that lets the tool do any necessary cleanup, or execute its own
cancellation plan. Tools that were pending (not yet run but requetsed to
run) are cancelled through
[`LLM::Function#cancel`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#cancel-instance_method).

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["DEEPSEEK_SECRET"])
agent = LLM::Agent.new(llm)
queue = Queue.new

Thread.new do
  queue.push(nil)
  sleep(2)
  agent.cancel!
end

begin
  queue.pop
  agent.talk "write me a very long poem", stream: $stdout
rescue LLM::Interrupt
  puts "request cancelled!"
end
```

[Back to top](#table-of-contents)

## Tracer

The runtime can be observed by subclasses of
[`LLM::Tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html). <br>
The default tracers include a tracer that can write to standard
output
([`LLM::Tracer::Logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html)),
and a generic OpenTelemetry tracer that can export spans via OTLP
([`LLM::Tracer::Telemetry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Telemetry.html)).

llm.rb has numerous hooks implemented throughout the runtime that
[`LLM::Tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html)
subclasses can hook into, and the tracer is
purposefully designed to be extensible. The scope of a trace
can vary from an individual agent (an instance of
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)),
or for every request a provider makes (an indirect instance of
[`LLM::Provider`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html)).

#### Provider-wide tracer

The following two examples demonstrate provider-wide tracers that
cover every request made for a single provider.

```ruby
##
# Provider-wide tracer
# Writes to $stdout
llm = LLM.deepseek(key: ENV["KEY"])
llm.tracer = LLM::Tracer::Logger.new(llm, io: $stdout)

##
# Provider-wide tracer
# Writes to deepseek.log
llm = LLM.deepseek(key: ENV["KEY"])
llm.tracer = LLM::Tracer::Logger.new(llm, path: "deepseek.log")
```

#### Agent-local tracer

The next two examples demonstrate a tracer that is local
to an agent.

```ruby
##
# Agent-local
# Writes to $stdout
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tracer: LLM::Tracer::Logger.new(llm, io: $stdout))

##
# Agent-local
# Writes to deepseek-agent.log
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tracer: LLM::Tracer::Logger.new(llm, path: "deepseek-agent.log"))
```

[Back to top](#table-of-contents)

## Images

The OpenAI, Google, xAI, and DeepInfra providers have builtin
image generation capabilities. OpenAI, xAI, and DeepInfra also
support image edits. Google, though, only supports image
generation and not edits.

#### Generation

The [`LLM::Provider#images`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#images-instance_method)
method returns an Image
object that a subset of providers implement. At the
moment Google, xAI, OpenAI, and DeepInfra have image generation
capabilities.

```ruby
require "llm"

##
# Store dogrocket.png
llm = LLM.openai(key: ENV["KEY"])
res = llm.images.create(prompt: "a dog on a rocket to the moon")
IO.copy_stream res.images[0], "dogrocket.png"
```

The API is the same across providers. <br>
For example &ndash; xAI:

```ruby
require "llm"

##
# Store dogrocket.png
# Same API as OpenAI
llm = LLM.xai(key: ENV["KEY"])
res = llm.images.create(prompt: "a dog on a rocket to the moon")
IO.copy_stream res.images[0], "dogrocket.png"
```

#### Edits

OpenAI, xAI, and DeepInfra have the same interface for image edits. <br>
Google does not have edit image support. <br>

```ruby
require "llm"

##
# Edit self.jpg and add a mustache
# Save to mustache.png
llm = LLM.openai(key: ENV["KEY"])
res = llm.images.edit(prompt: "add a mustache", image: "self.jpg")
IO.copy_stream res.images[0], "mustache.png"
```

[Back to top](#table-of-contents)
