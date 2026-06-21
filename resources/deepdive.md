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

## Intro

This guide is a practical walkthrough of [llm.rb](https://github.com/r-uby-dev/llm.rb#readme) —
Ruby's capable AI runtime.

llm.rb runs on Ruby's standard library by default and loads optional pieces
only when needed. You can start with a provider and a single context, then add
agents, tools, streaming, persistence, embeddings, and protocol clients
without changing the shape of your code.

It supports OpenAI, OpenAI-compatible endpoints, Anthropic, Google Gemini,
DeepSeek, xAI, Z.ai, AWS Bedrock, Ollama, and llama.cpp. ActiveRecord and
Sequel support are built in, along with concurrent tool execution through
threads, tasks, fibers, ractors, and fork.

## Install

```bash
gem install llm.rb
```

## Quick Start

#### Agent

[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html) is the
recommended starting point.
<br>
It manages tool execution for you and keeps conversation state across turns.

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
agent.talk "Hello world"
```

#### REPL

A read-eval-print loop is the simplest way to interact with an agent.
<br>
The loop reads input, sends it to the model, and prints the response as it
arrives:

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

#### Context

[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html) is the
lower-level runtime object.
<br>
It holds the same conversation state but leaves tool execution up to you.
Use it when you want to decide when and how tools run.

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
ctx = LLM::Context.new(llm, stream: $stdout)
ctx.talk "Hello world"
```

With tools, the manual loop is explicit:

```ruby
ctx = LLM::Context.new(llm, tools: [ReadFile])
ctx.talk("Read README.md and summarize it.")
ctx.talk(ctx.wait(:call)) while ctx.functions?
```

For ordinary application code, prefer
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).
It does the same thing but manages the loop for you.

## Tools

#### Definition

Tools extend what the model can do.
<br>
They are plain Ruby classes with typed parameters. Define one, attach it to
an agent, and the model can call it when it makes sense.

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

Attach the tool to an agent:

```ruby
agent = LLM::Agent.new(llm, stream: $stdout, tools: [ReadFile])
agent.talk "Read README.md and summarize the project."
```

[`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html) handles the
Ruby-side definition. llm.rb adapts the tool schema to the provider at request
time.

#### Concurrency

When an agent calls several tools at once, you can run them in parallel.
<br>
This cuts down waiting time when tools do independent work like reading
files or calling APIs.

```ruby
class Agent < LLM::Agent
  model "gpt-5.4-mini"
  tools ReadFile
  concurrency :thread
end

llm = LLM.openai(key: ENV["KEY"])
agent = Agent.new(llm, stream: $stdout)
agent.talk "Read README.md and CHANGELOG.md and compare them."
```

## Structured Output

#### Schema

When you need JSON with a known shape, use
[`LLM::Schema`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html).
<br>
The model will return data that matches your schema instead of free text.

```ruby
class Report < LLM::Schema
  property :category, Enum["performance", "security", "outage"]
  property :summary, String, "Short summary"
  property :services, Array[String], "Impacted services"
  required %i[category summary services]
end

agent = LLM::Agent.new(llm, schema: Report)
res = agent.talk("Classify: 'API latency spiked for the billing service.'")
puts res.content!
```

For one-off schemas, build the shape inline:

```ruby
schema = LLM::Schema.new.object(
  category: LLM::Schema.new.string.enum("bug", "feature").required,
  summary: LLM::Schema.new.string.required
)

agent = LLM::Agent.new(llm, schema:)
res = agent.talk("Classify: add a dark mode toggle.")
puts res.content
```

## Streaming

#### Stream

Streaming works with any object that responds to `#<<`, like `$stdout`.
<br>
For more control, subclass
[`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html) and
override its callbacks:

```ruby
class MyStream < LLM::Stream
  def on_content(content)
    print content
  end

  def on_reasoning_content(content)
    warn content
  end
end

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: MyStream.new)
agent.talk "Explain Ruby fibers."
```

## Skills

#### Release

Skills package repeatable instructions and scoped tool access into
`SKILL.md` directories.
<br>
They turn common workflows into named capabilities that agents can load
on demand.

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
class ReleaseAgent < LLM::Agent
  model "gpt-5.4-mini"
  skills "./skills/release"
end

llm = LLM.openai(key: ENV["KEY"])
ReleaseAgent.new(llm, stream: $stdout).talk("Prepare the next release.")
```

When a skill runs, llm.rb starts a subagent with the skill's instructions,
its allowed tools, and recent conversation context. Skills can also use
`tools: inherit` to run with the parent agent's full toolset.

## MCP

#### Stdio

[`LLM::MCP`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html) lets llm.rb use
tools provided by local stdio servers or remote HTTP servers.
<br>
This is how you connect your agent to GitHub, databases, or anything else
that speaks the Model Context Protocol.

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
mcp = LLM::MCP.stdio(argv: ["ruby", "server.rb"])

mcp.session do
  agent = LLM::Agent.new(llm, stream: $stdout, tools: mcp.tools)
  agent.talk "Use the available tools to inspect the environment."
end
```

#### Remote

For HTTP MCP servers, use persistent connections when you make repeated
tool calls:

```ruby
mcp = LLM::MCP.http(
  url: "https://remote-mcp.example.com",
  transport: :net_http_persistent
)

agent = LLM::Agent.new(llm, stream: $stdout, tools: mcp.tools)
agent.talk "Use the remote tools to inspect the repository."
```

## Persistence

#### Overview

Agents and contexts serialize to JSON and restore later.
<br>
The same serialized state powers the ActiveRecord and Sequel integrations.

#### Filesystem

Persist agent state to a JSON file on disk.

```ruby
require "llm"

llm = LLM.openai(key: ENV["KEY"])
agent = LLM::Agent.new(llm)
agent.talk "Remember that my favorite language is Ruby"

# Save
File.write("agent.json", agent.to_json)

# Restore later
agent2 = LLM::Agent.new(llm, stream: $stdout)
agent2.restore(path: "agent.json")
agent2.talk "What is my favorite language?"
```

#### ActiveRecord

[`acts_as_agent`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/ActsAsAgent.html)
wraps an agent directly on an ActiveRecord model.
<br>
Serialized state lives in a single `data` column while your application
controls provider, model, and tool configuration.

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
    {mode: :responses, store: false}
  end
end

ticket = Ticket.create!
puts ticket.talk("How do I rotate my API key?").content
```

If you need manual control over tool execution, use
[`acts_as_llm`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/ActsAsLLM.html)
instead. It wraps
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html) with the
same persistence contract.

