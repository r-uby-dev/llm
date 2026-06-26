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

Welcome to the canonical llm.rb repository.

llm.rb is not a library, framework or toolkit but an advanced runtime
for building highly capable AI applications on CRuby. By default
it has zero runtime dependencies although certain functionality &ndash;
such as ActiveRecord support &ndash; require optional dependencies
that are opt-in.

## Features

The runtime supports OpenAI, OpenAI-compatible endpoints, Anthropic, Google
Gemini, DeepSeek, xAI, Z.ai, AWS Bedrock, Ollama, and llama.cpp.
It has first-class support for streaming, tool calls,  MCP
and A2A, embeddings, vector stores and the RAG pattern.

There are multiple HTTP backends to choose from, tools can be run concurrently
or in parallel via threads, async tasks, fibers, ractors, and fork, and it is
also possible to make a tool call while the model is still streaming.

The runtime builds on top of three core concepts: providers, contexts, and agents,
so once you learn the fundamentals, everything else falls into place naturally. And once
you learn llm.rb, you will also be able to use <a href="https://r.uby.dev/mruby-llm">mruby-llm</a> and
<a href="https://r.uby.dev/wasm-llm">wasm-llm</a> because the API is pretty much identical.

## Install

```bash
gem install llm.rb
```

## Quick start

#### LLM::Agent

The [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html) class is the default high-level interface,
and it is recommended for most use-cases. It manages tool execution
automatically, guards against infinite loops, manages conversation
state, and much more.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
agent.talk "Hello world"
```

#### LLM::Context

The [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html) class is at the heart of the runtime
and it is what [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html) uses under the hood.
It requires that the tool call loop be managed manually -
sometimes that can be useful, but usually for advanced use-cases.
If you're new to llm.rb, try [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html) first.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
ctx = LLM::Context.new(llm, stream: $stdout)
ctx.talk "Hello world"
```

#### LLM::Tool

Subclasses of [`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html) are plain Ruby classes with
an optional set of typed parameters. <br> The model can choose to
call them on your behalf, and they're one of the most powerful features
for extending the feature set or abilities of a model.

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
```

#### LLM::Stream

Streams can be simple IO objects or subclasses of
[`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html) with structured callbacks for content,
reasoning, tool calls, tool returns, and compaction.

```ruby
class MyStream < LLM::Stream
  def on_content(content)
    print content
  end

  def on_reasoning_content(content)
    warn content
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: MyStream.new)
agent.talk "Explain Ruby fibers."
```

#### LLM::MCP

The Model Context Protocol (MCP) has first-class support
in llm.rb. The stdio and http transports work out of the
box. MCP tools are translated into subclasses of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html) that can be used with [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
or [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
mcp   = LLM::MCP.stdio(argv: ["ruby", "server.rb"])
agent = LLM::Agent.new(llm, stream: $stdout, tools: mcp.tools)
agent.talk "Run the tool"
```

#### LLM::A2A

The Agent 2 Agent (A2A) protocol has first-class support
in llm.rb. The http and jsonrpc transports work out of the
box. A2A skills are translated into subclasses of
[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html) that can be used with [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
or [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
a2a   = LLM::A2A.rest(url: "https://remote-agent.example.com")
agent = LLM::Agent.new(llm, stream: $stdout, tools: a2a.skills)
agent.talk "Run the skill"
```

#### RAG

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

Document.create!(
  title: "llm.rb",
  body:,
  embedding:,
)
```

#### Concurrency

The runtime supports five different concurrency strategies that have
different attributes. The choice between all of them often depends
on the requirements of your application.

IO-bound tools are a good fit for the `:task`, `:thread`,
and `:fiber` strategies while true parallelism can be achieved
with the `:fork` and `:ractor` strategies. The
`:fork` strategy also provides a separate process that offers
isolation from its parent.

```ruby
require "llm"

llm   = LLM.deepseek(key: ENV["KEY"])
tools = [FetchNews, FetchStocks, FetchFeeds]
agent = LLM::Agent.new(llm, tools:, concurrency: :fork)
agent.talk "Run the tools in parallel"
```

#### ORM

Because both [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html), and [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
can be serialized to JSON and stored in a simple string, both ActiveRecord
and Sequel support can be implemented within a single column on a single row.

The runtime includes first-class support for both ActiveRecord *and* Sequel, and
for both Rack-based applications *and* Rails-based applications. On databases
where it is supported, such as PostgreSQL, the column can be optimized by using
the `jsonb` type.

```ruby
require "active_record"
require "llm"
require "llm/active_record"

class Agent < ApplicationRecord
  acts_as_agent do |agent|
    agent.model "deepseek-v4-pro"
    agent.instructions "solve the user's query"
    agent.tools [Research, FinalizeResearch, ActOnResearch]
  end

  private

  # By convention, this method defines the provider for a model.
  # If necessary, it can be renamed with: provider: :your_method.
  def set_provider
    LLM.deepseek(key: ENV["KEY"])
  end

  # By convention, this method returns the context options given
  # to LLM::Context or LLM::Agent.
  def set_context
    {}
  end
end

agent = Agent.create!
agent.talk "perform research"
```

## Resources

If you like what you read so far, check out the [deepdive.md](https://r.uby.dev/llm/deepdive/)
and [API docs](https://r.uby.dev/api-docs/llm.rb) to learn more. Unfortunately it
wasn't possible to cover every feature without the README becoming a small book.
The [r.uby.dev](https://r.uby.dev) homepage also includes more learning material
and resources.

## License

[BSD Zero Clause](https://choosealicense.com/licenses/0bsd/)
<br>
See [LICENSE](./LICENSE)
