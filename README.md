It is possible to interrupt a running request, a running tool call, or a
turn that is between two of them, with
[`LLM::Agent#interrupt!`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#interrupt!)
(or `cancel!`). The third one is the shape llm.rb gives cancellation that a
read of the usual abort would miss: a turn waiting out a retry, handing tool
returns back to the model, or building its next request is a turn that has
not stopped until the cancel reaches it - and this one does.

A tool is interrupted where it stands rather than at its next opportunity to
notice: its own `rescue` runs, and `#on_interrupt` is called even where a
raise cannot reach the tool. Nothing is left half-answered either, because a
cancelled call is closed with an in-band return before the next request goes
out, so the conversation the model sees stays valid and the model is told
what happened rather than finding a hole. And a cancel is not an error:
[`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
sits outside `StandardError`, so a bare `rescue` passes one through. The
[cancellation chapter](docs/deepdive/advanced/cancellation.md) has the
details, including the strategies whose shape differs.

```ruby
class Search < LLM::Tool
  name "search"
  description "Search many files"
  parameter :pattern, String, "The pattern to search for"
  required %i[pattern]

  ##
  # A raise is delivered here; `on_interrupt` is a notification, and it
  # runs on every strategy - `:sequential` included.
  def call(pattern:)
    search(pattern)
  rescue LLM::Interrupt
    ##
    # A tool can return a value from here, and the turn carries on with
    # it, or re-raise and the fiber that made the request is raised
    # into as well.
    cleanup
    raise
  end

  ##
  # Told on the thread or fiber the call runs on, before the raise on
  # `:fork` and `:ractor` and after the rescue above on the other three.
  def on_interrupt
    cleanup
  end

  private

  def cleanup
    # Release a file, a socket, or a lock here.
  end
end

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, tools: [Search], concurrency: :async)
Thread.new { sleep(1); agent.interrupt! }

begin
  agent.talk "find every TODO in the repository", stream: $stdout
rescue LLM::Interrupt
  puts "cancelled"
end
```