## Embeddings

#### Vector

Embeddings turn text into vectors. Call `.embed` on any provider that supports
it. The returned vectors can be stored in a vector-aware database (PostgreSQL
with pgvector, SQLite with `vec0`, or a dedicated vector database) and
compared by semantic similarity.

```ruby
llm = LLM.openai(key: ENV["KEY"])
res = llm.embed("llm.rb manages providers, agents, tools, and state")
puts res.model
puts res.embeddings.first.size
```

Embed multiple texts at once:

```ruby
chunks = [
  "LLM::Agent manages the tool loop automatically.",
  "LLM::Context exposes the low-level tool loop.",
  "MCP tools can be passed to agents as local tools."
]

res = llm.embed(chunks)
res.embeddings.each_with_index { |vec, i| puts "Vector #{i}: #{vec.size} dimensions" }
```

## Multimodal

#### Image

Prompts can be strings, arrays, or
[`LLM::Prompt`](https://r.uby.dev/api-docs/llm.rb/LLM/Prompt.html) objects.
<br>
Arrays let you mix text with images and other content.

```ruby
agent = LLM::Agent.new(llm)
agent.talk [
  "Describe this image",
  agent.image_url("https://example.com/image.png")
]
```

Attach local files directly with
[`LLM::Agent#ask`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#ask-instance_method):

```ruby
agent = LLM::Agent.new(llm)
puts agent.ask("Summarize this document.", with: "README.md").content
```

## Tracing

#### Logger

Attach a tracer at the provider level to log requests and tool calls:

```ruby
llm.tracer = LLM::Tracer::Logger.new(llm, io: $stdout)
agent = LLM::Agent.new(llm)
agent.talk("Hello")
```

## Applications

#### SSH

The llm.rb runtime powers small terminal applications that you can try over
SSH right now.

| Application | Try it | Runtime |
|---|---|---|
| [matz](https://r.uby.dev/matz/) | `ssh matz@r.uby.dev` | [mruby-llm](https://r.uby.dev/mruby-llm/) |
| [robert](https://4.4bsd.dev/robert) | `ssh robert@4.4bsd.dev` | [mruby-llm](https://r.uby.dev/mruby-llm/) |
