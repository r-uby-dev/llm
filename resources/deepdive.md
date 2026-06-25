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

Welcome to the llm.rb deepdive. This document is a continuation of
the [homepage documentation](https://r.uby.dev/llm). It assumes you
are familiar with the basics already, and focuses on features that
didn't make it into the homepage documentation.

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

  def on_compaction(ctx)
    # this callback is called *before* a compact happens
  end

  def on_compaction_finish(ctx, compactor)
    # this callback is called *after* a compact happens
  end
end
```

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

class Agent < Sequel::Model
  plugin(:agent, format: :jsonb) do |agent|
    agent.model "deepseek-v4-pro"
    agent.instructions "solve the user's query"
    agent.tools [Research, FinalizeResearch, ActOnResearch]
    agent.tracer { LLM::Tracer::Logger.new(llm, io: $stdout) }
  end

  private

  def set_provider
    LLM.deepseek(key: ENV["DEEPSEEK_SECRET"])
  end
end

agent = Agent.create
agent.talk "perform research"
```