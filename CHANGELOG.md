> Changelog <br>
> [r.uby.dev](https://r.uby.dev) project

This file covers the upcoming v18 series, and
the previous v17 and v16 series. <br> Older releases (v15 and
before) can be seen in [changelog/old.md](changelog/old.md).

## What's next

### Breaking

#### Migration

| Old | New |
|-----|-----|
| Ruby 3.4 or later | Ruby 4.0 or later |
| `LLM.json = :yajl` | `LLM.json = :json` |
| `LLM::Tool::Utils::Process#wait` raises on a timeout | it throws `:kill` on a timeout |
| `transport: :curb` | `transport: :net_http` or `transport: :net_http_persistent` |
| `LLM::Message#role` returns the provider's spelling, eg `model` | it returns the abstract role, eg `assistant` |
| a saved payload carries `schema_version: 1` and `original_tool_calls` | it carries `schema_version: 2`, and `original_tool_calls` is gone |
| `#deserialize` reads a payload from any version | it refuses a payload from a newer runtime, and one that carries no version |
| `LLM::Function::Ractor::Mailbox`, and `LLM::Function::Ractor::Task#mailbox` | both are removed, and the task implements `#alive?`, `#wait`, and `#interrupt!` |
| `llm.rb` runs tool calls sequentially | it runs them on a Ractor, and `-c` picks the strategy |
| `LLM::Skill`, the `skills:` option, and `on_skill_call` / `on_skill_return` | all are removed |
| `LLM::Tracer#provider_name`, `#provider_host`, and `#provider_port` | the provider implements `#name`, `#host`, and `#port` |
| `LLM::Transformer`, the `transformer:` and `transformer_options:` options, and `on_transform` / `on_transform_finish` | `LLM::MessageFilter`, `filter:` and `filter_options:`, and `on_filter` / `on_filter_finish` |
| `LLM::Context#transformer`, and `LLM::Transformer::Multi#transformers` | `LLM::Context#filter`, and `LLM::MessageFilter::Multi#filters` |
| `LLM::Transport::PersistentHTTP.registry` and `.lock` | each transport keeps a client and a lock of its own |
| `LLM::Tool::Utils#wait`, `#spawn` and `#now`, and `LLM::Tool::Utils::Command` | they are `LLM::Tool::Utils::Process#wait`, `#spawn` and `#now`, and `LLM::Tool::Utils::Process::Command` |
| `LLM::ActiveRecord::Message.for(agent:)` | `LLM::ActiveRecord::Message.for(record:)` |

### Skills

**Skills have been removed.**

A skill was a directory-backed capability that turned itself into a tool
on every call - through `Class.new(LLM::Tool)`, closing over the skill and
the context - and then spawned a subagent per invocation. Anonymous classes
and closures do not survive the `:ractor` strategy, which supports
class-based tools with shareable arguments only, and the feature carried a
second agent lifecycle (nested agents, skill callbacks, inherited tool
lists) that had to be maintained beside the core.

`LLM::Skill`, `LLM::Skill.load`, the `skills:` option on
[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html),
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html) and
[`LLM::Console`](https://r.uby.dev/api-docs/llm.rb/LLM/Console.html),
`on_skill_call` and `on_skill_return` on
[`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html), and
`LLM::Tool#skill?` are gone. Tool calling, the concurrency strategies
and streaming do not depend on any of it. A skill directory can still be
exposed as a tool by subclassing `LLM::Tool` and reading `SKILL.md` from
it.

### Ruby

* **drop Ruby 3.4 support** <br>
  The gem now requires Ruby 4.0 or later, where the v17
  series requires Ruby 3.4 or later. The v18 series
  focuses on Ractor, and it drops the incompatibilities
  between the 3.x and 4.x series: `Ractor#take` is gone
  in Ruby 4.0.0, and `Ractor#value` replaces it in
  llm.rb, though the two are not equivalent.

* **ruby: declare the stdlib gems as runtime dependencies** <br>
  The gemspec declares `net-http` (`~> 0.10`), `json`
  (`~> 3.1`), `securerandom` (`~> 0.4`), `time` (`~> 0.5`),
  `stringio` (`~> 3.2`), `digest` (`~> 3.3`) and `openssl`
  (`~> 4.0`) as runtime dependencies. The v17 series declared
  none, which left each gem implicit, and each one is now
  declared, so a fresh `bundle install` installs it.

### LLM

* **core: add `LLM.debug`** <br>
  [`LLM.debug`](https://r.uby.dev/api-docs/llm.rb/LLM.html#debug-class_method)
  writes a message to `$stderr` that is prefixed
  with the runtime's name and version. This method
  is a noop when
  [`LLM.debug_mode?`](https://r.uby.dev/api-docs/llm.rb/LLM.html#debug_mode?-class_method)
  returns false and debug mode can be toggled through
  the
  [`LLM.debug_mode!`](https://r.uby.dev/api-docs/llm.rb/LLM.html#debug_mode!-class_method)
  method or by setting
  `LLMRB_DEBUG_MODE=1`
  in your shell.
  <br><br>
  It takes an optional `IO` as its second argument, and it writes
  to `$stderr` by default. The default can be replaced with
  [`LLM.debug_io=`](https://r.uby.dev/api-docs/llm.rb/LLM.html#debug_io=-class_method),
  and
  [`LLM.debug_io`](https://r.uby.dev/api-docs/llm.rb/LLM.html#debug_io-class_method)
  returns the IO that is in use, so debug output can be sent
  to a file:

  ```ruby
  LLM.debug_io = File.open("llm.log", "w+")
  LLM.debug_mode!
  ```

* **core: resolve `LLM.json` while `lib/llm.rb` loads** <br>
  The first call to
  [`LLM.json`](https://r.uby.dev/api-docs/llm.rb/LLM.html#json-class_method)
  from a Ractor other than main raised `Ractor::IsolationError`,
  because it set module state from where it was called. The adapter
  is resolved once, on the main Ractor, at load time now, so a tool
  call that runs on a Ractor can read it.

### LLM::Google

* **google: keep a streamed thought signature with its part** <br>
  Gemini can send a `thoughtSignature` in a chunk of its
  own, after the part it belongs to, and the stream parser
  appended it as a part of its own. The response adapter
  reads only parts that hold a `functionCall`, so a streamed
  call lost the signature Gemini requires when it was
  replayed. A signature-only chunk is folded into the part
  before it now, and a signature sent beside other content
  stays where it was sent.

* **google: keep parallel streamed tool calls apart** <br>
  A streamed response can hold more than one
  complete function call (parallel tool calls), and
  the stream parser appended each call to the part
  before it, so an earlier call was overwritten by
  the call that followed and only the last one
  survived. Each complete call is a part of its own
  now, even when it repeats a function name and
  carries no `id`, while a continuation of a partial
  call, and an update that repeats the same `id`,
  are still merged into the part they continue.

### LLM::Context

* **context: store tool calls in the abstract form** <br>
  A tool call is stored as `{id, name, arguments}`, and each
  request adapter builds the blocks its provider expects
  when a request is assembled. A conversation saved under
  one provider restores under another now, including across
  the completions and Responses protocols.

* **context: bump schema_version to 2** <br>
  The
  [`LLM::Context.schema_version`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#schema_version-class_method)
  returns 2 (previously 1), and a payload that was
  written under version 1 is still read. The schema
  changed to store tool calls in the abstract form,
  and the `original_tool_calls` field has been
  dropped from it.

* **context: save token usage with the payload** <br>
  [`LLM::Context#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#to_h-instance_method)
  includes a `token_usage` hash now, so the usage a conversation
  accumulated is saved beside `context_used` and `context_window`.
  It is written for queryability, like the other two, and the
  runtime derives it from the messages when a payload is restored,
  so a payload that carries none still restores.

* **context: add `LLM::Context#compactor_options`** <br>
  [`LLM::Context#compactor_options`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#compactor_options-instance_method)
  returns the options the context's compactor was configured
  with, and `{}` by default.

### LLM::Tool

* **tools: a timed out command doesn't lose its streams** <br>
  The
  [`LLM::Tool::Exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Exec.html)
  tool no longer discards what
  was written to `$stdout` and
  `$stderr` when the tool call
  times out. We also include a
  `note` field that tells the
  model the tool call timed out,
  and that its streams (`$stdout`
  and `$stderr`) are probably
  incomplete.

* **tools: wait throws** <br>
  The
  [`LLM::Tool::Utils::Process#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils/Process.html#wait-instance_method)
  method now uses the `Kernel.throw`
  method instead of `Kernel.raise`
  when a command times out. The
  "wait" method is used internally
  by the
  [`LLM::Tool::Exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Exec.html)
  tool and it can be used by your
  own tools as well. Tools that
  depended on the old behavior
  will require an update (although
  I'd be surprised if any Utils
  method was used directly).

* **tools: fix tools broken under `:ractor` strategy** <br>
  Tools that ship with llm.rb read
  a sentinel constant when an argument
  is omitted (`LLM::Tool::UNDEFINED`)
  and the constant was not Ractor-shareable
  so the tool would fail and report its failure
  back to the model. This also fixes `llm.rb -c ractor`.

* **tool: run MCP tools on a Ractor** <br>
  A tool that
  [`LLM::MCP#tools`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#tools-instance_method)
  builds is Ractor-shareable now, so the `:ractor`
  concurrency strategy can call it. The main Ractor
  keeps the client the tool was built with, and
  another Ractor builds a client of its own from the
  options it was created with. Two transports do not
  work this way: `:net_http_persistent` wraps a
  `Monitor`, which is not Ractor-shareable, and the
  stdio transport cannot start its server from inside
  a Ractor on Windows.

* **tool: run A2A tools on a Ractor** <br>
  A tool that
  [`LLM::Tool.a2a`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#a2a-class_method)
  builds is Ractor-shareable now, so the `:ractor`
  concurrency strategy can call it. The main Ractor
  keeps the client the tool was built with, and
  another Ractor builds a client of its own from
  [`LLM::A2A#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A.html#to_h-instance_method).
  A `transport:` given as an instance cannot be
  rebuilt that way, so pass a Symbol or Class
  shortcut when the tool will run on a ractor.
  `persistent: true` still works, because the pool
  is built inside the Ractor.

* **tool: `params` accepts a hash** <br>
  [`LLM::Tool.params`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#params-class_method)
  and
  [`LLM::Function#params`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#params-instance_method)
  take a hash of JSON Schema now, in addition to the
  block they already took, so a schema that arrives as
  a hash, like the `inputSchema` of an MCP tool, no
  longer has to be wrapped in a block.

* **tools: move process helpers into `LLM::Tool::Utils::Process`** <br>
  The `#wait`, `#spawn` and `#now` methods moved out of
  [`LLM::Tool::Utils`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html)
  and into the new
  [`LLM::Tool::Utils::Process`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils/Process.html)
  module, and `LLM::Tool::Utils::Command` is
  `LLM::Tool::Utils::Process::Command` now. `#wait` still
  throws `:kill` when a command exceeds its timeout, exactly
  as it did in its old home, and `LLM::Tool::Exec` includes
  `Process` now.

* **tools: `LLM::Tool::ReadFile` drops its `test-cmd` dependency** <br>
  [`LLM::Tool::ReadFile`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/ReadFile.html)
  includes `LLM::Tool::Utils` alone now, so the read-file
  tool no longer pulls in `test-cmd` as a transitive
  dependency the way it did when the process helpers
  lived in `Utils`.

### LLM::MCP

* **mcp: add `LLM::MCP#to_h`** <br>
  [`LLM::MCP#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html#to_h-instance_method)
  returns the options a client was created with, which is how an
  MCP tool puts its client back together inside a ractor.

### LLM::A2A

* **a2a: add `LLM::A2A#to_h`** <br>
  [`LLM::A2A#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A.html#to_h-instance_method)
  returns the options a client was created with, which is how
  an A2A tool puts its client back together inside a ractor.

* **a2a: `LLM::A2A.new` takes an `http:` keyword** <br>
  [`LLM::A2A.new`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A.html#initialize-instance_method)
  takes the options that `LLM::A2A#to_h` returns back as
  `http:`, and it builds the transport from them. `transport:`
  is optional now, and one of the two is still required.

### LLM::Message

* **message: `LLM::Message#role` returns a normalized role** <br>
  [`LLM::Message#role`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#role-instance_method)
  returns the abstract role of a message now. A message is
  saved with an abstract role (`assistant` for a model reply,
  `tool` for a tool return) regardless of the
  provider, and each provider or model may have its own terms
  that are different to ours. For example, Google uses the term
  `model` instead of `assistant`. The runtime resolves these
  differences internally.

* **message: add `LLM::Message#returns`** <br>
  [`LLM::Message#returns`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#returns-instance_method)
  returns, as an array, the tool returns a message holds, whether
  the content holds one
  [`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
  or a nested list of them, so a caller no longer has to unwrap
  the content itself. A message that holds no tool return returns
  an empty array, so a filter can iterate over the result instead
  of reproducing the unwrapping:

  ```ruby
  message.returns.each { it.value[:email] = "[EMAIL]" }
  ```

  [`LLM::Message#tool_return?`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#tool_return?-instance_method)
  is built on it now.

* **message: add `LLM::Message#contents`** <br>
  [`LLM::Message#contents`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#contents-instance_method)
  returns the content of a message as a flat array, so a caller can
  iterate over every item without unwrapping the nested lists a
  message can hold. A message that holds no content returns an empty
  array, and
  [`LLM::Message#image_urls`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#image_urls-instance_method)
  and
  [`LLM::Message#files`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#files-instance_method)
  are built on it now.

### LLM::Object

* **object: add `LLM::Object#freeze` and `LLM::Object#frozen?`** <br>
  [`LLM::Object#freeze`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html#freeze-instance_method)
  freezes the object and everything nested in it, down to the strings
  in its arrays, and makes the result Ractor-shareable, so a parsed
  response can be handed to a `:ractor` tool call. It returns self,
  and freezing it twice does nothing.
  [`LLM::Object#frozen?`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html#frozen?-instance_method)
  returns true once the object has been frozen, and a write to a frozen
  object - through `#[]=`, `#merge!`, or `#delete` - raises `FrozenError`.

### LLM::Schema

* **schema: `LLM::Schema::Object#to_h` returns plain hashes** <br>
  [`LLM::Schema::Object#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema/Object.html#to_h-instance_method)
  unwraps the properties it holds now, so a property that is
  another schema, an `LLM::Object`, a `Hash`, or an `Array` of any
  of them comes back as a plain `Hash` all the way down. Before, a
  property kept the object it was built from, and the result could
  not be used where a plain JSON schema is expected.

* **schema: follow a chain of local references** <br>
  A `$ref` that points at another schema that holds
  a `$ref` of its own is resolved all the way down
  now, where only one hop was followed before and the
  second reference was read as if it were a concrete
  schema. A chain of aliases is bounded, and a
  reference that loops back on itself raises
  `TypeError`.

* **schema: decode a JSON Pointer in a `$ref`** <br>
  [`LLM::Schema.parse`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema.html#parse-class_method)
  decodes a JSON Pointer the way RFC 6901 spells it
  out now, so a token that holds a percent-encoded
  character, a `/` (`~1`), or a `~` (`~0`) resolves,
  an empty token is kept, and a token that names an
  array index addresses that array. A pointer that
  cannot be resolved still raises `TypeError`.

### LLM::Provider

* **provider: add `LLM::Hanzo`** <br>
  [`LLM::Hanzo`](https://r.uby.dev/api-docs/llm.rb/LLM/Hanzo.html)
  is a new, US-based provider that talks to [hanzo.ai](https://hanzo.ai)
  through its OpenAI-compatible chat completions API.
  It is not yet part of the official
  [models.dev](https://models.dev)
  registry but we have added our own registry entries that
  cover its flagship models. At the time of writing Hanzo
  is still in beta.

* **provider: improve error message that covers lack of API key** <br>
  The methods that return an instance of
  [`LLM::Provider`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html)
  (eg [`LLM.openai`](https://r.uby.dev/api-docs/llm.rb/LLM.html#openai-class_method))
  now include a helpful error message that indicates
  what key should be set. For OpenAI, the error message
  includes a string that looks like this:

  > did you forget to set `$OPENAI_API_KEY`?

* **provider: document `LLM::Provider#host` and `LLM::Provider#port`** <br>
  [`LLM::Provider#host`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#host-instance_method)
  returns the host a provider talks to, and
  [`LLM::Provider#port`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#port-instance_method)
  returns its port. Both were available before, but they are
  documented now, so a caller can read the address a provider
  talks to without reaching into its instance variables.

### LLM::Agent

* **agent: `LLM.interrupt` returns the agent it interrupted** <br>
  The
  [`LLM.interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM.html#interrupt-class_method)
  method returns the agent that was interrupted. <br>
  Before it would return `true` instead, and that's
  not as useful as the agent that was interrupted.
  Still returns `false` for a miss. The agent that
  is returned can access the model instance associated
  with it via the `record` method.

* **agent: add class-level compactor configuration** <br>
  The [LLM::Agent](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
  class can assign a compactor and
  its options. <br> Three methods exist
  to assign the compactor, and its options:
  * [LLM::Agent.compactor](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#compactor-class_method)
  * [LLM::Agent.compactor_options](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#compactor_options-class_method)
  * [LLM::Agent.set](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#set-class_method) (can set both)

* **agent: add `LLM::Agent#compactor` and `LLM::Agent#compactor_options`** <br>
  The
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
  class adds two new methods that provide access to an agent's
  compactor (and its options) at the instance level. By default
  the compactor is a Null compactor that does nothing:
  * [`LLM::Agent#compactor`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#compactor-instance_method)
  <br> returns the compactor class
  ([`LLM::Compactor::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor/Null.html)
  by default)
  * [`LLM::Agent#compactor_options`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#compactor_options-instance_method)
  <br> returns the compactor options (`{}` by default)

### LLM::Function

* **function: run a `:ractor` tool call in a single ractor** <br>
  Our previous Ractor implementation spawned
  two ractors that have now been replaced by a
  **single ractor** that maintains multiple
  [`Ractor::Port`](https://docs.ruby-lang.org/en/master/Ractor/Port.html)
  objects instead. Ractor ports are available
  in Ruby4 and onward. This implementation
  is much cleaner and helps bring Ractor support
  up to par with other concurrency strategies.

* **function: support the `:ractor` strategy on Windows** <br>
  The `:ractor` concurrency strategy works on
  Windows from llm.rb v18 on, where the hang it
  used to hit kept it out of the Windows test
  suite. It also needs Ruby 4.1.0 or later there,
  and both are available as pre-releases. The
  single ractor that hands its result to a
  `Ractor::Port` is what makes it work.

* **function: a tool error carries the exception's backtrace** <br>
  The
  [`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
  that reports a failed tool call holds the
  exception's `backtrace` in its value now, next
  to `error`, `type`, and `message`, so a caller
  can see where the tool failed. The trace is
  captured under every concurrency strategy.
  Before, a failure reported its class and its
  message only.

* **function: trace a sequential tool call** <br>
  The `:sequential` strategy tells a tracer that a tool started now, so
  [`LLM::Function::Sequential::Task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Sequential/Task.html)
  calls
  [`LLM::Tracer#on_tool_start`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_start-instance_method)
  when it spawns, and the span it returns is the span that
  [`LLM::Tracer#on_tool_finish`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_finish-instance_method)
  closes. Before, a sequential call reported that a tool finished and
  never that it started, so the two callbacks did not pair up the way
  they do on the other strategies.

### Console

* **console: run tool calls on a Ractor by default** <br>
  `llm.rb` defaults to the `:ractor` concurrency strategy
  now, where it ran tool calls sequentially. A tool class
  the console loads has to be Ractor-shareable, and `-c`
  picks another strategy, so `-c sequential` restores the
  old behavior.

* **console: add `llm.rb models.dev:download`** <br>
  `llm.rb models.dev:download` fetches `https://models.dev/api.json`
  and writes a pretty-printed `data/<provider>.json` file for each
  provider it knows, in a source checkout of llm.rb. It prints
  `ok: data/<provider>.json` for each file it writes. It needs no
  credentials and it takes no options, and a response that is not
  HTTP 200 aborts the command. The files it writes are overwritten in
  place, so it refreshes a checkout rather than an installed gem.

* **console: `-n` takes only the http transports** <br>
  The `-n` switch takes the name of an HTTP transport, `net-http`
  (the default) or `net-http-persistent`, in the dashed or the
  underscored spelling. The `curb` transport is gone, so `-n curb`
  raises `LLM::Error` with `:curb is not a recognized transport`,
  and the console exits 1. The help text lists the two transports
  that remain, and its example is `-n net-http-persistent`.

### LLM::MessageFilter

* **filter: rename `LLM::Transformer` as `LLM::MessageFilter`** <br>
  The class that rewrites a message before it is sent is
  [`LLM::MessageFilter`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter.html)
  now, and the subclasses it ships move with it. A filter takes a
  message and it returns a message, so the name says what `#call`
  does instead of naming a transformation the class never had to
  perform. No alias is left behind, because the v18 series is a
  breaking release already.

* **filter: rename `transformer:` and `transformer_options:`** <br>
  The `transformer:` and `transformer_options:` options a context or
  agent takes are `filter:` and `filter_options:` now.

* **filter: rename `LLM::Context#transformer`** <br>
  The method that returns the filter a context is configured with is
  [`LLM::Context#filter`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#filter-instance_method)
  now. `LLM::Context#transformer` is removed, and no alias is left
  behind.

* **filter: rename the `on_transform` stream callbacks** <br>
  The `on_transform` and `on_transform_finish` callbacks a stream
  implements are `on_filter` and `on_filter_finish` now, and each is
  given the filter that rewrites a prompt.

* **filter: add `LLM::MessageFilter.multi`** <br>
  [`LLM::MessageFilter.multi`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter.html#multi-class_method)
  composes several filters into a single
  [`LLM::MessageFilter::Multi`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter/Multi.html),
  so a message can be rewritten more than once
  before it is sent. It takes a provider and any
  mix of classes and instances, and the
  [`#filters`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter/Multi.html#filters-instance_method)
  it returns are the filters it runs.

* **filter: drop a tool error's backtrace by default** <br>
  [`LLM::MessageFilter::DeleteBacktrace`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter/DeleteBacktrace.html)
  removes the `backtrace` from an error that a
  tool reported, and every message is composed
  with it now, whether a `filter:` was
  configured or not. It runs before the
  filter it is composed with, which is what
  keeps a stack trace out of a request and out of
  a saved conversation.

* **filter: add `LLM::MessageFilter::Rescue`** <br>
  The
  [`LLM::MessageFilter::Rescue`](https://r.uby.dev/api-docs/llm.rb/LLM/MessageFilter/Rescue.html)
  module rescues the exception that a filter's `#call`
  method raises, so a filter that raises no longer takes
  the turn down with it.
  `LLM::MessageFilter.inherited` prepends it to every
  subclass, so every filter is covered.
  `LLM::Interrupt` is re-raised, and an interrupt still
  travels up the stack. Any other `StandardError` or
  `ScriptError` goes to `Rescue.crash`, which writes the
  report to `$stderr`: the filter's class, the exception's
  class, its message, and the first ten lines of its
  backtrace. The return value of `crash` is what `#call`
  returns, so a call that crashes returns `nil` rather
  than a message.

### LLM::Tracer

* **tracer: drop `#provider_name`, `#provider_host` and `#provider_port`** <br>
  A [`LLM::Tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html)
  read the provider's name, host, and port through three helpers
  of its own, and two of them reached into the provider's instance
  variables. The provider implements `#name`, `#host`, and `#port`
  itself now, and the bundled tracers read them from the provider
  they were built with. A tracer of your own should do the same,
  since `#provider_name`, `#provider_host`, and `#provider_port`
  are gone.
  [`LLM::Provider#name`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#name-instance_method)
  returns a Symbol, where the old `#provider_name` returned a
  String, so cast it when you need a String.

### LLM::Usage

* **usage: add `LLM::Usage.fields`** <br>
  [`LLM::Usage.fields`](https://r.uby.dev/api-docs/llm.rb/LLM/Usage.html#fields-class_method)
  returns the names of the fields an `LLM::Usage` object holds, as an
  array of strings: `input_tokens`, `output_tokens`, `reasoning_tokens`,
  `input_audio_tokens`, `output_audio_tokens`, `input_image_tokens`,
  `cache_read_tokens`, `cache_write_tokens`, and `total_tokens`. The
  ActiveRecord wrapper builds usage from a column with it, so a field
  that is added to usage is read from a saved conversation without a
  second list to maintain.

### JSON

* **json: remove the Yajl adapter** <br>
  The Yajl adapter has been removed due to a
  lack of Ruby4 support. <br>
  There is also not much upstream
  activity (last release was in 2022).
  Both
  [`LLM::JSONAdapter::JSON (default)`](https://r.uby.dev/api-docs/llm.rb/LLM/JSONAdapter/JSON.html)
  and
  [`LLM::JSONAdapter::Oj`](https://r.uby.dev/api-docs/llm.rb/LLM/JSONAdapter/Oj.html)
  still work, though.

### ORM

* **orm: add `unwrap!` to the ActiveRecord and Sequel wrappers** <br>
  The `#unwrap!` method returns the runtime a record wraps: an
  [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
  or an
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).
  This means a caller no longer has to reach for the wrapper's
  private runtime accessor but can use this new method instead. The
  runtime is memoized and every call returns the same object.

* **orm: read token usage from the column** <br>
  [`LLM::ActiveRecord#token_usage`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#token_usage-instance_method)
  (and its `#usage` alias) reads the `token_usage` that a `:jsonb` record
  holds in its column and returns it as an
  [`LLM::Usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Usage.html), so the
  usage of a saved conversation can be read without a provider, without
  credentials, and without loading the runtime. Every field is zero
  when the column holds no usage, and the value is memoized.

* **orm: read context window usage from the column** <br>
  [`LLM::ActiveRecord#context_window`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#context_window-instance_method),
  [`LLM::ActiveRecord#context_used`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#context_used-instance_method)
  and
  [`LLM::ActiveRecord#context_usage`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#context_usage-instance_method)
  read the projections that a `:jsonb` record holds in its column now,
  so the context window usage of a saved conversation can be read
  without loading the runtime. `#context_window` falls back to the
  runtime when the column holds none, `#context_used` returns `nil` when
  it holds none, and `#context_usage` returns `nil` when either of the
  two is `nil`.

* **orm: read the model from the column** <br>
  [`LLM::ActiveRecord#model!`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#model!-instance_method)
  returns the `model` that a `:jsonb` record holds in its column, and it
  falls back to the model the runtime resolves when the column holds
  none.

* **orm: `LLM::ActiveRecord::Message.for` takes `record:`** <br>
  [`LLM::ActiveRecord::Message.for`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/Message.html#for-class_method)
  takes the record as `record:` now, where it took it as `agent:`, so the
  keyword matches the `record:` a runtime is bound with when a wrapper
  builds one. The relation it returns is still scoped to that record's
  id.

### Transport

* **transport: remove the curb transport** <br>
  The
  [`LLM::Transport`](https://r.uby.dev/api-docs/llm.rb/LLM/Transport.html)
  class ships `:net_http` and `:net_http_persistent` only now.
  The curb transport has been removed for a few reasons
  but primarily because we couldn't offer the same interrupt
  semantics as net-http and net-http-persistent. When we
  add a transport in the future it will have to have
  consistent interrupt semantics otherwise the runtime
  provides a fragmented experience.

* **transport: drop the process-wide client cache** <br>
  The `:net_http_persistent` transport kept a class-level registry of
  `Net::HTTP::Persistent` clients, and every transport instance that
  served the same host, port, timeouts and scheme re-used one client
  from it, including instances built by different providers,
  [`LLM::MCP`](https://r.uby.dev/api-docs/llm.rb/LLM/MCP.html) and
  [`LLM::A2A`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A.html) clients.
  That registry was process-wide state that another Ractor cannot
  reach, so each transport keeps a client and a lock of its own now.

### Registry

* **registry: add `enso-auto` to the Hanzo registry** <br>
  [`LLM::Hanzo`](https://r.uby.dev/api-docs/llm.rb/LLM/Hanzo.html)
  ships its own registry entries because models.dev does not list
  it, and `enso-auto` joins them now. The model routes each request
  to an Enso tier by the reasoning depth the request asks for, it
  takes text and images, it calls tools, and it has a 900,000 token
  context window.

* **refresh model metadata** <br>
  Update `data/` with current listings, limits, and pricing. OpenRouter adds
  Glimpse, Pareto 26.10, Mercury 3, DeepSeek V4.1 Flash 1017, and a free
  MiniMax M3.1 Flash, and it drops DeepSeek-R1, Llama 3.3 Euryale 70B, and
  WizardLM-2 8x22B. Mistral drops its three open-weights models, OpenAI drops
  the GPT-5.2 and GPT-5.3 chat aliases, and DeepInfra adds DeepSeek V4.1
  Flash 1017. DeepSeek raises the context window of four models to 1,048,576
  tokens, Alibaba adds context tiers to six Qwen models and re-prices two
  others, Z.AI adds cache pricing to GLM-4.5V and GLM-4.6V, and OpenRouter
  corrects prices and limits across its listings.

* **refresh model metadata, second pass** <br>
  OpenRouter adds LFM2.5-2.6B, Kimi K3.1 Pro, GPT-6.1 Terra, GPT-6.1 Terra
  Pro and a free Flint, and it trades its free MiniMax M3.1 Flash for a
  paid MiniMax-M3.1-Flash. It drops Trinity Large Thinking, Granite 4.0
  Micro, the free Nemotron 3 Super, GPT-3.5-turbo and GPT-3.5 Turbo
  Instruct. Alibaba drops its six Qwen2.5 listings: the 7B, 14B, 32B and
  72B instruct models and both Qwen2.5-VL models. Mistral adds
  GLM-5.3-Flash and drops Devstral Medium, Devstral Small, Devstral Small
  2505, Mistral Large 2.1, Mistral Nemo and Pixtral Large (latest), Google
  adds Gemini Pro Latest and drops Veo 3.1, Veo 3.1 fast and Veo 3.1 lite,
  Moonshot adds Kimi K3.1 Pro and Kimi K3.1 Pro Highspeed, OpenAI adds
  GPT-6.1 Terra, DeepInfra adds Llama Guard 4 12B, and Bedrock adds Claude
  Sonnet 5.5 (AU). DeepInfra deprecates Inkling. OpenRouter raises the
  output limit of GPT-4.1 nano to 942,818 tokens, of Qwen3.8 2.4T A95B to
  909,000, of DeepSeek V4 Flash 0731 to 943,718 and of Qwen3.5 9B to
  235,929, and it cuts the output limit of DeepSeek V4 Flash, DeepSeek V4.1
  Flash, Beam 1.0 501B A23B and GLM Flash Latest to 131,072, of Qwen3.5
  35B-A3B to 81,920, of MiMo-V2.5 to 65,536 and of Gemma 3 4B IT to 16,384.
  Prices move as well: DeepSeek V4 Pro roughly doubles, DeepSeek V4.1 Flash
  input rises from 0.0355 to 0.14, GLM-5.2 input falls to 0.034, Nemotron 3
  Super 120B A12B rises from 0.08 input and 0.45 output to 0.30 and 2.40,
  Kimi K3 output rises from 11.94 to 20, and Mistral Large 4 doubles to
  1.36 input and 4.18 output. Alibaba adds cache pricing to Qwen Flash,
  Qwen Plus, Qwen3 Coder Flash and Qwen3-VL Plus, and DeepInfra adds
  cache-write pricing to DeepSeek V4 Flash, Kimi K2.7 Code, Kimi K3 and
  GLM-5.2.

* **refresh model metadata, third pass** <br>
  Bedrock adds GPT-6.1 Terra in its default, US and Global variants, with a
  1,050,000 token context window, a 272,000 token context tier, and
  cache-write pricing, and Mistral adds Mistral Large 4.0.8 and DeepSeek V4.1
  Flash 1017. Mistral halves the price of Mistral Large 4, to 0.70 input and
  2.10 output per million tokens, and widens its reasoning efforts to low,
  medium, and high. Google drops Nano Banana Pro and Nano Banana 2 and
  deprecates Nano Banana, OpenAI drops `gpt-image-1` and deprecates
  `gpt-image-1.5`, `gpt-image-1-mini` and `chatgpt-image-latest`, and
  DeepInfra deprecates Step 5 Preview. OpenRouter adds Particle-1 and Ternary
  Bonsai 2 9B, and it drops ten listings, among them GPT-4 Turbo, o1, o3-mini,
  o4-mini and GPT-5.2 Chat. It raises the output limit of DeepSeek V4 Flash
  and DeepSeek V4.1 Flash to 943,717 and 943,718 tokens, and of DeepSeek V3.1
  and V3.2 to 147,456, and the context window of Ling 3.1 Flash to 1,000,000
  tokens and of Nemotron 3 Super 120B A12B to 1,048,576. It cuts the Llama 4
  Scout context window to 327,680 and the output limit of Qwen3.8 2.4T A95B,
  Muse Spark Open and GLM-5.3-Flash to 131,072. Prices move as well: DeepSeek
  V4 Flash roughly doubles, GLM-5.3-Flash falls by three quarters, DeepSeek
  V4.1 Flash input drops to 0.045, DeepSeek Pro Latest output halves to 4,
  DeepSeek V3.2 cache reads rise from 0.028 to 0.13, and GLM-5.1 rises by 45%.

## v17.0.1

Changes since `v17.0.0`.

This is a small release with a single fix. An `intercept:`
given to an agent is passed to the context now, so the
intercept is called when a tool call is about to run.

### Fix

* **agent: forward `intercept:` to `LLM::Context`** <br>
  An `intercept:` given to an agent was kept on the
  agent as an instance variable and never read, so the
  context a turn runs against fell back to
  [`LLM::Intercept::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept/Null.html)
  and no tool call was intercepted. The option is
  passed to
  [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
  as a parameter now, the way `tools:` and `stream:`
  are. Each way to set it works: `set intercept:`, a
  block given to
  [`LLM::Agent.intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#intercept-class_method),
  and an `intercept:` given to
  [`LLM::Agent.new`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#initialize-instance_method).

## v17.0.0

Changes since `v16.0.0`.

This release is large, and includes a number of breaking
changes. It covers a lot of ground. I will try to cover the
highlights but I won't be able to cover everything, and
there won't be much depth. Check out the changelog entries
to learn more.

The Files API provided by deepseek is now supported
(via [LLM::DeepSeek#files](https://r.uby.dev/api-docs/llm.rb/LLM/DeepSeek/Files.html)),
and there was a large focus on the cancellation and
interrupt story. [LLM::Tracer](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html)
saw a lot of changes and it has the most changelog
entries in this release.

The `LLM::Guard` class was a focus as well, and it
has been renamed to
[LLM::Intercept](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html)
. An intercept can block a tool call with a return
of its own, it can mutate tool-call parameters in
place, validate tool call parameters, and anything
else a middleman that sits between the model and a
tool could do.

It is now possible to combine multiple tracers _or_
intercepts into a single tracer, or intercept. The
[LLM::Tracer.multi](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#multi-class_method)
and
[LLM::Intercept.multi](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html#multi-class_method)
methods exist for this purpose.

For everything else, keep reading.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| the default read timeout is 600 seconds | the default read timeout is 240 seconds |
| `LLM::Tracer#on_interrupt` and `#on_exit` do nothing | both raise `NotImplementedError`, so a tracer implements each |
| `LLM::Tracer#on_tool_finish(result:, span:)` and `#on_tool_error(ex:, span:)` | both also take `started_at:` and `finished_at:` |
| `LLM::Tracer#on_tool_error` is given the `Exception` a tool raised | it is given the `LLM::Function::Return` that holds the error |
| a tracer's tool callbacks run on the thread or fiber that ran the tool | they run on the agent's thread, like the other callbacks |
| a cancelled `:ractor` call returns in band with `cancelled: true` | it raises `LLM::Interrupt` in the caller's thread |
| `LLM::Guard`, `LLM::Guard::Null` | `LLM::Intercept`, `LLM::Intercept::Null` |
| `guard:` and `guard_options:` on a context or agent | `intercept:` and `intercept_options:` |
| `LLM::Context#guard` | `LLM::Context#intercept` |
| a guard that returned anything truthy stopped the tool call | only a `LLM::Function::Return` stops it, and any other value lets the call run |
| `trace:` on `LLM::Agent#console`, a deprecated alias | it is removed, and `tracer:` is the keyword |

### Intercept

* **intercept: rename `LLM::Guard` to `LLM::Intercept`** <br>
  The hook that sees a pending tool call before it
  runs is an
  [`LLM::Intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html)
  now, because it does more than guard a call:
  `#call` receives the `LLM::Function`, so an
  intercept can rewrite a call and let it run by
  returning `nil`. A subclass of `LLM::Guard` is
  renamed, the `guard:` and `guard_options:` a
  context or agent takes are `intercept:` and
  `intercept_options:`, and `LLM::Context#guard` is
  `LLM::Context#intercept`. `LLM::Guard` is
  removed, and no alias is left for it.

* **intercept: add `LLM::Intercept.multi`** <br>
  The
  [`LLM::Intercept.multi`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html#multi-class_method)
  factory combines one or more intercepts into a
  single
  [`LLM::Intercept::Multi`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept/Multi.html)
  that a context or agent can be given as
  `intercept:`. Each intercept is called in the
  order it was given, and the first that returns an
  [`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
  ends the call, so an intercept that returns `nil`
  lets the next one decide. An `intercept:` is
  taken as an instance now as well as a class,
  which is what lets the factory's return value be
  used as it is.

* **intercept: give an intercept the options it was built with** <br>
  The `intercept_options:` a context or agent is
  built with now reach
  [`LLM::Intercept#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html#call-instance_method)
  as keywords, and an intercept can read them
  through
  [`LLM::Intercept#options`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html#options-instance_method).
  Before, the options were held on the context and
  never passed to the intercept, so a subclass that
  wanted them had no way to read them.

### Provider

* **deepseek: upload a file once and refer to it by id** <br>
  [`LLM::DeepSeek#files`](https://r.uby.dev/api-docs/llm.rb/LLM/DeepSeek.html#files-instance_method)
  returns an
  [`LLM::DeepSeek::Files`](https://r.uby.dev/api-docs/llm.rb/LLM/DeepSeek/Files.html)
  object now, so a file can be uploaded once and a
  later chat request can name it instead of
  resending its bytes. Before, the call raised
  `NotImplementedError`. Uploads default to
  `purpose: "user_data"`, the only purpose
  DeepSeek accepts, and requests go to the root of
  the API host, where DeepSeek serves its Files
  API.

* **provider: add `LLM::Provider#retry_errors`** <br>
  The
  [`LLM::Provider#retry_errors`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#retry_errors-instance_method)
  method returns the exceptions that a request can
  raise and that are retried up to the provider's
  retry budget. A provider extends the array it
  inherits rather than replacing it, and
  [`LLM::DeepSeek#retry_errors`](https://r.uby.dev/api-docs/llm.rb/LLM/DeepSeek.html#retry_errors-instance_method)
  adds `LLM::ServerError`, the error DeepSeek
  returns when its servers are overloaded, so a
  request that finds an overloaded server is retried
  with a growing delay like a rate limit instead of
  failing on the first response.

* **provider: drop the default read timeout to 240 seconds** <br>
  The default read timeout is now 240 seconds (four
  minutes), down from 600 seconds (ten minutes). A
  timeout is retried, so the old default could be
  spent on a response that never arrives, and the
  new one fails sooner and opens a new session
  instead. DeepSeek prompted the change: it can
  stall past four minutes when it is under heavy
  load. Pass `read_timeout:` or `timeout:` to a
  provider to choose your own.

### Agent

* **agent: interrupt an agent via `LLM::Agent#id`** <br>
  The
  [`LLM.interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM.html#interrupt-class_method)
  method can interrupt an agent with nothing more
  than an ID that references it. A controller, a
  background job, or a socket handler can use this
  method to interrupt an agent that is running
  in the same process but on a different thread
  or fiber.

* **agent: add `LLM::Agent.registry`** <br>
  The
  [`LLM::Agent.registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#registry-class_method)
  method returns an object that holds every
  active instance of
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).
  An agent enters the registry when it starts a turn,
  and it exits the registry after that. The registry is
  thread-safe, local to a single process
  and
  [`LLM.interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM.html#interrupt-class_method)
  uses it under the hood to find an agent by ID.

* **agent: `LLM.interrupt` can retry until it finds an agent** <br>
  The method now takes `attempts:` and `interval:`, so
  a caller that asks for an agent before its turn has
  started can poll for it instead of giving up on the
  first miss, which is the loop a caller used to write
  by hand. `attempts` defaults to 1 and `interval` to
  0.1 seconds, so the method is unchanged until a caller
  asks it to wait. It returns `true` when an interrupt
  took place, and `false` otherwise.

* **agent: set an intercept at the class level** <br>
  [`LLM::Agent.intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#intercept-class_method)
  is where an agent's intercept is declared, so it
  can sit beside the agent's other defaults. It
  takes an intercept, or a block that is resolved
  when the agent is built, and `set intercept:`
  takes a `Symbol` that names an instance method,
  which is how
  [`LLM::Intercept.multi`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept.html#multi-class_method)
  is composed. An `intercept:` given to
  [`LLM::Agent.new`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#initialize-instance_method)
  is resolved the same way, and an ActiveRecord or
  Sequel model that wraps an agent carries it into
  the context it builds.

* **agent: remove the deprecated `trace:` keyword from `LLM::Agent#console`** <br>
  The `trace:` keyword is gone from
  [`LLM::Agent#console`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#console-instance_method)
  and from its `repl` alias. It was renamed to
  `tracer:` in an earlier release, and it was kept
  for a caller that still passed it, with a warning
  each time. The keyword is `tracer:`, so
  `trace: true` is `tracer: true`.

### Function

* **function: `:ractor` raises `LLM::Interrupt` (like everyone else)** <br>
  An
  [`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
  that is delivered to a tool running on a ractor
  will travel back to the caller and raise itself
  on the caller's thread, the same as all other
  concurrency strategies. This only happens after
  all tools have been interrupted themselves, and
  it is the last step in an interrupt. The caller
  is expected to rescue `LLM::Interrupt` and handle
  the interrupt from there.

* **function: add `LLM::Function::Task#intercepted?`** <br>
  An intercept stops a tool call when it returns
  an
  [`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html),
  because that Return is what the model is
  given for the call. Any other value lets the call
  through, where only `nil` did that before, so a
  guard that returned anything else stopped a tool
  call and returned it to the model instead.
  [`LLM::Function::Task#intercepted?`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#intercepted?-instance_method)
  is the predicate a task asks, and it is true only
  for a Return.

### Tracer

* **tracer: add `LLM::Tracer::Multi`** <br>
  The
  [`LLM::Tracer::Multi`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Multi.html)
  tracer fans every tracing callback out to a set of
  tracers, so a request can be logged to a file and
  exported to OpenTelemetry at the same time instead
  of choosing between them. Its `on_request_start`
  and `on_tool_start` return an array with one span
  per tracer, and that array is passed back as
  `span:` to the matching finish, error, or interrupt
  callback, so each tracer is handed the span it
  returned. A tracer that raises is reported rather
  than taking the request down with it, and
  `LLM::Interrupt` still travels up the stack.

* **tracer: add `LLM::Tracer.multi`** <br>
  Add
  [`LLM::Tracer.multi`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#multi-class_method)
  as a factory for `LLM::Tracer::Multi`. The
  provider comes first and is required, so a
  tracer given as a class is built with it,
  while a tracer given as an instance is used
  as it is. Builtin tracers and a custom one
  can be mixed in a single call.

* **tracer: build every tracer given to `LLM::Tracer.multi`** <br>
  Fix a bug where
  [`LLM::Tracer.multi`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#multi-class_method)
  passed its tracers to `LLM::Tracer::Multi.new` as
  a single array rather than one argument each,
  so a `Multi` held that array as its only
  tracer and every callback raised `NoMethodError`
  on it.
  [`LLM::Tracer::Rescue`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Rescue.html)
  reported the crash to standard error and
  swallowed it, so the request was not traced.

* **tracer: alias `LLM::Tracer.pretty_logger` as `LLM::Tracer.pretty`** <br>
  Add
  [`LLM::Tracer.pretty`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#pretty_logger-class_method)
  as an alias for `LLM::Tracer.pretty_logger`,
  so the shorter name builds the same tracer
  with the same options. The README uses
  `pretty` throughout.

* **tracer: protect an agent from a tracer crash** <br>
  The
  [`LLM::Tracer::Rescue`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Rescue.html)
  module prepends itself on every subclass of
  [`LLM::Tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html)
  and rescues uncaught exceptions that occur
  in tracer callback. Any callback that lets
  an exception exit its method will be rescued
  and the exception dumped onto standard error.

* **tracer: run every `on_tool_*` callback on the agent's thread** <br>
  The
  [`LLM::Tracer#on_tool_start`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_start-instance_method),
  `#on_tool_finish`, `#on_tool_error`, and
  `#on_tool_interrupt` callbacks are now
  called on the same thread as the agent
  they belong to - and this is true
  across all strategies. The previous
  implementation could call the tracer
  across threads and fibers when given
  the `thread`, `async`, and `fiber`
  strategies.

  Both `ractor`, and `fork` already kept the
  tracer on one thread, and now all strategies
  do. The last exception to the rule was
  `LLM::Tracer#on_interrupt`, which could be
  called on the thread that asked for the
  interrupt rather than the thread that
  received the interrupt.

* **tracer: run `LLM::Tracer#on_interrupt` on the agent's thread** <br>
  The
  [`LLM::Tracer#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_interrupt-instance_method)
  callback is now called on the agent's thread,
  or fiber, the same as every other callback.
  Before, it was called by whoever asked for the
  interrupt, so a tracer could be called across
  threads for an interrupt alone. The raise now
  unwinds to the turn it stopped, the tracer is
  told `scope: :agent` there, and the interrupt
  is re-raised for the caller.

* **tracer: `on_interrupt` and `on_exit` raise `NotImplementedError`** <br>
  The
  [`LLM::Tracer#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_interrupt-instance_method)
  and
  [`LLM::Tracer#on_exit`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_exit-instance_method)
  methods now raise `NotImplementedError`
  by default and subclasses of
  [`LLM::Tracer`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html)
  must implement them, otherwise
  the tracer will crash and the crash
  will be logged to standard error
  (`$stderr`). A tracer crash does
  not crash an agent, and both of
  these methods can be implemented
  as noops that return `nil`.

* **tracer: `on_tool_{finish,interrupt,error}` receive `started_at` / `finished_at`** <br>
  The
  [`LLM::Tracer#on_tool_finish`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_finish-instance_method),
  [`LLM::Tracer#on_tool_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_interrupt-instance_method)
  and
  [`LLM::Tracer#on_tool_error`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_error-instance_method)
  methods now receive `started_at`
  and `finished_at` attributes that can
  determine how long a tool took to run.
  Both are based on a monotonic clock
  (`Process::CLOCK_MONOTONIC`) and
  neither are `Time` objects.

* **tracer: add `LLM::Tracer#on_tool_interrupt`** <br>
  The [`LLM::Tracer#on_tool_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_interrupt-instance_method)
  method allows a tracer to close a span that
  was opened by
  [`LLM::Tracer#on_tool_start`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_tool_start-instance_method)
  and it is called for every tool that
  was interrupted. The callback receives
  the tool name and its tool call ID plus
  the span that was opened by `on_tool_start`.

* **tracer: return a span from `LLM::Tracer::Logger#on_tool_start`** <br>
  The
  [`LLM::Tracer::Logger#on_tool_start`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/Logger.html#on_tool_start-instance_method)
  method now returns a span that can be
  matched by another callback method that
  will close the span (eg `on_tool_start -> on_tool_finish`).

* **tracer: return a span from `LLM::Tracer::PrettyLogger#on_tool_start`** <br>
  The
  [`LLM::Tracer::PrettyLogger#on_tool_start`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/PrettyLogger.html#on_tool_start-instance_method)
  method now returns a span that can be
  matched by another callback method that
  will close the span (eg `on_tool_start -> on_tool_finish`).

* **tracer: add `LLM::Tracer::Logger#on_tool_interrupt`** <br>
  This method implements the new callback available on the
  superclass of Logger. The callback emits an `tool.interrupt`
  event and carries other metadata with it.

* **tracer: add `LLM::Tracer::PrettyLogger#on_tool_interrupt`** <br>
  This method implements the new callback available on the
  superclass of PrettyLogger. The callback emits a log entry
  that captures the tool interrupt via an IO object.

* **tracer: add `LLM::Tracer::Telemetry#on_tool_interrupt`** <br>
  This method implements the new callback available on
  the superclass of Telemetry. The callback records
  `error.type` as `LLM::Interrupt`, marks the span as
  an error, adds the standard `gen_ai.tool.finish`
  event and closes the span that was opened by
  `on_tool_start`. It follows the shape of
  `on_tool_error` and `on_interrupt` instead of
  emitting a `gen_ai.tool.interrupt` event, which is
  not part of the OpenTelemetry standard.

* **tracer: `LLM::Tracer#on_interrupt` raises `NotImplementedError` by default** <br>
  The
  [`LLM::Tracer#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_interrupt-instance_method)
  method is no longer a noop that returns nil. All tracers
  that subclass `LLM::Tracer` must implement this method. The
  change makes `on_interrupt` consistent with all other
  callback methods that are available on [LLM::Tracer](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html).

* **tracer: add `LLM::Tracer::Logger#on_interrupt`** <br>
  This method implements the callback available on the
  superclass of Logger. The callback emits an `info` event
  that is named from the scope (eg `request.interrupt`)
  and carries the scope and the request ID with it.

* **tracer: add `LLM::Tracer::PrettyLogger#on_interrupt`** <br>
  This method implements the callback available on the
  superclass of PrettyLogger. The callback writes a line
  to its IO object that names the provider and the scope
  the interrupt was received in.

* **tracer: add `LLM::Tracer::Telemetry#on_interrupt`** <br>
  This method implements the callback available on the
  superclass of Telemetry. A `:request` interrupt closes
  the span that `on_request_start` opened and marks it
  with an error and a `gen_ai.request.finish` event, since
  a request is the only interrupted scope with a span left
  open. The `:tool` and `:agent` scopes do nothing, because
  tools are closed by `on_tool_interrupt`, and any other
  scope raises `LLM::Error`.

* **tracer: `LLM::Tracer#on_exit` raises `NotImplementedError` by default** <br>
  The
  [`LLM::Tracer#on_exit`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_exit-instance_method)
  method is no longer a noop that returns nil. All tracers
  that subclass `LLM::Tracer` must implement this method. The
  change makes `on_exit` consistent with all other
  callback methods that are available on [LLM::Tracer](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html).

### LLM::Context

* **context: inherit database ID** <br>
  The
  [`LLM::Context#id`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#id-instance_method)
  and
  [`LLM::Agent#id`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#id-instance_method)
  methods will inherit the database ID
  of the record that is associated with
  them __if__ a record is in scope and
  __if__ the database ID is in the UUIDv7
  format. Otherwise a random UUIDv7 is
  generated as the ID. A record is normally
  in scope when given an ActiveRecord or
  Sequel model has wrapped an instance
  of
  [LLM::Context](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
   /
  [LLM::Agent](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html).

* **context: an ID must be in the UUIDv7 format** <br>
  An agent and context ID must __always__ carry a
  UUIDv7 format, even when given an explicit `id`
  as a parameter, and anything else raises
  `LLM::Error`. This is because the ID is used
  internally to compute other attributes
  (such as `LLM::Agent#created_at`). The runtime
  checks it with
  [`LLM::Utils.uuidv7?`](https://r.uby.dev/api-docs/llm.rb/LLM/Utils.html#uuidv7?-instance_method),
  the same predicate `LLM::Utils.timestamp` reads
  a time through, so an id this predicate accepts
  is an id `created_at` can be computed from.

### Registry

* **refresh model metadata** <br>
  Update `data/` with current listings, limits,
  and pricing. Anthropic adds Claude Haiku 5.5,
  Bedrock adds Claude Haiku 5.5, Claude Sonnet
  5.5 in the US and EU, Claude Sonnet 5 and
  Claude Opus 5 in India, and GLM-5.3 in the US
  and global regions, Mistral adds the Ministral
  3 3B, 8B, and 14B models, Mistral Large 4,
  Codestral 25.08, Voxtral Small, GLM-5.2, and
  Leanstral 1.5, DeepInfra adds
  `Qwen/Qwen3-VL-30B-A3B-Instruct`, and
  OpenRouter adds six models. OpenRouter drops
  sixteen entries, twelve of them Qwen, and
  Alibaba, Mistral, Moonshot, OpenAI, and xAI
  correct limits and prices. Google adds Gemini 4
  Argon, a reasoning model with a 1M-token context,
  DeepInfra adds Claude Fable 5 and Mistral Small 3
  and deprecates `Qwen/Qwen3.8-2.4T-A95B`, and
  OpenRouter adds `liquid/lfm-2.5-24b-a2b`,
  `google/gemini-4-argon`, the Scaledown extract
  and summarize models, and the Pareto models,
  drops `unbiased/pareto` and three Ling 3.0 Flash
  and Apodex entries, and reprices several DeepSeek,
  Z.ai, Tencent, Moonshot, Meta, and Gemma models.

### Fix

* **tools: require `test-cmd.rb` `~> 2.7.3`** <br>
  The exec-backed tools now need `test-cmd.rb`
  2.7.3 or later, up from 2.7.1. Version 2.7.2
  fixes a race where `Process.wait` could claim a
  process another thread had spawned, so a tool
  could return a status and a pid that
  belonged to another command, and 2.7.3 stops
  looking for `/bin/false` when a command is not
  found, which Windows does not have.

* **tools: name the tool that was not found** <br>
  The in-band error returned when a model asks for
  a tool that does not exist names it now, as
  `tool 'exec' not found`, where it said only
  `tool not found`. That is the same message
  [`LLM::Tool.find_by_name!`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#find_by_name!-class_method)
  raises when it cannot resolve a name, so the two
  paths read alike: the class raises
  [`LLM::NoSuchToolError`](https://r.uby.dev/api-docs/llm.rb/LLM/NoSuchToolError.html)
  rather than the `no such tool "exec"` it used to.

## v16.0.0

Changes since `v15.5.0`.

This release makes an interrupt precise: `LLM::Interrupt` moves outside
`StandardError`, a turn between its requests ends where it is, and a cancel is
delivered inside the tool that has to handle it. It also requires Ruby 3.4 or
later, reads a `:jsonb` record's messages from the column, saves a
record-backed conversation after each request, and adds
`LLM::ActiveRecord#messages!`, `LLM::Stream#on_step`, and a tracer's
`on_interrupt` hook.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| Ruby 3.3 or later | Ruby 3.4 or later |
| `record.messages` returns the messages the runtime holds | a `:jsonb` record returns a relation of `LLM::ActiveRecord::Message` rows |
| a `set_tracer` method on an ORM model | `set tracer:` in the block, or `tracer:` on the wrapper |
| a pre-start cancel is dropped on `:thread`, `:fiber`, and `:async`, a `NoMethodError` on `:fork`, and says nothing on `:ractor` | the cancel is held, and delivered inside the tool's call |
| a cancel that arrives between two requests does nothing | the turn ends there, and the caller sees `LLM::Interrupt` |
| a bare `rescue`, or `rescue => ex`, catches a cancel | `LLM::Interrupt` is outside `StandardError`, so both forms pass it through |

* **drop Ruby 3.3 support** <br>
  The gem now requires Ruby 3.4 or later. Ruby 3.3 cannot hold an
  interrupt for a ractor-backed tool call, so a cancel can arrive
  before the tool starts and never be delivered.

* **activerecord: read a `:jsonb` record's messages from the column** <br>
  The `#messages` of a `:jsonb` record is now a relation over the stored
  messages, so a conversation can be filtered and counted in SQL without a
  provider or credentials. Before, every record loaded the runtime; reach
  that again with `#messages!`, and order the relation by `position`
  because it is unordered.

* **function: hold a cancel that arrives before the tool starts** <br>
  A cancel that arrived before the tool started used to be lost: dropped on
  `:thread`, `:fiber`, and `:async`, a `NoMethodError` on a `:fork` task that
  had not been spawned, and nothing at all on `:ractor`. It is now held until
  the call opens and delivered inside it, so the tool is entered, its own
  `rescue` sees the interrupt, and a caller that cancelled a task it had not
  yet spawned is given the cancel rather than a return. On `:async`
  and `:fiber` the raise is asked of the scheduler rather than issued, so a
  tool that never yields still returns, and that caller sees a return with the
  tool told it was asked about.

* **interrupt: reach a turn that is between its requests** <br>
  A cancel that arrived between two requests used to do nothing, because
  there was nothing in flight to close and nothing running to raise into.
  It now ends the turn where it is, raising `LLM::Interrupt` into the
  caller the turn runs under and announcing `scope: :agent` to the tracer
  first. `LLM::Agent#run_loop` records that caller for as long as the turn
  lasts, and it implements `interrupt!` through
  [`LLM::Agent::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent/Interrupt.html).
  The raise lands in the thread or fiber the turn runs on, so it unwinds out
  of the turn to whoever called it.

* **interrupt: move `LLM::Interrupt` outside `StandardError`** <br>
  `LLM::Interrupt` is now an `Exception` rather than an `LLM::Error`, so a
  bare `rescue` and a `rescue => ex` pass a cancel through instead of
  swallowing it. Before, a broad rescue in a tool, a tracer, or an
  application could eat an interrupt, and the turn looked like one that had
  ignored its cancel. It is not a `SignalException`, since an interrupt has
  to be catchable and a signal is a framework's own condition. A caller that
  handles a cancel names `LLM::Interrupt`; `#wait` and the tool's
  `on_interrupt` hook are unchanged, and a task still carries the interrupt
  back to the caller rather than raising it inside its reactor.

### ActiveRecord

* **activerecord: add `messages!` for the runtime's own messages** <br>
  [`LLM::ActiveRecord#messages!`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#messages!-instance_method)
  returns the messages the runtime holds, including state that has not been
  saved, where `#messages` reads the column. Use it to reach the live
  conversation of a `:jsonb` record. The Sequel plugin responds to
  `#messages!` too, where it is the same call as `#messages`.

### Agent

* **agent: keep the instructions it injected in step** <br>
  An agent now refreshes its instructions before each request, so a
  conversation restored from saved state runs on the agent's current
  instructions instead of the ones it was saved with. A message the caller
  composed is never touched.

* **agent: identify its own instructions by the mark, not by the role** <br>
  Fix a bug where an agent on Google added a fresh copy of its instructions
  every turn, because it looked for a `system` message and Google gives
  instructions the `user` role. It now marks the message it wrote and finds
  it by that mark.

### Console

* **console: erase with the backspace key on OpenBSD** <br>
  The console now erases for every code a backspace key sends: DEL (127),
  ^H (8), and curses's `KEY_BACKSPACE`. Before, only 127 worked, so
  backspace did nothing on the OpenBSD console.

### Fix

* **fork: require xchan.rb `~> 0.24`** <br>
  The `:fork` strategy now needs `xchan.rb` 0.24 or later, up from 0.23.

### Function

* **function: deliver an interrupt to the tool, not to whatever is running** <br>
  A cancel is now aimed at the tool on every concurrency strategy. A running
  tool is entered and
  [`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html) raised
  inside it, so its own `rescue` and its
  [`LLM::Tool#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#on_interrupt-instance_method)
  hook see it, whether the tool was given as an instance or a class. A cancel
  that arrives before the tool starts is held and delivered inside the call, and
  one that arrives after the tool returns is a no-op that leaves the result
  alone. Before, the raise landed wherever the target thread or fiber had got
  to, and a tool's hook ran on some strategies but not others. A pre-start
  cancel was dropped on `:thread`, `:fiber`, and `:async`, was a `NoMethodError`
  on `:fork`, and said nothing on `:ractor`. Three strategies keep a shape of
  their own: `:fiber` and `:async` ask the fiber scheduler for the raise, so a
  tool that never yields is one it cannot reach, and `:sequential` runs the tool
  in the caller's own thread, so it tells the tool through its hook alone.

* **function: a task that has returned returns again** <br>
  A second `#wait` returns what the first one took, which is what
  `Thread#value` does, so a task that has returned returns again. That covers an
  `:async` queue the first wait drained, a `:fork` channel the task closed, and
  a `:ractor` whose result is held by a ractor of the task's own rather than
  asked of the ractor that ran the tool and has gone. A group's cancel reaches
  every task it holds, and an interrupt re-raises the same exception rather than
  blocking. Before, a second wait blocked on a queue nothing would fill, or read
  a channel or ractor that had already closed.

* **function: a forked call that died without a result returns** <br>
  A `:fork` tool that died before it wrote anything used to leave
  [`LLM::Function::Fork::Task#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Fork/Task.html#wait-instance_method)
  blocked on a read that never ended, because this side still held the write
  end of the same channel and so never saw end of file. Each side now closes
  the end it does not use, which makes that ending an `EOFError`, and `#wait`
  returns it in band rather than raising into the turn, the way the runtime
  returns a tool that raised: `{error: true, type: "EOFError", message: "the
  tool exited unexpectedly"}`. A second wait is given the same return.

* **function: refuse a `:fiber` scheduler that cannot hold a cancel** <br>
  The `:fiber` strategy now raises
  [`LLM::FiberError`](https://r.uby.dev/api-docs/llm.rb/LLM/FiberError.html) when
  `Fiber.scheduler` does not implement `fiber_interrupt`, because a cancel that
  arrives before the call is held by asking the scheduler for a raise at the
  call's first instruction. A scheduler that cannot be asked would be sent the
  cancel before the call instead, where the tool never runs, so the strategy
  refuses in the caller's hands, before a fiber is scheduled at all.

### ORM

* **orm: save a conversation after each request, not once per turn** <br>
  A record-backed conversation is now written down as it goes, so an
  interrupted turn can be continued instead of started over. Before, the
  wrappers saved once when the whole turn finished, so an interrupted turn
  persisted nothing.

* **orm: drop the `set_tracer` callback** <br>
  The wrappers no longer resolve a tracer from a `set_tracer` method on the
  model. Declare it where an agent's other defaults are declared, with
  `set tracer:` in the block, or pass it to the wrapper as `tracer:`, which
  is what a context has. A model that implements `set_tracer` today loses
  its tracer silently.

### Prompt

* **prompt: let a message carry fields a caller attaches to it** <br>
  [`LLM::Prompt#system`](https://r.uby.dev/api-docs/llm.rb/LLM/Prompt.html#system-instance_method),
  `#user`, `#developer`, and `#talk` (and its `#chat` alias) now take an
  `extra:` keyword, so a caller can tag a message with fields of its own. The
  runtime reads those fields back instead of guessing provenance from the role.

### Provider

* **deepseek: support image attachments in chat completions** <br>
  DeepSeek's vision models now accept an image. A `:image_url` object is sent
  as an `image_url` item, and a local image file as a base64 data URI.
  Anything else is rejected with a reason: a remote file or an `LLM::Response`
  raises
  [`LLM::PromptError`](https://r.uby.dev/api-docs/llm.rb/LLM/PromptError.html)
  because DeepSeek has no Files API, and a non-image local file raises because
  its models read images only.

* **provider: keep a scoped header alive through garbage collection** <br>
  Fix a bug where a header set by
  [`LLM::Provider#with`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#with-instance_method)
  could be collected before its block returned, so a garbage collection inside
  the block was enough to make a request later in the same scope go out without
  it. The store held the header hash weakly. It now holds it for as long as the
  provider is alive, so a scoped header lasts as long as the scope does.

### Registry

* **refresh model metadata** <br>
  Update `data/` with current listings, limits, and pricing. Anthropic adds
  Claude Sonnet 5.5, OpenAI adds GPT-6.1 Sol and the Daybreak Blue and Daybreak
  Red models, Bedrock adds Claude Sonnet 5.5, GPT-6 Sol, GPT-6 Luna, and GPT-6.1
  Sol across regions plus Grok 4.7 in the global and US regions, Alibaba adds
  the Qwen3.5, Qwen3.7, and Qwen3.8 Flash models, DeepInfra adds the Xiaomi
  MiMo V2.6 models and `tencent/Hy4-preview`, xAI adds Grok Imagine Video 1.5
  Lite, and OpenRouter adds ten models. OpenRouter drops six entries, Mistral
  drops `magistral-small`, and Google, DeepSeek, Moonshot, and Z.ai correct
  limits and prices.

### Schema

* **schema: apply every `parameter` option to the leaf** <br>
  Every option given to `parameter` now reaches the schema, so `min:`, `max:`,
  `multiple_of:`, and `const:` are no longer dropped, a `default: false`
  survives, and `required: false` marks a parameter optional. Before, only
  `required`, `default`, and `enum` were read, so a tool that declared a range
  sent a plain number and lost it.

### Stream

* **stream: add `on_step`, called when a request completes** <br>
  [`LLM::Stream#on_step`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_step-instance_method)
  is a new callback, fired once the prompt and response are in the
  conversation. It marks where one request ends and the next begins, which is
  where a stream can checkpoint, and it fires once per successful request even
  when streaming is off.

### Tools

* **tools: wait for a command's status, not only for it to stop running** <br>
  Fix a bug where an exec-backed tool could return `ok: nil` for a command
  that ran and printed its output.
  [`LLM::Tool::Utils#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html#wait-instance_method)
  left as soon as `running?` said the process was gone, and the status is not
  decided at that moment, so `command.success?` was read too early.
  It waits for the status now, and a command that was never found is
  the exception, because there was nothing to reap.

### Tracers

* **tracer: report a request that failed** <br>
  [`LLM::Tracer#on_request_error`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_request_error-instance_method)
  is now called whenever a request ends without a response, so a span is always
  closed. Before, only provider errors that became exceptions were reported, so
  a dropped connection left a span open, which reads like a process that died.

* **tracer: add `on_interrupt`, called when a request is interrupted** <br>
  [`LLM::Tracer#on_interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#on_interrupt-instance_method)
  is a new hook, called with `scope: :request`, `:tool`, or `:agent` before
  `LLM::Interrupt` reaches the caller, so a tracer can record an interrupted
  turn. An `:agent` scope means the interrupt landed between a turn's
  requests, where there was nothing more precise to interrupt. It does
  nothing by default, since a raise here would replace the interrupt
  callers are written against.

* **tracer: announce an interrupted tool phase once** <br>
  [`LLM::Context#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#wait-instance_method)
  now calls `on_interrupt` once when an interrupt unwinds through it, rather
  than once per tool, matching the single exception the caller receives.
