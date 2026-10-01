
## Cancellation

### Introduction

#### Overview

Cancellation lets you abort a model request mid-stream and interrupt
any tools that are currently executing. The user changes their mind.
The model goes off course. A tool hangs. In all three cases,
cancellation stops the work and reclaims the tokens.

#### How it works

When you want to cancel an active request or tool call, call
[`LLM::Agent#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#interrupt!)
or
[`LLM::Context#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#interrupt!)
from any thread. Two things
happen at once:

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
via a message over the control channel.

A tool that has not started yet is not forgotten. On `:thread`
and `:fiber` the cancel is held on the task and spent as the
tool's body begins, so the tool's
[`on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#on_interrupt-instance_method)
hook runs and the caller sees
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
rather than a call that ran to completion. The other strategies
answer it their own way: `:async` raises before the call is
entered, `:fork` and `:ractor` deliver it as a message, and
`:sequential` runs no call at all, so the hook is its only
notification.

The transport layer also cancels the in-flight HTTP request.

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
tool that enters an infinite loop would run forever without it.

#### Notes

The `:ractor` strategy delivers the interrupt through ractor
message passing. The `:fork` strategy delivers it via a message
over the xchan control channel. All other strategies raise the
exception directly on the executing thread or fiber - except
`:fiber`, which asks the scheduler to deliver it when the
scheduler provides the hook for it, as `Async` does.
