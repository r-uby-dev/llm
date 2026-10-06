
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
is raised on every active tool, and a tool that has not started
yet is held rather than dropped: the cancel is delivered inside
the call when it starts, so the tool is entered and its own
`rescue` and
[`LLM::Tool#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#on_interrupt-instance_method)
hook see it.

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

A canceller usually holds the agent, and `interrupt!` is then enough. In
an application it often does not: the agent is built inside the job that
runs the turn and stays a local variable for as long as the turn lasts,
while the side that wants to stop it is a route handler that holds
nothing but the row the conversation is stored in.

So a turn registers itself for as long as it runs, and
[`LLM.interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM.html#interrupt-class_method)
finds one by the agent or by an id: the same question asked with
different things in hand.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["DEEPSEEK_SECRET"])
agent = LLM::Agent.new(llm, name: "robert", path: "agent.json")

Thread.new do
  sleep(2)
  LLM.interrupt(id: agent.id)   # also: LLM.interrupt(agent: agent)
end

begin
  agent.talk "write me a very long poem", stream: $stdout
rescue LLM::Interrupt
  puts "request cancelled!"
end
```

The name is one value and not two. An agent built around a record
answers to the record's id, because that is what a host already has in
hand, and an agent with no record answers to its own. An id is compared
with `==`, so a string, a number, or whatever a host holds that equals
it will do. Passing neither an agent nor an id, or both, is an
`ArgumentError` rather than a guess.

#### Why would I use it?

Cancellation prevents wasted time and tokens when the model goes
off course, the user changes their mind, or a tool hangs. A forked
tool that enters an infinite loop would run forever without it. A turn
that is between two requests is worth cancelling for the same reason:
a rate-limited turn waiting out its backoff is a turn that has not been
stopped until the cancel reaches it, and the request it is waiting to
make is one nobody asked for any more.

It is also worth saying what is unusual about it. The usual shape of a
cancel is a request that is aborted: this one reaches a tool that is
running, and a turn that is between two requests. And a cancel does not
leave a hole: the call it stopped is closed with an in-band return
before the next request goes out, so the conversation the model sees
stays valid and the model is told what happened rather than finding one.

#### Notes

How an interrupt reaches a tool depends on the strategy. The
`:ractor` strategy delivers it through ractor message passing, and
`:fork` via a message over the control channel the `xchan.rb` gem
provides. The `:thread`
strategy raises it on the thread that runs the tool. The `:fiber`
and `:async` strategies ask the fiber scheduler for the raise,
because a scheduled fiber cannot be entered from another thread -
which is also why a tool that never yields is one the raise cannot
reach. The `:sequential` strategy has nothing to raise into: its
tool runs on the caller's own thread, so a cancel tells the tool
through its hook alone.

Where the hook runs against the raise is the one thing a tool can
feel twice. On `:fork` and `:ractor` the hook is written before the
raise, so a tool that releases a resource in the hook has released it
by the time the interrupt arrives. On `:thread`, `:fiber` and `:async`
it runs in the call's `ensure`, after the raise has landed and after
the tool's own `rescue` - so a tool that cleans up in both places
cleans up twice, rescue first, and one that cleans up in one place
should pick the hook.

A cancel is delivered at the point the turn has reached, which can be
any point of it: inside a stream callback, a compactor, a transformer,
a guard, or the persistence write a step makes.
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
sits outside `StandardError`, so neither a bare `rescue` nor a
`rescue => ex` catches it, and the language is what keeps a cancel from
being eaten rather than a convention every rescue has to remember. Code
that handles a cancel names `LLM::Interrupt`, the way the example above
does; it is not an `LLM::Error` either, so a rescue of the runtime's
error superclass does not catch it.

The runtime's own path out of a turn does not swallow an interrupt:
[`LLM::Context#try`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#try)
re-raises anything that is not a retryable failure, and the tracer
interface has no broad rescues of its own.

The names are worth separating.
[`LLM::Context#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#interrupt!-instance_method)
and
[`LLM::Function#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#interrupt!-instance_method)
are each aliased to `cancel!`, so `cancel!` ends what is in flight and
tells a tool, and the two spellings are the same call.
[`LLM::Function#cancel`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#cancel-instance_method)
is something else: it answers a call that has not run with a cancelled
return and marks it cancelled, which is how a caller declines a pending
tool rather than interrupting one. A tool hears about an interrupt
through
[`LLM::Tool#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#on_interrupt-instance_method),
or
[`LLM::Tool#on_cancel`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#on_cancel-instance_method),
which takes precedence when both are defined.

[`LLM.interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM.html#interrupt-class_method)
answers `false` when nothing was registered under the name it was given,
and that is the ordinary race rather than a failure: a turn that ended
between the lookup and the raise, or a cancel that arrived after it.
The registry is one process and holds the agents that process is
running, so a cancel that lands in a second worker, or in a process a
deploy has not finished replacing, finds nothing there - and `false`
must not be read as "the turn is over". An application that needs more
than the fast path keeps a registry of its own, and one that runs a loop
of its own can record a caller the same way:
[`LLM::Agent::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent/Interrupt.html)
is public for that reason, and what it does with the names is the
caller's business.
