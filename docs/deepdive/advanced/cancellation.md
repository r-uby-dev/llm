
## Cancellation

### Introduction

#### Overview

Cancellation lets you abort a model request mid-stream, interrupt any
tools that are currently executing, and end a turn that is between the
two. The user changes their mind. The model goes off course. A tool
hangs. In all three cases, cancellation stops the work and reclaims
the tokens.

#### How it works

When you want to cancel an active request, tool call, or turn, call
[`LLM::Agent#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#interrupt!)
or
[`LLM::Context#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#interrupt!)
from any thread. Three things happen, and the last of them is what
reaches a turn that is doing nothing in particular:

[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
is raised on the thread where
[`LLM::Agent#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#talk)
or
[`LLM::Context#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#talk)
is running, so the caller
can rescue it and know the request was cancelled.

At the same time,
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
is raised on every active tool.
A tool running in a thread gets it on that thread. A tool in a
fiber gets it on that fiber. A tool in a forked process gets it
via a message over the control channel. Pending tools (not yet
started) are cancelled through
[`LLM::Function#cancel`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#cancel)
without ever being executed.

The transport layer also cancels the in-flight HTTP request.

And when the turn is between two requests - waiting out a retry,
handing tool returns back to the model, or building the next request -
there is nothing in flight to close and nothing running to raise into,
so the interrupt is raised into the frame the turn is running in.
[`LLM::Agent#run_loop`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#run_loop)
records that frame for as long as the turn lasts: the thread when the
canceller is another thread, and the fiber when the canceller shares the
turn's thread. That second case is a fiber scheduler - a turn under
Falcon or Async runs on a fiber of the reactor's thread, and a cancel
that arrives on that thread is another fiber asking.

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

#### Why would I use it?

Cancellation prevents wasted time and tokens when the model goes
off course, the user changes their mind, or a tool hangs. A forked
tool that enters an infinite loop would run forever without it. A turn
that is between two requests is worth cancelling for the same reason:
a rate-limited turn waiting out its backoff is a turn that has not been
stopped until the cancel reaches it, and the request it is waiting to
make is one nobody asked for any more.

#### Notes

The `:ractor` strategy delivers the interrupt through ractor
message passing. The `:fork` strategy delivers it via a message
over the xchan control channel. All other strategies raise the
exception directly on the executing thread or fiber.

A cancel is delivered at the point the turn has reached, which can be
any point of it: inside a stream callback, a compactor, a transformer,
a guard, or the persistence write a step makes.
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
is a `StandardError`, so a `rescue` that names no class catches it too.
Code that has to see the end of a turn should re-raise what it does not
recognize rather than absorb it.

The runtime's own path out of a turn does not swallow an interrupt:
[`LLM::Context#try`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#try)
re-raises anything that is not a retryable failure, and the tracer
interface has no broad rescues of its own.
