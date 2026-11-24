> Changelog <br>
> [r.uby.dev](https://r.uby.dev) project

This file covers the v22 series. <br> 
Older releases:  
* [changelog/v21.md](changelog/v21.md)
* [changelog/v20.md](changelog/v20.md)
* [changelog/v19.md](changelog/v19.md)
* [changelog/v18.md](changelog/v18.md)
* [changelog/v17.md](changelog/v17.md)
* [changelog/v16.md](changelog/v16.md)
* [changelog/v15.md](changelog/v15.md)
* [changelog/v14.md](changelog/v14.md)
* [changelog/v13.md](changelog/v13.md)
* [changelog/v12.md](changelog/v12.md)

## What's next

*No unreleased changes yet. Check back after the next release.*

## v22.0.0

Changes since `v21.1.0`.

This is a major release, and only because of one rename: `Model.agent` is
`Model.__agent__` now, on both the ActiveRecord and Sequel plugins, since
`agent` is a name an application may define for itself. The rest is small.
The git tools take a per-call `max_bytes`, the console drains its stream in
one go so the status line no longer outlives the turn, the MCP HTTP
transport asks for JSON and an event stream, keeps the session id a server
returns, and raises the reason a server gives, and a scoped header or
tracer is keyed by the request owner rather than the fiber.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `Model.agent`, on a model that `acts_as_agent` or `plugin :agent` | `Model.__agent__` |

### LLM::Tool

* **tools: the git tools take a `max_bytes`** <br>
  Each tool that
  [`LLM::Tool::Git`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git.html)
  provides declares a `max_bytes` parameter now, so a model that needs less of a
  `git-log` or a `git-diff` asks for it on the call instead of taking what the
  class was configured to return. The parameter defaults to the tool's own
  `max_bytes`, so a call that passes none is capped as it was, and the number
  reaches
  [`LLM::Tool::Utils::Process#exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils/Process.html#exec-instance_method)
  per call rather than from the class alone.

### ORM

* **orm: `Model.agent` is `Model.__agent__`** <br>
  [`LLM::ActiveRecord::ActsAsAgent::ClassMethods#__agent__`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/ActsAsAgent/ClassMethods.html#__agent__-instance_method)
  returns the agent class a model wraps, and the Sequel plugin has the same
  method as
  [`LLM::Sequel::Agent::ClassMethods#__agent__`](https://r.uby.dev/api-docs/llm.rb/LLM/Sequel/Agent/ClassMethods.html#__agent__-instance_method).
  The name was `agent`, which is what an application is likely to define for
  itself, so a model with a column, an association or a method of that name
  shadowed the wrapper and lost the agent class with it. The old name is not
  an alias, so `Model.agent` has to be renamed where it is called.
  `Model.set` bulk-assigns the class-level defaults as it did, and the block
  that `acts_as_agent` or `plugin :agent` is given still runs against the
  agent class this method returns.

### Console

* **console: the status line no longer outlives the turn** <br>
  [`LLM::Console`](https://r.uby.dev/api-docs/llm.rb/LLM/Console.html) drains
  the queue its stream is written to in one go, where it drained four
  messages per pass, and it sets the status line from a terminal message
  before it paints the stream that preceded it. A fast model queued more
  chunks than four, so the turn ended with chunks still queued and the status
  line sat on the "Thinking" text until the backlog had been painted - ten
  seconds or more after the turn had ended. A run of chunks is painted once
  now, with the last of the run, because a chunk holds the whole message so
  far rather than a delta.

### LLM::MCP

* **mcp: the HTTP transport asks for JSON and an event stream** <br>
  [`LLM::MCP::Transport::HTTP`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP/Transport/HTTP.html)
  sends `Accept: application/json, text/event-stream` with every request, where
  it left the header to the caller. The MCP spec asks for both media types,
  because a server may return one JSON document or a stream of server-sent
  events, and a server that enforces the header rejected a request that came
  without it. A header that is passed in `headers:` is merged over the default,
  so a caller that wants another value still sets it.

* **mcp: the HTTP transport keeps the session id a server returns** <br>
  [`LLM::MCP::Transport::HTTP#write`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP/Transport/HTTP.html#write-instance_method)
  remembers the `mcp-session-id` a response carries and sends it with every
  request after that, which is how a server that keeps state per session follows
  one transport through the requests it makes. A response that carries no id
  leaves the id that is held alone, so a transport that was given no session
  sends none.

* **mcp: a failed write raises the reason the server gives** <br>
  [`LLM::MCP::Transport::HTTP#write`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP/Transport/HTTP.html#write-instance_method)
  reads the body of a response that is not a success and appends it to the
  [`LLM::MCP::Error`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#Error-constant)
  it raises, so the reason a server gives - a method it does not know, a
  parameter it rejects - reaches the caller, where the error named the status
  code alone. An empty body leaves the message as it was.

### LLM::Provider

* **provider: a scoped header or tracer is keyed by the request owner** <br>
  [`LLM::Provider#with`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#with-instance_method)
  and
  [`LLM::Provider#with_tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#with_tracer-instance_method)
  keep what they scope in a map that belongs to the current request owner, and
  that map is held by the thread rather than by the fiber. The request owner is
  the async task when there is one and the fiber otherwise, so a request that is
  resumed on another fiber of the scheduler keeps the header and the tracer its
  scope set, where the scope went with the fiber it was opened on. The map is
  keyed by the owner before the provider, so two owners that are active at once
  on one thread do not overwrite each other's scope, and a scope restores only
  the entry its own owner opened. Separate threads stay apart as they did.
