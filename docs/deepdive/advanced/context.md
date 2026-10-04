
## Context

### Introduction

#### Overview

[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
is the runtime that powers every agent. When you call
[`LLM::Agent#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#talk),
the agent delegates to its internal context. The context manages
the message history, sends requests to the provider, tracks pending
tool calls, and feeds results back to the model. Everything an agent
does, a context does too, but without the automatic tool loop.

Using a context directly gives you finer control over each step
of the conversation. You decide when to send messages, when to
execute tools, and when to stop. This is useful for custom
confirmation flows, mixed concurrency strategies per tool, or
any workflow where the agent's automatic loop gets in the way.

#### How it works

A context wraps a provider and maintains the conversation state.
Call
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk)
to send input to the model, check
[`LLM::Context#pending_functions?`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#pending_functions?)
to see if tools were requested, and use
[`LLM::Context#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#wait)
to execute them. Each call to
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk)
appends
to the conversation and returns the model's response. The context
serializes its state with
[`LLM::Context#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#to_h)
and
[`LLM::Context#to_json`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#to_json),
and restores it
with
[`LLM::Context#restore`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#restore).
This is how the ORM integrations and filesystem
persistence work under the hood:

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
ctx = LLM::Context.new(llm)

res = ctx.talk "What's the weather in Tokyo?"
puts res.content
```

#### Why would I use it?

A bare context gives you control that the agent
abstraction does not expose. Pre-flight checks on tool requests,
per-tool confirmation prompts, mixed concurrency strategies across
tools, or manual iteration until a condition is met are all easier
with a bare context.

#### Notes

The agent uses
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
internally. Anything you can do with
a context, you can also do through an agent. The trade-off is
convenience versus control. Contexts support the same concurrency
strategies, compaction, cancellation, and serialization as agents.

OpenAI contexts default to the Responses API (`mode: :responses`)
with `store: false`, so no conversation state is kept server-side.
Pass `mode: :completions` to use the legacy Chat Completions API
instead. Every other provider defaults to `mode: :completions`.

A raw context disables retries by default (`retry_budget: 0`).
Pass `retry_budget:` to retry a request that was rate limited
(`LLM::RateLimitError`) or timed out (`Timeout::Error`, covering
`Net::OpenTimeout` and `Net::ReadTimeout`), up to that many times.
Each retry sleeps a growing interval (2s, 4s, 6s, ...) and notifies
the stream through
[`LLM::Stream#on_retry`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_retry-instance_method)
before trying again. The budget lives on the provider, where it
defaults to 5 (8 on Alibaba, which rate limits more often), and an
agent that sets none of its own takes the provider's, so most users
never touch this directly.

### Identity

#### Overview

A context has an id and a creation time, and so does each message it
holds. The id is a UUIDv7 string, a UUID version that encodes its own
creation timestamp, so an id sorts by the order it was created and
carries the time it was made.

#### How it works

Read the id and creation time from a context, an agent, or a message:

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
ctx = LLM::Context.new(llm)
ctx.talk "Hello"
ctx.id          # => "01932f5a-..." (UUIDv7)
ctx.created_at  # => 2026-09-11 04:21:07 UTC
ctx.messages.first.id
```

[`LLM::Agent#id`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#id-instance_method)
and
[`LLM::Agent#created_at`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#created_at-instance_method)
delegate to the context the agent wraps.
[`LLM::Context#created_at`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#created_at-instance_method)
and
[`LLM::Message#created_at`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#created_at-instance_method)
are read from the id rather than stored, so they return `nil` when
the id is not a UUIDv7 string.

A context bound to a record takes that record's id when the record's
id is a UUIDv7 string, and generates one otherwise - so an agent's
id is the identity its host already has, and a record with an
integer primary key, or a row that is not saved yet, still gets a
UUIDv7 of its own. Pass `id:` to name a context yourself: the value
is used as given, and is not required to be a UUIDv7.

#### Why would I use it?

An id gives a conversation or a message a stable name you can log,
correlate, or look up. Because the id is a UUIDv7, the same value
also answers when the object was created, so sorting ids sorts by
creation order and no separate timestamp column is needed.

#### Notes

The id is generated once and saved with the runtime state, so it
survives a save and a restore. A payload written before ids existed
has none, so its object is restored with a fresh id.
A UUIDv7 is recommended for a record's id, though it is not required:
it is what lets the same string name a row and the conversation bound
to it, and what makes `created_at` answerable. An id that is not a
UUIDv7 is stored and restored as given, and only `created_at` answers
`nil` for it.
[`LLM::Message#==`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#==-instance_method)
ignores the id, so a difference in creation time alone does not make
two messages unequal.
[`LLM::Utils.timestamp`](https://r.uby.dev/api-docs/llm.rb/LLM/Utils.html#timestamp-instance_method)
is the shared method that decodes a UUIDv7 timestamp.

### Manual loop

#### Overview

[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
manages the tool loop automatically. It calls
the model, checks for tool requests, runs the tools, feeds results
back, and repeats until the model produces text. You can bypass
this and drive
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
directly instead. This
gives you finer control over each step of the loop at the cost of
more code.

#### How it works

When you want to control the tool loop yourself, drive
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
directly instead of using an agent. Start a conversation, check
for tool requests, execute them, and feed results back. The full
loop is under your control. Each call to
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk)
appends to the conversation and returns the model's response, and
[`LLM::Context#pending_functions?`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#pending_functions?)
tells you whether tools were requested.
From that foundation you can inspect, iterate, or confirm
per-tool in a single flow:

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
ctx = LLM::Context.new(llm)

loop do
  res = ctx.talk("What's the weather in Tokyo?")
  break unless ctx.pending_functions?

  puts "Model requested #{ctx.pending_functions.size} tool(s)"

  results = ctx.pending_functions.map do |fn|
    print "Run #{fn.name} with #{fn.arguments}? [y/N] "
    if $stdin.gets&.match?(/\Ay\z/i)
      fn.task(:thread).wait
    else
      fn.cancel(reason: "user declined")
    end
  end

  ctx.talk(results)
end

puts res.content
```

#### Why would I use it?

Manual control gives you pre-execution checks, custom confirmation
flows, different strategies per tool, and fine-grained error
recovery that the default tool loop does not expose.

#### Notes

[`LLM::Context#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#wait)
picks up pending functions, spawns them using the chosen
strategy, waits for results, and records them back in the context.
Each strategy is supported: `:sequential`, `:thread`, `:fiber`,
`:async`, `:fork`, and `:ractor`. Functions are reset after each
[`LLM::Context#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#wait)
or
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk)
call. Store the array if you need to
preserve them.

### Pending functions

#### Overview

Pending function calls represent the model's tool requests. After
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk)
returns, the context may have pending function
calls if the model requested tools. These are available through
[`LLM::Context#pending_functions`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#pending_functions)
which returns an array of
[`LLM::Function`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html)
objects. Each function has a name, arguments, and methods for
execution or cancellation.

#### How it works

When you want to check whether the model requested tools, call
[`LLM::Context#pending_functions?`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#pending_functions?)
after each
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk)
call. Each pending
function has a name, arguments, and
methods for execution or cancellation. Call
[`LLM::Function#task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#task)
to execute it or
[`LLM::Function#cancel`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#cancel)
to skip it. Iterate over all
pending functions to inspect or handle them individually:

```ruby
res = ctx.talk "What's the weather in Tokyo?"

if ctx.pending_functions?
  puts "Model requested #{ctx.pending_functions.size} tool(s)"
  results = ctx.pending_functions.map do |fn|
    print "Run #{fn.name} with #{fn.arguments}? [y/N] "
    if $stdin.gets&.match?(/\Ay\z/i)
      fn.task(:thread).wait
    else
      fn.cancel(reason: "user declined")
    end
  end
  ctx.talk(results)
end
```

#### Why would I use it?

Inspecting pending functions lets you decide which tools to run,
in what order, and with what strategy. This is essential for
confirmation flows, selective execution, or logging which tools
the model requested.

#### Notes

Pending functions are reset after each
[`LLM::Context#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#wait)
or
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk)
call. If you need to preserve them, store the array before
executing. Functions that are cancelled still count as completed
from the model's perspective; the model sees a cancellation
result, not a tool error.

### Tool responses

#### Overview

A tool interrupt gives you two choices. When a tool receives
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html),
it can either cancel the turn or return a result. The choice
depends on the situation.
A hard cancel aborts the request outright and is the default.
Returning a value lets the model adapt and continue the
conversation, which can be useful when the interrupt is
temporary, like a timeout or a user pause.

#### How it works

When a tool receives
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html),
re-raise to abort the turn or return a value to continue the loop.
The model receives the result and decides what to do next.

Re-raise to abort the turn entirely:

```ruby
class MyTool < LLM::Tool
  def call
    # do work
  rescue LLM::Interrupt
    cleanup
    raise
  end
end
```

Return a value to continue the loop:

```ruby
class MyTool < LLM::Tool
  def call
    # do work
  rescue LLM::Interrupt
    cleanup
    {ok: false, reason: "interrupted"}
  end
end
```

#### Why would I use it?

A hard cancel aborts the request outright. Useful when continuing
would produce garbage. Returning a value lets the model adapt,
which can be helpful when the interrupt is temporary.

#### Notes

The mechanism is the same across all six concurrency strategies.
The `:ractor` strategy delivers the interrupt through ractor
message passing. The `:fork` strategy delivers it over the control
channel the `xchan.rb` gem provides.

### Messages

#### Overview

[`LLM::Context#messages`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#messages-instance_method)
returns an
[`LLM::Buffer`](https://r.uby.dev/api-docs/llm.rb/LLM/Buffer.html),
an ordered, array-like collection of the conversation's
[`LLM::Message`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html)
objects. Read it to inspect or filter a conversation, and edit it to
shape what the model sees next.

#### How it works

A buffer is `Enumerable`, so it supports `each`, `find`, `map`,
`select`, and the rest. It also offers the array methods a long
conversation needs, including `first`, `last`, `take`, `drop`,
`shift`, `pop`, `slice!`, `select!`, `reject!`, and `clear`:

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
ctx = LLM::Context.new(llm)
ctx.talk "Hello"

ctx.messages.size       # => 2
ctx.messages.first      # => the user message
ctx.messages.last       # => the assistant message
ctx.messages.each { |m| puts "#{m.role}: #{m.content}" }
```

Because a message carries its own role, filtering by role is a normal
`select`:

```ruby
ctx.messages.select(&:assistant?)
```

#### Why would I use it?

Reading the buffer gives you the conversation as data, so you can log
it, count tokens against it, or render it in your own UI. Editing the
buffer lets you drop or keep specific messages without rebuilding the
conversation.

#### Notes

Changing the buffer changes the next request, so edits are best made
between turns. The compaction topic covers the built-in, bounded way
to trim a long conversation.

### Prompt

#### Overview

[`LLM::Prompt`](https://r.uby.dev/api-docs/llm.rb/LLM/Prompt.html)
composes a single request from several role-aware messages. A prompt
is not just a string: it is an ordered list of messages with explicit
roles, so one turn can carry a system message, a user message, and
anything else the model supports.

#### How it works

Call
[`LLM::Context#prompt`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#prompt-instance_method)
with a block, then pass the result to
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk).
Inside the block, `system`, `user`, and `developer` append a message
with the matching role, and `talk` appends one with an explicit
role. The provider resolves each role to its provider-specific name:

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
ctx = LLM::Context.new(llm)

prompt = ctx.prompt do
  system "Your task is to assist the user"
  user "Hello. Can you assist me?"
end

res = ctx.talk(prompt)
```

The block receives the prompt object when it takes an argument, and
otherwise runs in the prompt's context:
[`LLM::Prompt#to_a`](https://r.uby.dev/api-docs/llm.rb/LLM/Prompt.html#to_a)
returns the messages in order, and two prompts are equal when their
messages match. Each of `system`, `user`, `developer`, and `talk`
accepts an `extra:` hash, which is attached to the message it builds,
so a caller can carry a field of its own alongside the content.

#### Why would I use it?

A prompt keeps the roles of a multi-part request explicit, and it is
an object you can build, pass around, and compare before it is sent.
Use it when a turn needs more than one role, or when the same prompt
is composed in more than one place.

#### Notes

[`LLM::Agent#prompt`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#prompt-instance_method)
delegates to the context it wraps, so an agent accepts a prompt
wherever it accepts a string. `LLM::Context#build_prompt` is an alias
kept for compatibility.

### Attachments

#### Overview

A message can carry files alongside its text. Pass file paths with the
`with:` option of
[`LLM::Context#ask`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#ask-instance_method),
or tag a value explicitly with
[`LLM::Context#local_file`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#local_file-instance_method),
[`LLM::Context#image_url`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#image_url-instance_method),
or
[`LLM::Context#remote_file`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#remote_file-instance_method).

#### How it works

`ask` is a shorthand for a turn that returns a response. Pass the
prompt and, optionally, files to attach with `with:`. It also accepts
a `stream:` target or a block for streaming:

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
ctx = LLM::Context.new(llm)

res = ctx.ask "What is in this photo?", with: "photo.jpg"
res = ctx.ask "Summarize these", with: ["one.pdf", "two.pdf"]
```

The three helpers tag a value so the runtime knows how to send it, for
turns built with `talk`:

```ruby
ctx.talk ["Describe this", ctx.local_file("/images/photo.png")]
ctx.talk ["Describe this", ctx.image_url("https://example.com/photo.png")]
ctx.talk ["Describe this", ctx.remote_file(res)]
```

`local_file` reads a path from disk, `image_url` passes a URL the
provider fetches, and `remote_file` reuses a file a previous response
produced.

#### Why would I use it?

Attachments let one turn carry an image, a PDF, or another file for the
model to read, instead of pasting its contents into the prompt.

#### Notes

Which files a model accepts depends on the provider and the model.
`ask` is a shorthand over `talk`: it builds the same prompt and returns
the same `LLM::Response`, so anything that works with `talk` works with
`ask`. An agent delegates all four methods to the context it wraps.

