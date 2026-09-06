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

> Changelog <br>
> [r.uby.dev](https://r.uby.dev) project

## What's next

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `LLM::Tool::Shell`, tool name `"shell"` | `LLM::Tool::Exec`, tool name `"exec"` |
| `require "llm/tools/shell"` | `require "llm/tools/exec"` |
| `LLM::Repl`, `LLM::Agent#repl` | `LLM::Console`, `LLM::Agent#console` |
| `require "llm/repl"` | `require "llm/console"` |
| `Git#call(action: "log")` | `Git#call(subcommand: "log")` |
| `ReadFile#call` returns `{ok:, content:}` | returns `{ok:, lines:, truncated:}` |

* **tools: rename `shell` to `exec`** <br>
  The command tool is renamed to
  [`LLM::Tool::Exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Exec.html),
  which better reflects that it spawns a command without a shell. The tool
  name and description change from `shell` ("run a shell command") to
  `exec` ("run a command without a shell"). The old `require
  "llm/tools/shell"` path no longer exists; use `require
  "llm/tools/exec"` instead.

* **tools: rename `repl` as `console`** <br>
  The interactive loop is renamed to
  [`LLM::Console`](https://r.uby.dev/api-docs/llm.rb/LLM/Console.html),
  which better reflects what it does. `agent.console` is the primary
  entry point, and the require path moves from `llm/repl` to
  `llm/console`. Backwards-compatible aliases remain: `LLM::Repl`,
  `LLM::Agent#repl`, the ORM wrappers' `#repl`, and `LLM::Command =`
  `LLM::Console::Command`.

* **tools: rename `LLM::Tool::Git`'s `action` parameter to `subcommand`** <br>
  `LLM::Tool::Git#call` now takes `subcommand:` instead of `action:`.
  The tool description, parameter schema, and comments all use the
  `git subcommand` term, matching how git itself is documented. A new
  `LLM::Tool::Git.subcommands` class method returns the supported
  subcommands (`log`, `diff`, `commit`, `checkout`, `branch`, `show`).

* **tools: read-file returns structured lines** <br>
  `LLM::Tool::ReadFile#call` now returns its content as structured
  `{lineno:, content:}` lines under a `lines:` key instead of a single
  `content:` string, and adds a `truncated:` flag. A reversed range
  (`start: 20, stop: 2`) is swapped to read lines 2 through 20. Callers
  that read the raw `content:` string must switch to the `lines:` array.

### Core

* **message: add `LLM::Message#created_at`** <br>
  [`LLM::Message#created_at`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#created_at-instance_method)
  returns the time the message was created, defaulting to the moment the
  message is initialized. The timestamp is serialized into
  [`LLM::Context#to_json`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#to_json-instance_method)
  as an ISO-8601 string and restored on deserialization, so it can be
  stored alongside the rest of the conversation.

### Cli

* **cli: add a `-v` switch** <br>
  `bin/llm.rb` gains a `-v` switch that prints the version (`llm.rb v#{LLM::VERSION}`) and exits.

### Console

* **console: raise `LLM::Interrupt` on the agent's thread** <br>
  Pressing Esc to cancel now also raises `LLM::Interrupt` on the agent's
  thread. `LLM::Agent#cancel!` alone can be a no-op at some stages of the
  request lifecycle, so the console backs it up by interrupting the thread
  that runs the agent.

* **console: alias `/compact` as `/keep`** <br>
  The console now accepts `/keep` as an alias of `/compact`, so `/keep 20%`
  keeps 20% of the context window. Closes
  [issue #161](https://github.com/r-uby-dev/llm.rb/issues/161).

### Tools

* **tools: write-file appends a trailing newline by default** <br>
  `LLM::Tool::WriteFile` now ensures written content ends with a newline,
  adding one when the content does not already end with `\n`. It previously
  wrote the content exactly as given. A new `newline:` parameter (default
  `true`) controls this, so `newline: false` writes the content exactly as
  given.

* **tools: fix `edit-file` treating `before` as a regex** <br>
  `LLM::Tool::EditFile` now escapes the `before` snippet with
  `Regexp.escape`, so regex metacharacters are matched literally, and
  switches to the block form of `sub` so the `after` replacement keeps
  backslash sequences like `\1` and `\&` literal.

* **tools: bound tool output with `LLM::Tool.max_bytes`** <br>
  [`LLM::Tool.max_bytes`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#max_bytes-class_method)
  is a configurable default (75,000) for the maximum number of bytes a
  tool returns to the model, for example `LLM::Tool.max_bytes(175_000)`. It
  does not enforce the limit by itself;
  [`LLM::Tool::Utils#truncate`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html#truncate-instance_method)
  trims a string within the limit and marks the trailing content as
  truncated.

* **tools: bound `read-file`, `rg`, and `exec` output** <br>
  `LLM::Tool::ReadFile`, `LLM::Tool::Rg`, and `LLM::Tool::Exec` now accept a
  `max_bytes:` parameter and truncate their output within
  `LLM::Tool.max_bytes`, so a large file read or a runaway search can no
  longer flood the context window. `rg` also gains a `max_count:` parameter
  that caps the number of results per file.

* **tools: route `git` and `rg` through `exec`** <br>
  `LLM::Tool::Git` and `LLM::Tool::Rg` now implement their calls through the
  `exec` tool, inheriting its bounded-output protections and dropping the
  duplicated command-spawning code.

* **tools: route `mkdir` and `ruby` through the `exec` tool** <br>
  `LLM::Tool::Mkdir` and `LLM::Tool::Ruby` now implement their calls
  through the `exec` tool, completing the refactor so every tool that
  shells out flows through the shared command runner with its bounded
  output. The shared runner is `LLM::Tool::Exec`, the renamed
  `LLM::Tool::Shell`, so requiring `llm/tools/exec` replaces the old
  `llm/tools/shell` path.

* **tools: resolve defaults through `LLM::Utils.resolve_option`** <br>
  A tool parameter default can now be an immediate value, a Symbol resolved
  as a method on the tool, or a Proc evaluated lazily at runtime, matching
  how `LLM::Agent` resolves its attributes. This lets a default track a
  value that can change between boot and runtime, such as
  `LLM::Tool.max_bytes`.

* **tools: require `test-cmd.rb` `~> 2.5`** <br>
  The `Git`, `Mkdir`, `Rg`, `Ruby`, and `Exec` tools now require the
  `test-cmd.rb` gem at `~> 2.5`, so they load against the updated command
  runner, which can read a limited number of bytes and drop any further
  output so a misbehaving command cannot flood memory.

### Registry

* **refresh model metadata** <br>
  Update `data/` with current pricing, limits, and capabilities for the
  OpenRouter, OpenAI, Bedrock, DeepInfra, DeepSeek, Google, Mistral,
  Moonshot, Z.ai, and Alibaba registries.

### Provider

* **provider: retry `Net::WriteTimeout`, too** <br>
  Requests that raise `Net::WriteTimeout` are now retried alongside the
  other timed-out and rate-limited requests, up to the `retry_budget`,
  matching how `Net::OpenTimeout` and `Net::ReadTimeout` are handled. The
  console status bar also reports a write timeout as `Timed out`.

* **alibaba: default to a retry budget of 8** <br>
  An agent that runs on the Alibaba provider now defaults to a retry
  budget of 8 instead of 5, because Alibaba (token plan) frequently rate
  limits and times out requests that it later recovers from. An explicit
  `retry_budget:` still overrides the default.

### Fix

* **json: scrub invalid UTF-8 on dump** <br>
  Fix a bug where [`LLM::JSONAdapter`](https://r.uby.dev/api-docs/llm.rb/LLM/JSONAdapter.html)
  raised a JSON generator error when dumping a string tagged as UTF-8 that
  carried invalid bytes. The normalize step now transcodes every string to
  valid UTF-8, replacing invalid sequences with the replacement character,
  so dumping works on `json ~> 3.0`.

* **fork: require xchan.rb `~> 0.23`** <br>
  The `:fork` concurrency strategy now requires the `xchan.rb` gem at
  `~> 0.23` instead of `~> 0.22`, following the deadlock fix, so it loads
  against the socket-based channel that keeps the writer and reader from
  getting stuck.

## v15.1.0

Changes since `v15.0.3`.

This release adds the OpenRouter provider, splits provider timeouts
into `connect_timeout` and `read_timeout`, retries timed-out requests,
and renames `on_rate_limit` to `on_retry`. Skills now gain a
frontmatter `model:` parameter and inherit the parent agent's model,
while the CLI gains `-m` and `-x` switches, and the console shows retry
progress and measures text by display width.

### Provider

* **add `LLM::OpenRouter` for the OpenRouter provider** <br>
  [`LLM::OpenRouter`](https://r.uby.dev/api-docs/llm.rb/LLM/OpenRouter.html)
  is a new provider that talks to [OpenRouter](https://openrouter.ai)
  through its OpenAI-compatible API, contributed via
  [PR #165](https://github.com/r-uby-dev/llm.rb/pull/165). Create an
  instance with
  [`LLM.openrouter`](https://r.uby.dev/api-docs/llm.rb/LLM.html#openrouter-class_method),
  which accepts the same `key:`, `host:`, and `base_path:` options as the
  OpenAI provider. It defaults to the `openrouter/auto` router model and
  supports chat completions, streaming, tool calls, structured output,
  and embeddings; image, audio, moderation, files, and vector store
  endpoints raise `NotImplementedError`. Model metadata ships in
  `data/openrouter.json` for the registry.

* **provider: `LLM::Provider#with` accepts headers without the `headers:` keyword** <br>
  [`LLM::Provider#with`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#with-instance_method)
  now accepts headers directly as a Hash (`llm.with("User-Agent" => "llmrb/1.0")`)
  in addition to the legacy `headers:` keyword form. Both are merged, and
  the keyword form remains for backwards compatibility.

* **providers: `model: nil` falls back to `default_model`** <br>
  [`LLM::Provider`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html)
  now treats a `model: nil` payload as "use the default model" instead of
  sending a model value that providers reject. Previously a `{model: nil}`
  param overwrote the default and then was removed by `.compact`, leaving
  undefined behavior where providers could reject the request.

* **openai: handle `model: nil` in the Responses API** <br>
  The OpenAI Responses API path now also falls back to the default model
  when `model: nil`, matching the completions path.

* **provider: separate `connect_timeout` and `read_timeout`** <br>
  [`LLM::Provider`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html)
  now accepts a `connect_timeout:` for opening the connection (default 5
  seconds) and a `read_timeout:` for waiting on an idle connection (default
  600 seconds), instead of a single `timeout`. The legacy `timeout:` option
  remains as a shorthand for `read_timeout`. The provider exposes the new
  `#read_timeout` and `#connect_timeout` accessors.

* **provider: retry timed-out requests** <br>
  Requests that time out (`Net::OpenTimeout` or `Net::ReadTimeout`) are now
  retried along with rate-limited requests, up to the `retry_budget`. When
  a heavily loaded provider (for example DeepSeek) drops the connection
  during the connect or read phase, the request is retried instead of
  failing, and the stream is notified through `on_retry`.

* **context: retry on `LLM::InsufficientQuotaError`, too** <br>
  A request that raises
  [`LLM::InsufficientQuotaError`](https://r.uby.dev/api-docs/llm.rb/LLM/InsufficientQuotaError.html)
  is now retried like other rate-limited requests. The error is a subclass
  of `LLM::RateLimitError` and can be raised at regular intervals, in
  particular by the Alibaba provider.

* **cost: return `LLM::Cost.zero` when the registry has no pricing** <br>
  Add
  [`LLM::Cost.zero`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html#zero-class_method),
  a factory for a zero-valued cost breakdown.
  [`LLM::Context#cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#cost-instance_method)
  now returns it when the active model has no pricing in the registry (for
  example OpenRouter's `openrouter/auto` router model), instead of crashing
  on a nil pricing entry.

### Skills

* **skills: add a `model` frontmatter parameter** <br>
  A skill's `SKILL.md` frontmatter can now declare a `model:` value, so a
  skill's sub-agent runs on a specific model instead of the default. This
  lets a parent agent run on one model (for example `deepseek-v4-flash`)
  while the skill runs on another (`deepseek-v4-pro`). The `model` value is
  not strictly portable between providers.

* **skills: inherit the model of the parent agent** <br>
  A skill's sub-agent now inherits the active model of the agent that
  spawns it instead of falling back to the provider default. The frontmatter
  `model:` parameter overrides it explicitly when set.
  [`LLM::Context#model`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#model-instance_method)
  now falls back to the provider's default model when no model is set.

### Stream

* **stream: rename `on_rate_limit` to `on_retry`** <br>
  [`LLM::Stream#on_rate_limit`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_rate_limit-instance_method)
  is renamed to
  [`LLM::Stream#on_retry`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_retry-instance_method),
  which fires when a request is retried after a rate limit or a timeout,
  and now receives the one-based retry attempt number as a second argument.
  The old `on_rate_limit` name remains as an alias.

### CLI

* **cli: add a `-m` switch for choosing the model** <br>
  `bin/llm.rb` now accepts `-m MODEL` to run the session on a model other
  than the provider default, for example
  `llm.rb -p deepseek -m deepseek-v4-pro`. A model unknown to the provider's
  registry prints an error and exits.

* **cli: add a `-x` switch for the read timeout** <br>
  `bin/llm.rb` now accepts `-x SECONDS` to set the provider read timeout.

* **cli: print a backtrace on fatal crashes** <br>
  When `bin/llm.rb` hits an unexpected error, the crash message now includes
  up to three stack lines from the backtrace, so the failure is easier to
  locate and report than a bare diagnostic.

### Console

* **console: show retry progress in the status bar** <br>
  When a request is rate limited or times out, the curses-based console status
  bar shows a retry indicator with the error and the remaining attempts, for
  example `🔁 Rate limited • attempt 2 of 5`.

* **console: measure text width with `unicode-display_width`** <br>
  The curses-based console now counts and slices text by display column width
  instead of character count, so wrapping, table columns, and clipping stay
  aligned for wide characters such as emoji. It requires the optional
  `unicode-display_width` gem.

* **console: treat `LLM::InsufficientQuotaError` as a rate limit in the status bar** <br>
  The curses-based console status bar now shows `Rate limited` when a request
  raises
  [`LLM::InsufficientQuotaError`](https://r.uby.dev/api-docs/llm.rb/LLM/InsufficientQuotaError.html),
  matching how ordinary `LLM::RateLimitError`s are shown, instead of falling
  through to the raw class name.

### Registry

* **refresh model metadata** <br>
  Update `data/*.json` with current model listings and pricing, adding
  GPT-5.6 Sol, Terra, and Luna models to Bedrock, Grok 4.6 and Grok Imagine
  Image 2.0 to xAI, DeepSeek V4 Flash Vision to DeepSeek, and DeepSeek V4
  Pro 0813, Qwen3 VL, and Qwen3.8 models to DeepInfra.

## v15.0.3

Changes since `v15.0.2`.

This release fixes ActiveRecord `:json`/`:jsonb` serialization so tool
call arguments round-trip as JSON objects instead of arrays of pairs.

### Fix

* **activerecord: serialize tool call arguments properly** <br>
  Fix a bug where the ActiveRecord `:json`/`:jsonb` layer serialized tool
  call arguments as an array of pairs instead of a Hash. The context is
  now serialized through its JSON form, so tool call arguments round-trip
  as JSON objects that providers accept.

## v15.0.2

Changes since `v15.0.1`.

This release fixes a concurrency race in MCP tool calls by
reference-counting the transport session, so overlapping tool calls
reuse the running transport instead of racing `start`/`stop`.

### Fix

* **mcp: fix concurrent MCP tool call race** <br>
  `LLM::MCP` now reference-counts its transport session: the first
  caller starts the transport and the last caller stops it. Concurrent
  or overlapping tool calls reuse the running transport instead of
  racing `start`/`stop`, avoiding "MCP transport is not running" errors
  that could occur with the `async` strategy. An externally started
  transport is never stopped by a borrower.

## v15.0.1

Changes since `v15.0.0`.

This release fixes agent `set` handling of single `Symbol`/`Proc`
values and resolves ORM options as `Symbol`s through the bound record
instead of the `LLM::Agent` instance.

### Agent

* **agent: fix `set (skills|tools): Symbol|Proc`** <br>
  The `skills`, `tools`, `confirm`, and `schema` class accessors now
  consistently resolve a single `Symbol` or `Proc` lazily at agent
  initialization, so `LLM::Agent.set(skills: proc { [...] })` and
  `LLM::Agent.set(tools: :tools)` no longer raise. The `set` family
  shares one `single_callable?` helper rather than each accessor
  duplicating its own logic.

### Fix

* **orm: resolve a `Symbol` through the bound record** <br>
  When an ORM model using `acts_as_agent` (ActiveRecord), `plugin :agent`
  (Sequel), or `acts_as_llm` / `plugin :llm` configures an option as a
  `Symbol`, that symbol is now resolved on the model instance (or its
  bound record) instead of the `LLM::Agent` instance. The contexts and
  agents built by the wrappers are now bound to the record, so a model like
  `agent.set :tools` with a `tools` method on the record works as
  expected.

## v15.0.0

Changes since `v14.0.0`.

This release renames `usage` to `token_usage` across contexts, agents,
and messages, makes `context_window` return `nil` when unknown, and
makes `LLM::Cost` accessors always return `Float`. It also adds the
Alibaba provider, automatic API key discovery from the environment,
new context-usage and context-used methods, a retry budget for
rate-limited requests, and a range of REPL and skills improvements.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `ctx.usage` / `agent.usage` / `msg.usage` | `ctx.token_usage` / `agent.token_usage` / `msg.token_usage` (`usage` remains an alias) |
| `LLM::Message#usage` returns `LLM::Object` | `LLM::Message#token_usage` returns a copy of `LLM::Usage`, for assistant messages only |
| `ctx.context_window` returns `0` when the model isn't in the registry | returns `nil` when unknown |
| `LLM::Cost#input` (and other accessors) return `nil` when unused | return `0.0` |
| `ctx.usage` returns the most recent assistant message usage | sums token usage across all assistant messages |
| a skill exposes its tool as `weather` (the skill name) | the generated tool is now named `weather-skill` |

* **rename `#usage` to `#token_usage` across contexts, agents, and messages** <br>
  [`LLM::Context#usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#usage-instance_method),
  [`LLM::Agent#usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#usage-instance_method),
  and
  [`LLM::Message#usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#usage-instance_method)
  are now aliases of `token_usage`.
  [`LLM::Message#token_usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html#token_usage-instance_method)
  now returns a copy of `LLM::Usage` instead of `LLM::Object`, and only
  returns a value for assistant messages.

* **`LLM::Context#context_window` now returns `nil` when unknown** <br>
  [`LLM::Context#context_window`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#context_window-instance_method)
  now returns `nil` when the model's context window size is not known to the
  runtime, instead of `0`. This makes the code check for a window instead
  of a number, so an unknown window no longer reads as a real (zero) size.

* **`LLM::Cost` accessors always return `Float` objects** <br>
  The cost accessors on
  [`LLM::Cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html)
  (`input`, `output`, `input_audio`, `output_audio`, `input_image`,
  `cache_read`, `cache_write`, and `reasoning`) now always return a
  `Float`, returning `0.0` when no tokens of that kind were used, instead
  of `nil`. Callers can sum and compare cost values without guarding
  against `nil`.

* **expose new context methods on the ActiveRecord and Sequel wrappers** <br>
  The `acts_as_llm` (ActiveRecord) and `plugin :llm` (Sequel) wrappers
  now expose `context_used` and `context_usage`, delegating to the
  wrapped `LLM::Context`. `token_usage` replaces `usage` (which remains
  as an alias), and `context_window` now returns `nil` when the model's
  context window is unknown instead of `0`.

### Core

* **discover API keys from the environment** <br>
  [Cloud provider factories](https://r.uby.dev/api-docs/llm.rb/LLM.html)
  (`LLM.anthropic`, `LLM.google`, `LLM.deepseek`, `LLM.openai`,
  `LLM.xai`, `LLM.mistral`, `LLM.zai`, `LLM.moonshot`,
  `LLM.alibaba`, and `LLM.aliyun`) now resolve the provider's API key
  automatically when no `key:` is given, by walking the environment
  variable names listed in the models.dev registry. So `LLM.openai`
  works without an explicit key as long as `OPENAI_API_KEY` (or one of
  the registry's alternative names) is set in the environment. A
  missing key raises `ArgumentError`.

* **cli: auto-discover credentials and support Bedrock** <br>
  `bin/llm.rb` now resolves the provider through the `LLM` factory
  methods instead of mapping environment variable names directly, so it
  picks up Bedrock (all three AWS credentials) and relies on the same
  automatic key discovery as the library. The CLI also always starts
  now: without arguments it falls back to `ollama` or `llamacpp`. A
  provider whose credentials are not set exits with status 1.

* **cli: add `-c` and `-n` switches** <br>
  `bin/llm.rb` now accepts a `-c STRATEGY` switch to choose the
  concurrency strategy used for tool calls (`thread`, `async`, `fork`,
  or any of the other strategies) and a `-n TRANSPORT` switch to choose
  the HTTP transport (`net-http`, `net-http-persistent`, or `curb`),
  both forwarded to the session's agent and provider.

* **context: keep runtime parameters from reaching the provider** <br>
  [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
  now strips its runtime-only parameters (`guard`, `retry_budget`,
  `concurrency`, `transformer`, and `compactor`) before merging params
  into a provider request, so they can never cross the context-provider
  boundary and risk an API-level error.

* **add `retry_budget` support for rate-limited requests** <br>
  [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
  now accepts a `retry_budget:` that automatically sleeps and retries a
  rate-limited request up to the given number of times before raising
  `LLM::RateLimitError`. Each retry sleeps a growing interval (2s, 4s,
  6s, ...) and notifies the stream through
  [`LLM::Stream#on_rate_limit`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_rate_limit-instance_method).
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
  enables a budget of 5 by default, while a raw context disables it (0)
  unless configured.

* **add `LLM::Usage.zero`** <br>
  Add
  [`LLM::Usage.zero`](https://r.uby.dev/api-docs/llm.rb/LLM/Usage.html#zero-class_method)
  as a zero-valued usage object. `LLM::Context#usage`, `LLM::Agent#usage`,
  and the ActiveRecord and Sequel wrappers now return `LLM::Usage` objects
  instead of `LLM::Object` when no provider usage has been recorded yet.

* **add `LLM::Context#context_usage` and `LLM::Agent#context_usage`** <br>
  Add
  [`LLM::Context#context_usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#context_usage-instance_method)
  and
  [`LLM::Agent#context_usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#context_usage-instance_method),
  which return the fraction of the model's context window currently used as
  a `Rational` (for example `Rational(100, 10_000)`), or `nil` when the used
  amount or the window size is unknown. The REPL status bar now renders this
  fraction instead of computing the remainder from raw token counts.

* **add `LLM::Context#context_used` and `LLM::Agent#context_used`** <br>
  Add
  [`LLM::Context#context_used`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#context_used-instance_method)
  and
  [`LLM::Agent#context_used`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#context_used-instance_method),
  which return the live context size (in tokens) of the most recent
  assistant message, or `nil` when no assistant message has a recorded token
  usage. This fills the gap left after `token_usage` became accumulative and
  no longer represented a single turn, so callers can read how much of the
  context window has been used without walking the messages themselves.

### Provider

* **add `LLM::Provider#registry`** <br>
  Add [`LLM::Provider#registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#registry-instance_method),
  which returns the provider's model registry. `LLM::Context#registry`
  and `LLM::Agent#registry` now delegate to their underlying provider
  instead of looking it up on their own.

* **add `LLM::Alibaba` for Alibaba Cloud Model Studio** <br>
  [`LLM::Alibaba`](https://r.uby.dev/api-docs/llm.rb/LLM/Alibaba.html)
  is a new provider that talks to
  [Alibaba Cloud Model Studio](https://www.alibabacloud.com/help/en/model-studio/models)
  through its OpenAI-compatible API, including the Qwen3 family of
  models. Create an instance with
  [`LLM.alibaba`](https://r.uby.dev/api-docs/llm.rb/LLM.html#alibaba-class_method),
  also aliased as `LLM.aliyun`, which accepts the same `key:`, `host:`,
  and `base_path:` options as the OpenAI provider. The provider defaults
  to the `deepseek-v4-flash-0731` model and supports chat completions,
  streaming, tool calls, and structured output through the shared
  OpenAI-compatible path; image, audio, moderation, responses, and
  vector store endpoints raise `NotImplementedError`. Model metadata
  ships in `data/alibaba.json` for the registry.

* **alibaba: support structured outputs via `json_object`** <br>
  [`LLM::Alibaba`](https://r.uby.dev/api-docs/llm.rb/LLM/Alibaba.html)
  now supports structured output through a shared `json_object` fallback,
  since Alibaba models do not support `json_schema` natively. The schema is
  described in an injected system message that also satisfies the
  "messages must contain the word json" requirement. The same shared
  fallback now also backs DeepSeek.

* **alibaba: default to the pay-as-you-go host** <br>
  The default
  [`LLM::Alibaba`](https://r.uby.dev/api-docs/llm.rb/LLM/Alibaba.html)
  host is now `dashscope-intl.aliyuncs.com`. Override it globally with
  the `DASHSCOPE_API_HOST` environment variable, or per instance with
  `LLM.alibaba(host: ...)`, for example to point at a Token Plan
  endpoint.

* **alibaba: use `DASHSCOPE_API_KEY` as the default key env var** <br>
  [`LLM::Alibaba`](https://r.uby.dev/api-docs/llm.rb/LLM/Alibaba.html)
  now discovers its API key from `DASHSCOPE_API_KEY` instead of
  `ALIBABA_API_KEY`, following the models.dev registry convention.

* **alibaba: raise `LLM::InsufficientQuotaError` for exhausted quota** <br>
  Add
  [`LLM::InsufficientQuotaError`](https://r.uby.dev/api-docs/llm.rb/LLM/InsufficientQuotaError.html),
  a subclass of `LLM::RateLimitError`, for when a provider reports a
  tokens-per-minute (TPM) quota limit.
  [`LLM::Alibaba`](https://r.uby.dev/api-docs/llm.rb/LLM/Alibaba.html)
  now raises it when Alibaba responds with an `insufficient_quota`
  error. Since it subclasses `RateLimitError`, quota errors are retried
  like other rate limits.

* **bedrock: auto-discover AWS credentials from the environment** <br>
  [`LLM.bedrock`](https://r.uby.dev/api-docs/llm.rb/LLM.html#bedrock-class_method)
  now infers its credentials from the `AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION` environment variables when
  they are not passed explicitly, matching the other cloud providers. A
  missing key raises `ArgumentError`.

* **add `LLM::Bedrock#key?`** <br>
  Add
  [`LLM::Bedrock#key?`](https://r.uby.dev/api-docs/llm.rb/LLM/Bedrock.html#key%3F-instance_method),
  which overrides the superclass method to check all three Bedrock
  credentials (`access_key_id`, `secret_access_key`, and `region`)
  instead of a single API key.

### Function

* **make `Sequential::Group` abide by the `LLM::Function::Group` contract** <br>
  [`LLM::Function::Sequential::Group`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Sequential/Group.html)
  now receives an array of
  [`LLM::Function::Sequential::Task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Sequential/Task.html)
  objects instead of raw `LLM::Function` objects, matching the interface
  shared by every other concurrency strategy.
  [`LLM::Function::Array#task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Array.html#task-instance_method)
  wraps each function as a `Sequential::Task` before constructing the
  group, and the group delegates `spawn`, `alive?`, and `wait` to those
  tasks. This fixes `Sequential::Group#alive?`, which always returned
  `false`, and restores guard handling for sequential execution by
  honoring the shared `guarded:` option on `Sequential::Task`.

* **function: redirect output streams in `:fork` tool processes** <br>
  The `:fork` concurrency strategy (via
  [`LLM::Function::Fork::Task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Fork/Task.html))
  now redirects the child process's `$stdout` and `$stderr` to
  `File::NULL`, so a forked tool can no longer clobber the parent
  terminal, for example by blanking the curses REPL display. A tool that
  genuinely needs the terminal can still reopen `/dev/tty`; the file
  descriptor stays available to the child.

### Fix

* **a2a: fix a typo in the HTTP transport** <br>
  Fix a bug in
  [`LLM::A2A::Transport::HTTP`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A/Transport/HTTP.html)
  where the constructor read `uri.port` instead of `@uri.port`, which
  crashed the program whenever
  [`LLM::A2A.rest`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A.html#rest-class_method)
  or
  [`LLM::A2A.jsonrpc`](https://r.uby.dev/api-docs/llm.rb/LLM/A2A.html#jsonrpc-class_method)
  was used. The transport now reads the port from the parsed `@uri`.

* **openai: report usage for streamed completions requests** <br>
  Fix a bug in the OpenAI completions path where `params[:stream]` was
  checked after it had been deleted from the params hash, so the check
  always evaluated to `false`. The fix checks the resolved stream's
  `enabled?` instead, so `stream_options: {include_usage: true}` is
  added to streamed requests and API usage is reported back to the
  caller.

* **curb: read the stream body and resolve streaming requests** <br>
  Fix two bugs in [`LLM::Transport::Curb`](https://r.uby.dev/api-docs/llm.rb/LLM/Transport/Curb.html)
  that left the `curb` transport unusable. The request body setter now
  reads a streaming request's body stream into a string (dropping the
  chunked transfer header, which curb replaces with a content length),
  and the result builder now accumulates the response body from the
  `on_body` callback instead of leaving it empty.

* **cli: handle errors in `main`** <br>
  Wrap all of `bin/llm.rb`'s `main` method in error handling: an
  interrupted session exits gracefully with `Bye!`, an explicit provider
  is passed the resolved transport, and any unexpected error prints a
  formatted diagnostic with a link to issue tracking before exiting.

* **cli: persist the session mapping file** <br>
  Fix a bug where `bin/llm.rb` saved the session file at
  `~/.llm.rb/<provider>/<uuid>.json` but never wrote the updated
  working-directory mapping back to `~/.llm.rb/<provider>.json`. The
  mapping file is now written whenever a new session is registered.

* **context: aggregate usage across all assistant messages** <br>
  [`LLM::Context#usage`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#usage-instance_method)
  now sums token usage across every assistant message in the conversation
  instead of returning only the first message's usage.
  [`LLM::Cost.from`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html)
  now subtracts reasoning tokens from the output total and cache-read
  tokens from the input total before pricing, and prices reasoning tokens
  with the model's reasoning rate when one is available.

### Repl

* **draw a top chrome row with the cwd and active model** <br>
  The curses-based REPL now draws a white-on-blue row at the very top of
  the screen showing the current working directory on the left and the
  active model on the right. The row is drawn above the transcript and
  uses a new blue status-bar color pair.

* **redraw the window on resize** <br>
  The curses-based REPL now handles the terminal resize signal
  (`KEY_RESIZE`) while reading input, clearing and redrawing the entire
  window so the layout stays aligned after the terminal is resized.

* **hide the cursor until the window is ready** <br>
  Fix a visual glitch where the curses-based REPL showed the cursor at
  position 0,0 at startup and then jumped it to the input area once the
  window was drawn. The cursor is now hidden until the input field has
  been drawn and the cursor can be placed directly into it.

* **collapse the cost to two decimal places** <br>
  [`LLM::Cost#to_s`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html)
  now renders the total cost with two decimal places (for example
  `$0.01`), so the REPL status bar shows a compact cost estimate instead
  of a long run of digits.

* **add auto-complete ability for commands** <br>
  [`LLM::Repl::Command`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl/Command.html)
  subclasses can now override a `complete` method to autocomplete their
  arguments. The method receives the command's parameters as keyword
  arguments, with the non-nil keyword being the active fragment, and
  returns candidate completions. Repeated TAB presses cycle through the
  candidate list.

* **add `LLM::Repl#model` and `LLM::Repl#model=`** <br>
  [`LLM::Repl`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl.html#model-instance_method)
  now tracks the active model in its own `model` attribute, seeded from
  the wrapped agent's model. The status bar reads the model through the
  repl instead of the agent, so the model can be switched within a
  session.

* **add `/model` command** <br>
  A new `/model <name>` command switches the active model within a
  single REPL session. Its argument auto-completes through the
  text-to-text models in the registry.

* **repl: restrict autocomplete to text-to-text models** <br>
  The `/model` command's argument auto-complete now suggests only
  text-to-text models, so embedding and other non-chat models are
  left out of the completion list.

* **repl: highlight GitHub-flavored codeblocks** <br>
  The curses-based REPL now parses the GitHub-style ``` fences that
  models commonly emit as real code blocks. Kramdown's native fenced-code
  syntax uses `~~~`, so the ``` fences were previously parsed as inline
  code spans. The language name is now shown in bold white above the code,
  which renders in green.

* **repl: fix a scroll render artifact** <br>
  Fix a bug where scrolling upward could leave a piece of text just
  above the status row as a render artifact. The row above the status
  row is now cleared on every buffer render.

* **repl: add a buffer row below the blue status bar** <br>
  The curses-based REPL buffer now starts with an empty row below the
  blue status bar, improving the visual spacing of the first exchange
  in the chat.

* **repl: pin `curses` and `kramdown` to tested versions** <br>
  The REPL now pins `curses` to `~> 1.6` and `kramdown` to `~> 2.5`
  through `LLM.require`, so it loads gem versions known to have been
  tested instead of whatever happens to be installed.

### Skills

* **skills: append `-skill` to the generated tool name** <br>
  A skill is now exposed as a tool named `"<skill>-skill"` instead of
  just the skill's name, so a skill like `weather` that also uses a tool
  named `weather` no longer collides with it (or a same-named global
  tool) in the tool registry.

* **skills: add `LLM::Stream` skill lifecycle callbacks** <br>
  Add
  [`LLM::Stream#on_skill_call`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_skill_call-instance_method)
  and
  [`LLM::Stream#on_skill_return`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_skill_return-instance_method),
  which are called before a skill's sub-agent runs and after it finishes.
  `on_skill_return` receives the `LLM::Agent` sub-agent that ran the skill
  along with the resulting `LLM::Response`, so a stream can inspect the
  sub-agent's conversation, tally its usage, or add a verification step. A
  stream can use the two callbacks to know when a skill sub-agent is
  running.

### Registry

* **add `LLM::Registry::Model` as a comparable model wrapper** <br>
  Add [`LLM::Registry::Model`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html),
  a wrapper around a model's registry metadata (pricing, limits,
  capabilities, and modalities). Models are comparable by price, so
  `models.sort` orders them from cheapest to most expensive. The class
  exposes predicate helpers such as `tool_call?`, `reasoning?`,
  `structured_output?`, `open_weights?`, `text?`, `image?`, `audio?`,
  `pdf?`, and `video?`, plus `input_cost`, `output_cost`, and
  `context_window` accessors.

* **gemspec: bundle the deepdive guide from `docs/`** <br>
  The gemspec now packages the deepdive guide from `docs/deepdive.md`
  and `docs/deepdive/*/*.md` after the deepdive sources moved from
  `resources/` to `docs/`, so the full guide ships with the gem.

* **make `LLM::Registry#models` return model objects** <br>
  [`LLM::Registry#models`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#models-instance_method)
  now returns a list of
  [`LLM::Registry::Model`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html)
  objects instead of model name strings. Use the new
  [`LLM::Registry#keys`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry.html#keys-instance_method)
  method to get the model names.

* **refresh DeepInfra model metadata** <br>
  Update `data/deepinfra.json` with current pricing for the DeepSeek
  V4, DeepSeek-V3, DeepSeek-R1-0528, and Kimi-K3 models, and mark
  `structured_output` support for one model.

## v14.0.0

Changes since `v13.1.0`.

This release replaces the `transformer=` setter with the new
`LLM::Transformer` class hierarchy, refactors guards into the
`LLM::Guard` superclass with per-tool-call interception, and replaces
the agent `tool_attempts` parameter with the `tool_budget` class DSL.
It also adds the Moonshot (Kimi) provider, the `LLM::Tool.set`
bulk-assignment DSL, a `LLM::Function#return` shorthand, and a wide
range of REPL improvements.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `ctx.transformer = MyTransformer` | `LLM::Context.new(transformer: MyTransformer)` |
| `transformer.call(ctx, prompt, params)` | `transformer.call(message:, **opts)` |
| `~/.llm.rb/session.json` (shared across providers) | `~/.llm.rb/<provider>/<uuid>.json` (scoped per provider and directory) |
| `agent.talk(tool_attempts: 25)` | `set :tool_budget => 50` (disabled by default) |
| `LLM::LoopGuard` | `LLM::Guard::Loop` |
| `guard: true` / `ctx.guard = MyGuard` | `guard: MyGuard, guard_options: {}` |
| `guard.call(ctx)` (warning string) | `guard.call(function:)` (`LLM::Function::Return` or nil) |
| `LLM::GuardError` | `"guard_error"` |

* **replace the transformer setter with `LLM::Transformer`** <br>
  The previous `transformer=` setter and 3-argument
  `call(ctx, prompt, params)` interface on `LLM::Context` have been
  replaced by the new
  [`LLM::Transformer`](https://r.uby.dev/api-docs/llm.rb/LLM/Transformer.html)
  class interface. Configure a transformer class through `transformer:`
  and options through `transformer_options:` instead.

* **cli: scope session persistence per provider and directory** <br>
  `bin/llm.rb` no longer shares a single session file between providers.
  Each provider now has a `~/.llm.rb/<provider>.json` file that maps the
  current working directory to a UUID-scoped session file under
  `~/.llm.rb/<provider>/<uuid>.json`, so sessions are scoped to both the
  provider and the directory they were started in.

* **cli: harden the executable against bad inputs** <br>
  `bin/llm.rb` now prints an error message followed by the help menu and
  exits with status 1 when the `-p` switch is given without an argument or
  when an unknown option is passed. Previously unknown options produced a
  warning but the run continued. The session-file lookup also no longer
  rewrites `~/.llm.rb/<provider>.json` when it already exists.

* **agent: replace `tool_attempts` with the `tool_budget` class DSL** <br>
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#tool_budget-class_method)
  replaces the `tool_attempts` parameter with a `tool_budget` class DSL
  (`tool_budget { 50 }`) that caps the number of tool calls allowed in a
  single turn. Once the budget is spent, the agent sends an in-band
  advisory message back through the model telling it to solve the problem
  with fewer tool calls.
  <br><br>
  The feature is now disabled by default; the old `tool_attempts`
  parameter defaulted to 25, which long-horizon agents could easily
  exhaust in a single turn.

* **guard: replace `LLM::LoopGuard` with the `LLM::Guard` class hierarchy** <br>
  [`LLM::Guard`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html)
  is a new superclass for context-level supervisors, with
  [`LLM::Guard::Loop`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard/Loop.html)
  (replacing `LLM::LoopGuard`) and
  [`LLM::Guard::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard/Null.html)
  as the built-in implementations.
  [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
  now accepts `guard:` (a guard class defaulting to `LLM::Guard::Null`)
  and `guard_options:` (a hash forwarded to the guard's `call` method),
  matching the transformer and compactor interfaces. The old boolean and
  hash forms of `guard` and the `guard=` setter are removed. `LLM::Agent`
  enables `LLM::Guard::Loop` by default.

* **guard: block individual tool calls instead of the whole batch** <br>
  [`LLM::Guard#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html#call-instance_method)
  now receives the pending `function:` and returns an
  [`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
  (or nil) instead of a warning string for the entire batch, so a guard
  can block a single tool call while the rest of the batch still
  executes. Custom guards that implemented the old `call(ctx)`
  warning-string interface must be updated to return a
  `LLM::Function::Return` instead.

* **errors: drop `LLM::GuardError`** <br>
  Remove `LLM::GuardError`. The constant was never raised as an
  exception; it only named the in-band error type for guarded tool
  returns. Guarded tool returns now use the string `"guard_error"` as
  their error type.

### Core

* **add `LLM::Provider#build_messages` for assembling outgoing messages** <br>
  [`LLM::Provider#build_messages`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html#build_messages-instance_method)
  normalizes a prompt into `LLM::Message` objects and prepends the existing
  history, replacing the per-provider `build_complete_messages`
  implementation. The method is idempotent: prompts that are already
  [`LLM::Message`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html)
  instances or arrays of messages are returned as-is.

* **copy the `params` hash in `LLM::Context` and `LLM::Agent`** <br>
  [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html) and
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html) now copy
  the `params` hash in their constructors before mutating it, leaving the
  caller's hash untouched. Previously the constructors deleted keys from
  the caller's hash in place.

* **gemspec: ship the deepdive sub-files in the gem** <br>
  The gemspec now includes `resources/deepdive/*/*.md` in the gem
  package, so the full deepdive guide (fundamentals, advanced,
  protocols, and everything-else chapters) is available after
  installation.

* **add short aliases to `LLM::Cost`** <br>
  [`LLM::Cost`](https://r.uby.dev/api-docs/llm.rb/LLM/Cost.html) now
  offers short aliases for its cost accessors: `input`, `output`,
  `input_audio`, `output_audio`, `input_image`, `cache_read`,
  `cache_write`, and `reasoning`. Each alias matches the key used by
  `#to_h`, so `cost.input` reads the same value as `cost.input_costs`.

### Provider

* **add `LLM::Moonshot` for the Moonshot AI provider** <br>
  [`LLM::Moonshot`](https://r.uby.dev/api-docs/llm.rb/LLM/Moonshot.html)
  is a new provider that talks to
  [Moonshot AI](https://platform.moonshot.ai) through its
  OpenAI-compatible Kimi API. Create an instance with
  [`LLM.moonshot`](https://r.uby.dev/api-docs/llm.rb/LLM.html#moonshot-class_method),
  which accepts the same `key:`, `host:`, and `base_path:` options as the
  OpenAI provider. The provider defaults to the `kimi-k3` model and
  supports chat completions, streaming, tool calls, and structured output
  through the shared OpenAI-compatible path; image, audio, moderation,
  responses, and vector store endpoints raise `NotImplementedError`.
  Model metadata ships in `data/moonshot.json` for the registry.

### Transformer

* **add `LLM::Transformer` for rewriting messages before they reach the provider** <br>
  [`LLM::Transformer`](https://r.uby.dev/api-docs/llm.rb/LLM/Transformer.html)
  is a new superclass for message transformers. A transformer is bound to a
  context and rewrites a single message before it is sent to the provider,
  which makes it possible to redact personal information or rewrite any
  message before it goes out over the wire. Each subclass implements
  `call(message:, **opts)` and returns the message to send, either by
  mutating it in place or returning a new one.
  [`LLM::Transformer::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Transformer/Null.html)
  is a no-op transformer used as the default.

* **hook the transformer API into `LLM::Context`** <br>
  [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html) now
  accepts `transformer:` (a transformer class defaulting to
  `LLM::Transformer::Null`) and `transformer_options:` (a hash forwarded to
  the transformer's `call` method). The transformer runs on the most recent
  message in both chat and responses turns.
  [`LLM::Stream#on_transform`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_transform-instance_method)
  and
  [`LLM::Stream#on_transform_finish`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_transform_finish-instance_method)
  now receive the transformer instance as their single argument.

### Tool

* **add `LLM::Tool.set` for bulk-assigning tool properties** <br>
  [`LLM::Tool.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#set-class_method)
  accepts a hash of `name`, `description`, `parameters`, `required`, and
  `defaults` to configure a tool subclass in a single call. Parameters are
  defined as tuples of `[name, type, description, options]`, matching the
  same interface as the existing `parameter` DSL. Unknown keys raise
  `KeyError`.

### Function

* **add `LLM::Function#return` for building tool returns** <br>
  [`LLM::Function#return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#return-instance_method)
  returns an
  [`LLM::Function::Return`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Return.html)
  built from the function's own id and name, using the given hash as its
  value. It is a shorthand mainly useful inside a
  [`LLM::Guard`](https://r.uby.dev/api-docs/llm.rb/LLM/Guard.html)
  subclass and is defined via `define_method` because `return` is a Ruby
  keyword.

### Guard

* **run the guard for streamed tool calls** <br>
  Fix a gap where the guard was not consulted when a tool call was queued
  while a response was still streaming. The guard is now stamped onto the
  functions a context binds, so it runs wherever a task is spawned,
  including tool calls queued from a stream. A blocked call yields its
  `guard_error` return without executing.

### Agent

* **add `LLM::Agent#compacted?`** <br>
  [`LLM::Agent#compacted?`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#compacted%3F-instance_method)
  delegates to the wrapped
  [`LLM::Context#compacted?`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#compacted%3F-instance_method)
  and reports whether the conversation has been compacted, so callers
  can detect when history was trimmed.

### Change

* **openai: default to `gpt-5.6-luna`** <br>
  The default OpenAI chat model has changed from `gpt-5.4-mini` to
  `gpt-5.6-luna`. The new model is OpenAI's fastest and most affordable
  option, matching the kind of default llm.rb aims for.

### Repl

* **show an unknown context state after `/compact`** <br>
  After running `/compact`, the REPL status line now renders `Context
  compacted` and the context-usage bar shows `???` instead of a percentage,
  because the used context is unknown until the next response.

* **land on a blank line after Ctrl+N at the end of history** <br>
  When recalling history with Ctrl+P and Ctrl+N, Ctrl+N at the last item
  now advances to a blank line so you can start typing new input, instead
  of staying stuck on the last item in history (the previous behavior).
  Recalling with Ctrl+P or Ctrl+N also no longer overwrites the input when
  there is no history to show.

* **restore history wrap for Ctrl+P and Ctrl+N** <br>
  Fix a regression where Ctrl+P and Ctrl+N recalled history text without
  reflowing it into rows, so recalled lines wider than the terminal were
  clipped. Recalled text now flows through the same word-wrap path as
  typed input and wraps at the terminal width.

* **restore Ctrl+D deletion across rows** <br>
  Fix a bug where Ctrl+D at the end of an input row was a no-op, so
  multiline input could not be joined by deleting a row break. Deleting
  at the end of a row now consumes the break and pulls the next row up,
  restoring the split space so merged words do not run together.

* **center the buffer with 20% gutters** <br>
  The curses-based REPL now centers
  [`LLM::Repl::Buffer`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl/Buffer.html)
  in a content area that is 60% of the terminal width, with an unused 20%
  gutter on each side. The drawing area is based on the available rows and
  columns instead of a fixed 80-column width, and `Buffer#wrap` now
  hard-breaks words that overflow the width onto the next row, fixing a
  bug where a word could be cut off between rows.

* **apply markdown to previous messages** <br>
  The curses-based REPL now renders every message in the buffer with
  markdown styling, including messages that were already present when
  the session started or restored from disk. Previously only newly
  streamed responses were styled; older messages fell back to plain
  text.

* **add `LLM::Repl#sender` for the user label** <br>
  [`LLM::Repl#sender`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl.html#sender-instance_method)
  returns the label used for user messages in the curses-based REPL. It
  defaults to `"You"` (previously `"user"`), and the buffer layout now
  places each label on its own line followed by the message content and a
  blank line.

* **add `LLM::Repl::Color` for coloring the curses UI** <br>
  Add
  [`LLM::Repl::Color`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl/Color.html)
  as a new module that returns Curses color bitmasks. `Color.enable`
  initializes 8 color pairs, and methods like `Color.blue` return the
  corresponding `Curses.color_pair(X)` bitmask, which can be bitwise
  OR'ed with other attributes such as `Curses::A_BOLD`. User labels in
  the REPL are now rendered in blue instead of plain bold text.

* **split on words rather than characters** <br>
  `LLM::Repl::Buffer#wrap` now breaks text on word boundaries instead of
  wrapping one character at a time. A word that does not fit on the
  current row moves to the next, and only a single word longer than the
  whole width is hard-broken, so text is never clipped by the window.

* **render kramdown typographic symbols and smart quotes** <br>
  Fix a bug where certain character sequences such as `...` were not
  rendered at all in the curses-based REPL. Kramdown parses them into
  `:typographic_sym` and `:smart_quote` nodes, which previously fell
  through to the children clause and were dropped. The markdown renderer
  now maps them to their unicode equivalents: ellipsis, en and em
  dashes, guillemets, and single and double quotation marks.

* **apply colors to the markdown renderer** <br>
  The curses-based REPL now renders markdown with the `LLM::Repl::Color`
  palette: headers and strong text in white, code spans and code blocks
  in green, and links in underlined green, on the black background.
  Previously markdown styling used bold, underline, and reverse video
  attributes only.

* **wrap the input line at word boundaries** <br>
  The curses-based REPL input line now wraps words whole onto the next
  row at the terminal width instead of cutting them in half. A word that
  does not fit on the current row moves to the next row, and only a
  single word longer than the whole width is hard-broken, so typed text
  is never clipped by the window.

* **distinguish the connecting and thinking status bar phases** <br>
  The curses-based REPL status bar now shows `Connecting • Esc to
  cancel` while the model is establishing a connection, then switches
  to `Thinking • Esc to cancel` once a tool call or text fragment
  arrives on the stream. Active tool calls appear in the status bar
  with a lambda indicator.

* **add emoji to the status bar phases** <br>
  The curses-based REPL status bar now uses emoji to identify each
  phase at a glance: a globe (`🌐`) while the model is connecting, and
  a brain (`🧠`) while it is thinking. The text after the emoji still
  reads `Connecting • Esc to cancel` and `Thinking • Esc to cancel`
  respectively.

* **render the status bar with color and attributes** <br>
  The curses-based REPL status bar now supports colored and attributed
  status text, so the lambda indicator for active tool calls is drawn
  in bold red.

### Registry

* **refresh model metadata across providers** <br>
  Update `data/*.json` files with current provider model listings and
  pricing. Remove the deprecated Claude Opus 4.1 entries from the
  Anthropic registry, add `Qwen/Qwen3.8-Max` to DeepInfra, and add a
  `low` reasoning-effort option to DeepSeek.

## v13.1.0

Changes since `v13.0.0`.

This release adds `LLM::Agent` class DSL attributes (`path`, `description`),
extends skills with file-path loading and the `tools: all` directive, adds new
built-in tools (`LLM::Tool::Ruby`, `LLM::Tool::EditFile`), introduces the
`LLM::Tracer::PrettyLogger` for human-readable tracing, renames `Transcript`
to `Buffer` across the REPL, ships a `bin/llm.rb` CLI entry point, and fixes
several agent and tool bugs around persistence, interruption, and naming.

### Core

* **add post install message with deepdive link** <br>
  The gemspec now includes a `post_install_message` that points users to
  the deepdive guide at `https://r.uby.dev/llm/deepdive` after installation,
  making it easier for new users to discover the project documentation.

### Agent

* **add `description` class DSL and instance method** <br>
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html) now
  has a `description` class DSL (`description "release engineer"`) and a
  corresponding `#description` instance method. The description is an
  optional self-documenting string that serves as a brief summary of the
  agent's purpose. It can be set via the class DSL,
  `LLM::Agent.set(description: ...)`, or `LLM::Agent.new(description: ...)`.

* **add `path` class DSL and instance method** <br>
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html) now
  has a `path` class DSL (`path "contexts/admin.json"`) and a
  corresponding `#path` instance method. When a path is set, the agent
  automatically restores its conversation history from that file on
  initialization and saves it back after each `talk` or `ask` turn,
  making session persistence across process restarts transparent.

### Skills

* **accept a path to a markdown file** <br>
  [`LLM::Skill.load`](https://r.uby.dev/api-docs/llm.rb/LLM/Skill.html#load-class_method)
  now accepts a path to a markdown file in addition to a directory path.
  When given a file path, the file is read directly instead of looking for
  a `SKILL.md` inside a directory. This makes it possible to load a single
  markdown file as a skill without placing it in a dedicated directory.

* **extend with `all` keyword for loading the full tool registry** <br>
  `LLM::Skill` now supports `tools: all` (or `tools: "*"`) in the frontmatter
  to load all tools from the global
  [`LLM::Tool.registry`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#registry-class_method).
  Previously, the `tools:` frontmatter only accepted `inherit`, an array of tool
  names, or nothing. The new `all` keyword makes it possible to give a skill
  access to every registered tool without listing them individually.

### Tools

* **add `LLM::Tool::Ruby` for executing Ruby code in a subprocess** <br>
  [`LLM::Tool::Ruby`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Ruby.html)
  is a new built-in tool that runs a string of Ruby code in a separate
  Ruby process with a configurable timeout (default 15s). The code runs
  in an isolated address space unaware of its parent, making it useful
  for safe(ish) dynamic code execution. It must be required explicitly
  with `require "llm/tools/ruby"` and requires the `test-cmd.rb` gem.

* **rename `LLM::Tool::SwapText` to `LLM::Tool::EditFile`** <br>
  The `SwapText` tool has been renamed to
  [`LLM::Tool::EditFile`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/EditFile.html)
  to better match the naming of sibling tools (`ReadFile`, `WriteFile`).
  The old `require "llm/tools/swap_text"` path no longer exists; use
  `require "llm/tools/edit-file"` instead.

### Tracer

* **add `LLM::Tracer::PrettyLogger` for human-readable tracing** <br>
  [`LLM::Tracer::PrettyLogger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/PrettyLogger.html)
  is a new tracer that writes human-readable request and tool-call logs to a
  console or file. Unlike the structured JSON output of
  `LLM::Tracer::Logger`, the pretty logger emits single-line entries with
  inline context, making it easier to follow agent activity at a glance.
  It writes to `$stderr` by default and accepts an `io:` option for file
  output.

### Repl

* **rename `LLM::Repl::Transcript` to `LLM::Repl::Buffer`** <br>
  `LLM::Repl::Transcript` has been renamed to
  [`LLM::Repl::Buffer`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl/Buffer.html)
  to better reflect its role as a conversation state manager. The old
  `start` and `finish` methods have been renamed to `open` and `close`
  respectively. The public accessor on
  [`LLM::Repl`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl.html) has been
  renamed from `transcript` to `buffer`.

* **add `write_message` for formatted message writing** <br>
  [`LLM::Repl::Buffer#write_message`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl/Buffer.html#write_message-instance_method)
  and
  [`LLM::Repl#write_message`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl.html#write_message-instance_method)
  provide a convenience method that takes a username and content string,
  formatting the output with a bold `user:` label and a trailing newline.
  This is simpler than the equivalent sequence of `write` calls.

* **add `Command#write_message` and refactor `Command#write`** <br>
  [`LLM::Command#write_message`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl/Command.html#write_message-instance_method)
  provides a convenience method that takes a username and content string,
  matching the same interface on `LLM::Repl` and `LLM::Buffer`. The
  `Command#write` method is now implemented on top of `write_message`,
  always prefixing output with `command(<name>): `. The `who:` keyword
  argument previously accepted by `write` has been removed; use
  `write_message` instead.

* **display pre-existing agent messages when the repl starts** <br>
  When
  [`LLM::Agent#repl`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#repl-instance_method)
  starts, any messages already in the agent's buffer are now rendered
  in the REPL window. Previously the REPL started with an empty
  transcript even when the agent carried prior conversation history,
  making it harder to resume a session. Tool-call and tool-return
  messages are skipped to avoid visual noise.

### CLI

* **add `bin/llm.rb` for launching the REPL from the command line** <br>
  A new executable script (`bin/llm.rb`) provides a convenient way to start
  an interactive REPL session directly from the terminal. It auto-detects
  the provider from environment variables like `OPENAI_API_KEY`, supports
  a `-p PROVIDER` flag for explicit provider selection, a `-t` flag for
  temporary (non-persistent) sessions, and `-h` for help. Sessions are
  automatically saved to `~/.llm.rb/` by default.

### Fix

* **agent: fix `path` restore on first run** <br>
  Fix a bug where [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
  called `@ctx.restore(path:)` even when the path's file did not exist.
  The fix checks `File.readable?(@path)` before attempting to restore,
  so the agent starts with a blank conversation on first use instead of
  failing with a file-not-found error.

* **tools: re-raise `LLM::Interrupt` to abort the turn** <br>
  [`LLM::Tool::Git`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git.html),
  [`LLM::Tool::Mkdir`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Mkdir.html),
  [`LLM::Tool::Rg`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Rg.html),
  [`LLM::Tool::Ruby`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Ruby.html),
  and
  [`LLM::Tool::Shell`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Shell.html)
  now re-raise `LLM::Interrupt` after killing their running command. The
  previous behavior rescued the interrupt and killed the child process but
  let the turn continue, which meant a cancelled tool call did not abort
  the conversation turn. Re-raising ensures the entire turn is interrupted.

* **tools: rescue `LLM::Interrupt` in shell-based tools** <br>
  [`LLM::Tool::Shell`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Shell.html),
  [`LLM::Tool::Git`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git.html),
  [`LLM::Tool::Mkdir`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Mkdir.html),
  and
  [`LLM::Tool::Rg`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Rg.html)
  now rescue `LLM::Interrupt` and kill their running command, preventing
  orphaned child processes when a tool is interrupted during execution.

* **agent: fix default name derivation** <br>
  Fix a bug where `LLM::Agent` used without a subclass derived its default
  name as `"l-lm-agent"` instead of `"agent"`. The fix replaces the
  regex-based parameterization with a pattern that correctly handles
  single-word class names and multi-word namespaced names.

* **function: `#params` always returns an `LLM::Object`** <br>
  [`LLM::Function#params`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#params-instance_method)
  now always returns an `LLM::Object` representing the function's parameter
  schema. Previously it returned `nil` when a function defined no parameters,
  forcing every caller to guard against `nil`. All provider adapters now use
  `fn.params.to_h` instead of `fn.params || {type: "object", properties: {}}`.

## v13.0.0

v13.0.0 is released under the MIT license. Commercial, personal,
educational, and all other uses are permitted under the standard
MIT terms.

Seven breaking changes. Concurrency strategies have been renamed
(`:call` → `:sequential`, `:task` → `:async`), `spawn` is now
`task`, and the `:async` strategy has been rebuilt from the ground
up. It no longer blocks and now supports interruption. The compactor
has been refactored into pluggable strategies. Interruption is now
reliable across all six concurrency backends. The `functions` and
`functions?` methods have been renamed to `pending_functions` and
`pending_functions?`.

### Migration from v12.6.0

| Old | New |
|-----|-----|
| `fn.spawn(:call)` | `fn.task(:sequential)` |
| `fn.spawn(:task)` | `fn.task(:async)` |
| `ctx.wait(:call)` | `ctx.wait(:sequential)` |
| `agent.concurrency :task` | `agent.concurrency :async` |
| `LLM::Function::FiberGroup` | `LLM::Function::Fiber::Group` |
| `LLM::Function::CallGroup` | `LLM::Function::Sequential::Group` |
| `LLM::Function::TaskGroup` | `LLM::Function::Async::Group` |
| `Compactor.new(model:, token_threshold:)` | `Compactor::Truncate.new(ctx)` |
| `on_compaction(ctx, compactor)` | `on_compaction(compactor)` |
| `ctx.functions` / `ctx.functions?` | `ctx.pending_functions` / `ctx.pending_functions?` |
| `agent.functions` / `agent.functions?` | `agent.pending_functions` |

### Breaking

* **rename `LLM::Function#spawn` as `LLM::Function#task`** <br>
  [`LLM::Function#task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#task-instance_method)
  (previously `spawn`) now consistently returns a
  [`LLM::Function::Task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html)
  object that can be spawned, waited on, and passed to
  [`LLM::Function::Group`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Group.html).
  The old implementation alternated between spawning immediately or
  returning a raw thread or fiber.

* **rename concurrency strategies (`:call` → `:sequential`,**
  **`:task` → `:async`)** <br>
  The `:call` concurrency strategy is now `:sequential`, and the `:task`
  strategy is now `:async`.
  [`LLM::Agent.concurrency`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#concurrency-class_method),
  [`LLM::Context#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#wait-instance_method),
  `LLM::Function::Array#task`, and
  [`LLM::Function#task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#task-instance_method)
  all accept the new names. The old names raise `ArgumentError`.

* **rename group classes** <br>
  Group classes have been moved into their strategy's namespace:
  `FiberGroup` → `Fiber::Group`, `ThreadGroup` → `Thread::Group`,
  `CallGroup` → `Sequential::Group`, `TaskGroup` → `Async::Group`,
  `Fork::Group` → `Fork::Group`, `Ractor::Group` → `Ractor::Group`.

* **repurpose `LLM::Function::Task` as a task interface superclass** <br>
  `LLM::Function::Task` has been repurposed from a general-purpose class
  that tried to support multiple concurrency strategies into an abstract
  base class that defines the task interface. Individual strategies
  (`Sequential::Task`, `Thread::Task`, `Fiber::Task`, `Async::Task`,
  `Fork::Task`, `Ractor::Task`) now subclass it and implement
  `spawn`, `alive?`, `interrupt!`, and `wait`.

* **fix `:async` concurrency (now backed by a managed**
  **`LLM::Function::Async::Reactor` on a background thread)** <br>
  The `:async` strategy previously used `Async {}` which blocked the
  caller until all tasks completed and did not support interruption.
  The fix replaces it with a per-turn
  `LLM::Function::Async::Reactor` on a background thread. Work is
  submitted via `submit(&block)` and consumed by the reactor's event
  loop through a thread-safe `Queue`. `Async::Group` manages the
  reactor lifecycle and spawns tasks lazily on `wait`.
  <br><br>
  Interruption pushes [`LLM::Interrupt`](https://r.uby.dev/api-docs/llm.rb/LLM/Interrupt.html)
  to the task's result queue instead of using `Fiber#raise`, and
  results are bridged back to the caller through a second `Queue`.
  This work drove the broader refactor of strategy naming, the
  spawn/wait split, and the `Task` superclass. The `:async` strategy
  needed the same interface the other strategies already had.

* **compactor: refactor to strategy-based interface** <br>
  [`LLM::Compactor`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor.html)
  has been refactored from a single class that performed LLM-based
  summarization into a strategy-based superclass. Each subclass
  implements a different compaction strategy via `call(**opts)`. The old
  summarization approach (using `model:`, `token_threshold:`,
  `message_threshold:`, and `retention_window:` options) has been removed.
  The built-in
  [`LLM::Compactor::Truncate`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor/Truncate.html)
  strategy drops the oldest messages when the conversation exceeds a
  configured size.

* **rename `LLM::Context#{functions,functions?}` and `LLM::Agent#{functions,functions?}`** <br>
  [`LLM::Context#functions`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#functions-instance_method)
  and
  [`LLM::Context#functions?`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#functions%3F-instance_method)
  have been renamed to
  [`LLM::Context#pending_functions`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#pending_functions-instance_method)
  and
  [`LLM::Context#pending_functions?`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#pending_functions%3F-instance_method)
  respectively. The same rename applies to
  [`LLM::Agent#functions`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#functions-instance_method)
  (now
  [`LLM::Agent#pending_functions`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#pending_functions-instance_method)).
  The `pending_functions` name was already available as an alias in
  v12.5.0; this change removes the old `functions` name entirely.

### Core

* **extend `LLM.require` with an optional version argument** <br>
  `LLM.require` now accepts a second `version` parameter that is passed
  to `Kernel#gem` before loading, enabling version constraints for
  optional runtime dependencies. For example,
  `LLM.require "test-cmd.rb", "~> 2.2"` ensures a minimum gem version
  is available. This is used internally by the `Git`, `Rg`, `Mkdir`,
  and `Shell` tools to enforce compatibility with the `test-cmd.rb` gem.

### Compactor

* **add `Truncate` strategy for dropping oldest messages** <br>
  [`LLM::Compactor::Truncate`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor/Truncate.html)
  is a new built-in compaction strategy that drops the oldest messages
  when the conversation exceeds a configured size. It preserves tool
  call/return pairs so the algorithm never breaks in the middle of a
  sequence. Configured with `keep:` (default 64), it emits the standard
  `on_compaction` and `on_compaction_finish`
  [`LLM::Stream`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html)
  lifecycle callbacks. No LLM call is made; the strategy is purely
  lossy but fast and requires no network.

* **raise when given an unparseable `keep:` value** <br>
  `LLM::Compactor::Truncate` now raises `ArgumentError` when the `keep:`
  parameter cannot be parsed as an integer or percentage string, instead
  of failing with an obscure error later during execution.

* **accept percentage string for the `keep:` parameter** <br>
  `LLM::Compactor::Truncate#call` now accepts a percentage string such
  as `"80%"` for the `keep:` parameter, which keeps approximately 80%
  of the most recent messages. Integer values continue to work as
  before. This makes it easy to trim proportionally rather than to an
  absolute number of messages.

* **add `Null` strategy for no-op compaction** <br>
  [`LLM::Compactor::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor/Null.html)
  is a new built-in compaction strategy that does nothing. It is used as
  the default compactor when no strategy is configured on a context,
  ensuring the compactor interface is always present without requiring a
  separate nil check.

* **accept both `LLM::Agent` and `LLM::Context`** <br>
  [`LLM::Compactor#initialize`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor.html#initialize-instance_method)
  now accepts both `LLM::Agent` and `LLM::Context` instances. When given
  an agent, the internal context is unwrapped automatically, making the
  compactor API more flexible when working with agents.

#### Context integration

* **accept `compactor` and `compactor_options` parameters** <br>
  [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
  now accepts `compactor:` (a compactor class defaulting to
  [`LLM::Compactor::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor/Null.html))
  and `compactor_options:` (a hash of options forwarded to the
  compactor's `call` method) parameters. The compactor is automatically
  invoked at the beginning of each `talk` turn. The previous `compactor=`
  setter has been removed in favour of constructor-driven configuration.

* **`on_compaction` and `on_compaction_finish` receive a single argument** <br>
  [`LLM::Stream#on_compaction`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_compaction-instance_method)
  and
  [`LLM::Stream#on_compaction_finish`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_compaction_finish-instance_method)
  now accept a single argument (the compactor instance) instead of two
  arguments (context and compactor). The context is still available via
  `LLM::Compactor#ctx`, so access to the context is not lost. This
  simplifies the callback interface for compaction lifecycle observers.

### Tools

* **add `LLM::Tool::Utils` module for shared command execution logic** <br>
  A new
  [`LLM::Tool::Utils`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils.html)
  module provides shared `wait(command:, timeout:)` and `now` helper
  methods for tools that execute commands. Tools that include `Utils` can
  wait on a running command and automatically kill it when it exceeds the
  configured timeout, using `Process.clock_gettime` with `CLOCK_MONOTONIC`
  for precise timing. The module is used by both the `Shell` and `Rg`
  tools internally.

* **shell: add `timeout` parameter for command execution deadlines** <br>
  The
  [`LLM::Tool::Shell`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Shell.html)
  tool now accepts a `timeout` parameter (default 60s) that automatically
  kills commands exceeding the specified time limit, preventing hung
  processes from blocking the agent indefinitely.

* **rg: add `timeout` parameter for search execution deadlines** <br>
  The
  [`LLM::Tool::Rg`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Rg.html)
  tool now accepts a `timeout` parameter (default 5s) that automatically
  kills search commands exceeding the specified time limit, preventing
  long-running searches from blocking the agent indefinitely.

* **git: add `timeout` parameter for command execution deadlines** <br>
  The
  [`LLM::Tool::Git`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git.html)
  tool now accepts a `timeout` parameter (default 5s) that automatically
  kills git commands exceeding the specified time limit, preventing hung
  processes from blocking the agent indefinitely.

### Schema

* **properties are now ordered and support indifferent access** <br>
  [`LLM::Schema::Leaf`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema/Leaf.html)
  tracks property definition order in a new `index` attribute, matching
  the convention already used by
  [`LLM::Command::Parameter`](https://r.uby.dev/api-docs/llm.rb/LLM/Command/Parameter.html).
  Internally, `@properties` is stored as an
  [`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
  instead of a plain `Hash`, so lookups with both string and symbol keys
  work.

### Buffer

* **more array-like message management** <br>
  [`LLM::Buffer`](https://r.uby.dev/api-docs/llm.rb/LLM/Buffer.html)
  now exposes `first`, `reject!`, `select!`, `shift`, `clear`, `drop`,
  `take`, and `reverse`, making it easier to query and mutate
  `LLM::Context#messages` like an ordinary Array. `reject!` is aliased
  as `delete_if` for familiarity.

* **`last(nil)` no longer returns the last message** <br>
  `LLM::Buffer#last` now uses an internal `UNDEFINED` sentinel to
  distinguish between no argument (`last` returns the last message)
  and `nil` (`last(nil)` is treated as an argument). Previously `nil`
  was indistinguishable from no argument.

### Function

* **consolidate `call` and `call!` into one method** <br>
  The private `call!` method has been merged into the public
  [`LLM::Function#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#call-instance_method).
  The separate `call!` method existed for tracer-scoping logic now
  handled directly inside `call`. All internal call sites now use
  `function.call` instead of `function.call!`.

* **add `LLM::Function::Group` as an abstract base class** <br>
  A new abstract base class
  ([`LLM::Function::Group`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Group.html))
  defines the interface that all concurrency strategy groups must
  implement: `alive?`, `interrupt!`, and `wait`. Each strategy group
  (`Sequential::Group`, `Thread::Group`, `Fiber::Group`,
  `Async::Group`, `Fork::Group`, `Ractor::Group`) now subclasses
  this base.

* **split `spawn` and `wait` across all strategies** <br>
  `spawn` now starts execution without blocking, and `wait` collects
  the result. `on_tool_start` moved into each task's `spawn` so the
  tracer span covers execution rather than construction. Each task and
  group now exposes a public `spawn` method alongside the existing
  `wait`/`value` methods.

* **spawn tasks lazily in `Group#wait`** <br>
  All concurrency strategy groups (Fiber::Group, Fork::Group,
  Ractor::Group, Thread::Group) now automatically spawn their tasks
  when `wait` is called if they haven't been spawned yet, matching
  the existing `Async::Group` behavior. This makes the spawn/wait
  contract consistent across all six concurrency backends.

### Agent

* **add `name` class DSL and instance method** <br>
  [`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html) now
  has a `name` class DSL (`name "admin"`) and a corresponding `#name`
  instance method. The name is resolved through the same lazy-resolution
  path as other agent attributes. It can be set via
  `LLM::Agent.set(name: ...)`, `LLM::Agent.new(name: ...)`, or the class
  DSL. When no name is given, a default is derived from the class name
  (e.g., `SystemAdmin` becomes `system-admin`). The REPL uses the name
  as the prompt label and transcript prefix, making it easier to
  distinguish multiple sessions.

### REPL

* **agent identity in the prompt** <br>
  [`LLM::Agent#repl`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#repl-instance_method)
  and
  [`LLM::Repl.new`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl.html#initialize-instance_method)
  accept a `name:` parameter (defaulting to `LLM::Agent#name`) that sets
  the input prompt to `provider(name)> ` and labels transcript messages
  with the agent's name instead of a hardcoded `agent:`. Useful when
  running multiple sessions.

* **`/compact` command** <br>
  New built-in `/compact` command frees context window space by dropping
  the oldest messages via
  [`LLM::Compactor::Truncate`](https://r.uby.dev/api-docs/llm.rb/LLM/Compactor/Truncate.html).
  Supports both integer (`/compact 32`) and percentage (`/compact 75%`)
  arguments. Defaults to keeping the last 128 messages.

* **tab-completion for `/` commands** <br>
  Pressing Tab on an input line starting with `/` autocompletes the
  command name. Repeated Tab presses cycle through matching commands.
  Powered by
  [`LLM::Command.complete(str)`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#complete-class_method)
  which is available outside the REPL too.

* **command system enhancements** <br>
  Commands can set parameter defaults in their `call` method signature
  (e.g., `def call(n: 128)`). Aliases like `/quit` now inherit their
  parent's description and parameters. Commands also have access to
  the active `agent` and `repl` via public readers.

* **tool argument sorting** <br>
  Tool parameters in the status bar are now displayed in definition
  order (using the new `index` attribute), regardless of the order
  the model returns them.

* **expanded markdown rendering** <br>
  The curses-based markdown renderer now handles lists (`<ul>`, `<ol>`),
  blockquotes, horizontal rules, hyperlinks (underline), images
  (`[image: alt text]`), and tables (aligned columns).

* **input improvements** <br>
  Ctrl+P and Ctrl+N walk through conversation history (user messages
  only, managed by
  [`LLM::Repl::Walker`](https://r.uby.dev/api-docs/llm.rb/LLM/Repl/Walker.html)).
  Page Up/Down scroll the transcript by a page. ENTER and BACKSPACE are
  now mapped to raw character codes from `Curses.getch` instead of
  `Curses::Key` constants.

### Object

* **preserve the original key name in `KeyError` messages** <br>
  `LLM::Object#fetch` now preserves the original key name when a key
  is not found, instead of raising `KeyError` with `key not found: nil`.
  The previous behavior occurred when the given key was not found in
  the stored hash, causing internal lookup to return `nil` and lose
  the original key reference.

### Registry

* **refresh model metadata across providers** <br>
  Update `data/*.json` files with current provider model listings and
  pricing. Mark several DeepInfra models as deprecated (`meta-llama/
  Meta-Llama-3.1-8B-Instruct`, `Qwen/Qwen1.5-110B-Chat`, and
  `mistralai/Mixtral-8x7B-Instruct-v0.1`). Correct xAI cache-read
  pricing from $0.50 to $0.30 per million input tokens.

### Fix

* **agent: fix default name resolution when name is not explicitly set** <br>
  Fix a bug where `LLM::Agent` derived its default name from
  `self.class` instead of `self`, causing the name to be `"class"`
  instead of a parameterized version of the actual class name
  (e.g., `"system-admin"` for `SystemAdmin`). The fix uses `self`
  directly, which correctly resolves the class name at the instance
  level.

* **function: make Fork::Task and Ractor::Task inherit LLM::Function::Task** <br>
  `LLM::Function::Fork::Task` and `LLM::Function::Ractor::Task` now
  explicitly subclass `LLM::Function::Task` and accept an options hash
  as their second argument, matching the constructor signature used
  by the other four task classes. The interface was already compatible
  but the inheritance was missing by mistake. It is now consistent across
  all six concurrency backends.

* **google: fix `stream` parameter leakage that broke the provider** <br>
  Fix a bug in the Google provider where `stream: stream.enabled?` was
  being merged into request parameters, causing API-level errors. The
  Google provider does not use a `stream` parameter. Streaming is
  controlled via the URL path (`streamGenerateContent` vs
  `generateContent`). The fix removes the leaked parameter and correctly
  routes streaming requests through the appropriate path.

* **fork: fix deadlock on xchan.rb channel** <br>
  Fix a deadlock in the `:fork` concurrency strategy where both the
  writer and reader could get stuck on the xchan channel, preventing the
  reader from draining the channel. The deadlock surfaced as an errno
  failure, especially with large tool returns. The fix requires xchan.rb
  v0.22.0 and uses the `SOCK_STREAM` socket type for communicating a
  tool's return value.

## v12.6.0

Changes since `v12.5.1`.

This release adds bulk defaults for tools and agents: `LLM::Tool.defaults`
for setting parameter defaults and `LLM::Agent.set` for mass-assigning
class-level defaults, both mirrored on ActiveRecord and Sequel agent models.

It also makes `LLM::Interrupt` reliable across every concurrency strategy
(:thread, :call, :fiber, :task, :fork, and :ractor) so tool cancellation
works consistently regardless of execution backend, and fixes a stale fiber
reference in `LLM::Context#talk` that could prevent interruption after a
prior call.

### Add

* **tool: add `defaults` method for setting parameter defaults** <br>
  Add `LLM::Tool.defaults(properties)` for bulk-setting default values
  on tool parameters, matching the same interface as `LLM::Schema.defaults`.
  Each key maps to a parameter name; unknown keys raise `KeyError`.

* **agent: add `set` method for bulk-assigning class-level defaults** <br>
  Add `LLM::Agent.set(properties)` for mass-assigning agent defaults
  from a Hash. Each key maps to a class-level accessor; unknown keys
  raise `KeyError`.

* **active_record: expose `set` on `acts_as_agent` models** <br>
  ActiveRecord models using `acts_as_agent` can call `set` to
  bulk-assign agent class-level defaults.

* **sequel: expose `set` on `plugin :agent` models** <br>
  Sequel models using `plugin :agent` can call `set` to bulk-assign
  agent class-level defaults.

### Fix

* **function: raise `LLM::Interrupt` on thread where tool is running** <br>
  On cancel, `LLM::Interrupt` is now raised on the thread that is
  running a tool. The tool can rescue `LLM::Interrupt` and gracefully
  terminate (e.g., clean up resources). The previous approach used
  `Thread#interrupt` which was less reliable. It did not interrupt a
  sleeping thread.

* **function: suppress thread exception reporting in `:thread` concurrency** <br>
  Threads spawned by the `:thread` concurrency strategy now have
  `report_on_exception` set to `false`, preventing noisy exception
  messages from appearing on stderr when a thread is interrupted
  during tool execution.

* **context: clear `@owner` after `talk` completes** <br>
  `LLM::Context#talk` now clears the `@owner` reference in an
  `ensure` block after the method completes, so `interrupt!` does
  not attempt to interrupt a stale fiber reference from a prior
  call.

* **function: raise `LLM::Interrupt` on thread waiting in `CallGroup#wait`** <br>
  When using `ctx.wait(:call)`, `LLM::Interrupt` is now raised on the
  thread executing the sequential tool wait. `CallGroup#wait` tracks the
  active thread and `interrupt!` raises `LLM::Interrupt` on it, enabling
  interruption of the `:call` concurrency strategy just like the existing
  `:thread` strategy.

* **function: raise `LLM::Interrupt` on fiber-backed tool tasks** <br>
  `LLM::Interrupt` is now raised on the active fiber via `Fiber#raise`
  when interrupting `:fiber`-concurrency tools.
  <br><br>
  `Task#interrupt!` now dispatches by task type: `Thread#raise` for
  threads, `Fiber#raise` for fibers. Making interruption reliable
  across all concurrency strategies.

* **function: raise `LLM::Interrupt` on fork-backed tool tasks** <br>
  `LLM::Interrupt` is now raised on the main thread of a fork child
  process via `Thread.main.raise(LLM::Interrupt)` when interrupting
  `:fork`-concurrency tools, and the fork `Task#wait` re-raises the
  interrupt on the parent side. Making interruption reliable across
  all concurrency strategies including `:fork`.

* **function: raise `LLM::Interrupt` on `Async::Task`-backed tool tasks** <br>
  `LLM::Interrupt` is now raised on the underlying fiber of an
  `Async::Task` via `Fiber#raise` when interrupting `:task`-concurrency
  tools. `Task#interrupt!` now detects `Async::Task` instances and
  dispatches to `Fiber#raise`, extending reliable interruption to the
  `:task` concurrency strategy under the Async runtime.

* **function: raise `LLM::Interrupt` on ractor-backed tool tasks** <br>
  `LLM::Interrupt` is now raised on the main thread inside a ractor
  via `Thread.main.raise(LLM::Interrupt)` when interrupting
  `:ractor`-concurrency tools. A listener thread inside the tool
  ractor waits for an interrupt message via `Ractor.receive` and
  raises `LLM::Interrupt` on the ractor's main thread.
  <br><br>
  `Task#interrupt!` delegates to the mailbox to send the interrupt
  message. Extending reliable interruption to the `:ractor`
  concurrency strategy.

## v12.5.1

Changes since `v12.5.0`.

This release reverts the global `LLM::Function` registry fallback for tool
resolution that was added in v12.5.0.

### Change

* **function: remove the global registry fallback for tool resolution** <br>
  Remove the `LLM::Function.find_by_name` fallback that was added in
  v12.5.0 as an intermediate step between available-tools lookup and
  raising `LLM::NoSuchToolError`. Tool calls not found in the available
  tools list now go directly to `function_missing` (which raises
  `LLM::NoSuchToolError`) without first checking the global
  `LLM::Function` registry.

## v12.5.0

Changes since `v12.4.0`.

This release extends the REPL command system with typed parameters, a
built-in `/help` command, command aliases (`/quit`), and cancellation
via the 'Esc' key.

The default HTTP timeout is increased to 15 minutes (900s) to better
accommodate reasoning models and large structured outputs.
`LLM::Agent#deserialize` and `LLM::Agent#restore` now return `self` for
method chaining, and `LLM::Buffer#pop` is added for tail-end message
removal.

Tool resolution gains a fallback to the global `LLM::Function` registry
before raising `LLM::NoSuchToolError`, and `pending_functions` aliases
are added on both contexts and agents for a consistent interface.

Several REPL bugs are fixed including parameter state leakage across
turns and invalid tool-call error routing.

Model metadata is refreshed across all providers with new Anthropic,
OpenAI, Google, DeepInfra, DeepSeek, and xAI model entries.

### Add

#### Buffer & function internals

* **buffer: add `LLM::Buffer#pop`** <br>
  Add `LLM::Buffer#pop` for removing the last message from the tail
  of the buffer, complementing the existing `#<<` and array-style
  message management.

* **function: add registry fallback for tool resolution** <br>
  When resolving tool calls from a message, if the tool is not found
  in the available tools list, it now also looks up the global
  `LLM::Function` registry via `LLM::Function.find_by_name` before
  creating a placeholder function. This improves tool resolution for
  tools that are registered globally but not passed directly through
  the request tool set.

#### Consistent `pending_functions` aliases

* **context: alias `LLM::Context#functions` as `LLM::Context#pending_functions`** <br>
  Add `LLM::Context#pending_functions` as an alias for `LLM::Context#functions`,
  so callers that prefer the more descriptive `pending_functions` name can use
  it instead of `functions` when checking for unresolved tool work.

* **agent: alias `LLM::Agent#functions` as `LLM::Agent#pending_functions`** <br>
  Add `LLM::Agent#pending_functions` as an alias for `LLM::Agent#functions`,
  matching the same alias on `LLM::Context`, so callers have a consistent
  `pending_functions` interface across both contexts and agents.

#### REPL command system

* **repl: extend command system with parameter support** <br>
  Commands can now declare typed parameters using the `parameter`
  DSL, modelled after `LLM::Tool` and `LLM::Schema` conventions.
  Parameters can be marked as required with `required %i[...]`,
  and values are type-checked before being passed to `call`.
  Argument parsing is handled by the repl: arguments are split
  from the input string and assigned to parameters by position.

  ```ruby
  class Greeter < LLM::Command
    name "greet"
    description "Greets the given name"
    parameter :name, String, "The person's name"
    required %i[name]

    def call(name:)
      write("Welcome #{name}!\n")
    end
  end
  ```

* **repl: add `help` command** <br>
  Add `LLM::Repl::Help` as a new built-in command, registered
  automatically via the command registry. Typing `/help` shows
  the `help` command's own name, description, and parameters,
  while `/help <name>` shows details for a specific command,
  including its parameters and whether each is required or
  optional. Unknown command names produce an error message.

  ```ruby
  class Help < Command
    name "help"
    description "show help for a given command"
    parameter :name, String, "The name of a command"

    def call(name: nil)
      if name.nil?
        write("\n#{self.class.help}\n\n")
      elsif command = LLM::Command.find_by(name:)
        write("\n#{command.help}\n\n")
      else
        write "\nNo help for #{name} was found" \
              "\nThat command doesn't exist.\n\n"
      end
    end
  end
  ```

* **repl: add support for command aliases** <br>
  Commands can now be aliased by creating a subclass of another
  command (with `LLM::Command` as an indirect ancestor). The
  first alias introduced is `/quit` as an alias of `/exit`.

  ```ruby
  class Quit < Command::Exit
    name "quit"
  end
  ```

* **repl: add `Command::Parameter#optional?`** <br>
  Parameters now expose an `#optional?` method that returns `true`
  when a parameter has not been marked as required, making it
  possible to query parameter optionality programmatically.

* **repl: add `LLM::Repl::Command#write`** <br>
  Commands can now write output to the transcript via the `write`
  method. Commands also receive a reference to the active repl
  through their `#initialize` method, making it possible to
  interact with the repl window from within a command.

* **repl: display command errors in the curses UI** <br>
  Commands invoked with too few arguments now display an error
  message: `command(<name>): too few arguments`. Displayed directly in
  the curses transcript area, giving immediate feedback instead
  of silently failing.

* **repl: add `LLM::Command` convenience constant** <br>
  Add `LLM::Command = LLM::Repl::Command` as a shorter alias,
  available once `"llm/repl"` is required.

#### Misc

* **repl: implement cancellation with the 'Esc' key** <br>
  The curses-based REPL now supports cancelling an active model
  request by pressing the 'Esc' key. When a request is in progress,
  the status line shows `thinking • Esc to cancel`, and pressing
  Esc calls `LLM::Agent#cancel!` to interrupt the request. The
  transcript displays `request cancelled!` to confirm the
  cancellation.

### Change

#### Misc

* **provider: increase default timeout to 900s** <br>
  The default HTTP timeout for all providers has been increased from
  180 to 900 seconds (15 minutes) to better accommodate long-running
  requests such as reasoning models and large structured outputs.

* **agent: `deserialize` and `restore` return `self`** <br>
  `LLM::Agent#deserialize` and `LLM::Agent#restore` now return `self`
  (the agent instance) instead of forwarding the context's return
  value, enabling method chaining after restoring agent state.

* **context: discard all messages from a cancelled turn** <br>
  When `LLM::Context#cancel!` is called, all messages added during
  that turn are now discarded via `Buffer#slice!`, preventing edge
  cases where dangling tool calls between turns caused repeated
  cancellation loops. The `#repair!` method now handles tool call
  cancellations on the next turn instead of mutating the conversation
  buffer directly at cancellation time.

* **stream: drop the `error` argument from `on_tool_call`** <br>
  The `on_tool_call` callback no longer accepts an `error` argument.
  Previously, stream parsers passed both a tool and an optional error,
  requiring boilerplate like `if error; queue << error; end` in every
  callback. Error handling is now pushed directly onto the stream queue
  inside each provider's stream parser, so `on_tool_call(tool)` is the
  only signature. The REPL stream and base `LLM::Stream` class have
  been updated accordingly.

#### REPL internals

* **repl: pass the repl instance to command constructors** <br>
  `LLM::Repl::Command` subclasses now receive the active repl
  instance via `initialize(repl)`, enabling commands to write
  to the transcript and interact with the repl window.

* **repl: `Command#write` prefixes messages with the command name** <br>
  The `#write` method now prefixes output with `command(<name>): `
  so command messages are consistent with the `user:` and `agent:`
  labels in the transcript. The prefix can be customised with the
  `who:` keyword argument, or set to `who: nil` to disable it
  entirely.

### Fix

#### Misc

* **function: avoid silent skip of tools not found in available tools** <br>
  When a model calls a tool that is not present in the available tools
  list, instead of silently skipping the tool call (via `next`), a
  `LLM::NoSuchToolError` is now raised so the model receives feedback
  about the invalid tool call and can correct course.
  <br><br>
  An additional fallback to the global `LLM::Function` registry is
  tried before raising, so globally registered tools are still
  resolved even when not in the per-request tool set.

#### REPL bugs

* **repl: don't persist parameter state between turns** <br>
  Parameter state (such as `Parameter#value`) was leaking across
  turns because the same parameter objects were being mutated
  in place. A duplicate set of parameters is now created for each
  turn, keeping the original parameter definitions intact and
  preventing stale state from carrying over.

* **repl: reply with error when given an invalid tool** <br>
  When the model tries to call a tool that does not exist, the
  error is now pushed onto the stream queue so the model can
  see the error and correct course, instead of silently dropping
  the invalid tool call and leaving it to `Context#repair` to
  remove it from history.

* **repl: fix save of initial runtime state** <br>
  Fix a bug in `LLM::Repl#configure` where a non-existent path
  argument was treated as no path at all, preventing the initial
  runtime state from being saved after the first turn. The correct
  behavior is to create the file so it can be written to after
  the first turn completes.

### Refresh

* **Refresh model metadata across all providers** <br>
  Update model listings, pricing, capabilities, reasoning options,
  modality support, context limits, and release dates across all
  provider registries (Anthropic, AWS Bedrock, DeepInfra, DeepSeek,
  Google, Mistral, OpenAI, xAI, and ZAI). Notable changes include
  Anthropic claude-opus-4-8 and claude-sonnet-4-6 additions with
  effort-based reasoning, OpenAI gpt-5.6-sol/terra/luna and
  gpt-5-codex additions, Google gemini-3-pro-preview and
  gemini-3-flash-preview additions, DeepInfra Qwen3.5 and DeepSeek
  V4 model additions, and updated xAI Grok model entries.

## v12.4.0

Changes since `v12.3.1`.

This release brings major improvements to the curses-based REPL
(`LLM::Agent#repl`). The REPL now supports saving and restoring runtime
state across sessions, automatic paste-mode detection for fast bulk input,
a command system foundation with the `/exit` command, and several new
keybindings (Ctrl+F, Ctrl+K, Ctrl+Y). Tool calls are rendered with a
compact function-call syntax in the status bar.

Two new built-in tools: `LLM::Tool::Ls` and `LLM::Tool::Which` are
available as opt-in additions for file listing and executable lookup.

Model metadata has been refreshed across providers, the REPL loop
internals have been refactored to use `catch`/`throw` for cleaner command
routing, and several bugs have been fixed including a tracer restoration
issue in the agent ensure clause and a missing cursor in the REPL input
area.

### Add

* **repl: allow runtime state to be saved and restored** <br>
  `LLM::Agent#repl` now accepts a `path:` option that serializes
  runtime state to the filesystem. When the path already exists,
  runtime state is restored when the read-eval-print loop starts.
  Otherwise the path is written after the first turn, making it
  possible to resume a session across process restarts.

* **repl: scroll to the bottom on submit** <br>
  The curses-based REPL now scrolls the transcript to the bottom when
  the user submits their input, so the latest response is visible
  without needing to scroll down manually.

* **repl: add Ctrl+F to move the cursor forward** <br>
  The curses-based REPL input now supports Ctrl+F to move the cursor
  forward by one column, matching common terminal editing conventions
  found in shells like `/bin/sh`.

* **repl: add Ctrl+K to erase from cursor to end of line** <br>
  The curses-based REPL input now supports Ctrl+K to erase all text
  from the cursor position to the end of the input buffer, matching
  common terminal editing conventions found in shells like `/bin/sh`.

* **repl: add Ctrl+Y to paste previously killed text** <br>
  The curses-based REPL input now supports Ctrl+Y to insert the most
  recently killed text (via Ctrl+K) at the current cursor position,
  matching the yank/paste convention found in shells like `/bin/sh`.
  The killed text is stored in an internal copy buffer so it can be
  pasted multiple times or at different cursor positions.

* **repl: add command system foundation** <br>
  Add `LLM::Repl::Command` as a new base class for REPL commands,
  along with the first built-in command `LLM::Repl::Command::Exit`
  which exits the read-eval-print loop via `throw(:exit)`.
  Commands are identified by a name and can be looked up through
  `Command.find_by`. This is the foundation for the `/` command
  syntax used in the REPL input line.

* **repl: connect the command system to user input** <br>
  The curses-based REPL now routes user input through the command
  system. Any input string beginning with `"/"` is matched against
  the command registry via `Command.find_by`, and the corresponding
  command is executed instead of being forwarded to the model.
  This makes built-in commands like `/exit` functional from the
  input line. Command arguments are not yet supported.

* **repl: add `LLM::Repl::Command.registry`** <br>
  Add `LLM::Repl::Command.registry` for auto-registering command
  subclasses. The `inherited` hook captures each new subclass and
  stores it in the registry, making it possible to enumerate all
  available commands at runtime. Built-in commands like Exit are
  automatically registered when the command file is loaded.

* **repl: detect and handle paste mode in the input line** <br>
  The curses-based REPL input now detects paste operations by tracking
  the rate at which characters arrive. A paste rate of ≤50ms is
  assumed to be a burst of characters that could only be explained by
  a paste. No human types that fast. Multiline pastes are supported
  through internal refactoring of the input handling logic.

* **repl: optimize paste mode rendering** <br>
  Track the paste state with an internal `@paste` variable and switch
  to a faster input path during paste operations. While in paste mode,
  the input buffer is drained via `Curses.getch`, bypassing the more
  expensive char-by-char render path used for ordinary interactive
  input. This makes pasting large amounts of text noticeably faster.

* **Add `LLM::Tool::Ls`** <br>
  Add a built-in tool for listing files and directories, with optional
  glob pattern filtering to narrow results. <br>
  It must be required explicitly with `require "llm/tools/ls"`.

* **Add `LLM::Tool::Which`** <br>
  Add a built-in tool for locating an executable on the system PATH.
  This lets an agent check whether a command is available before
  attempting to run it, avoiding failed subprocess calls. <br>
  It must be required explicitly with `require "llm/tools/which"`.

* **repl: render tool calls in a function-call syntax** <br>
  The curses-based REPL status bar now renders tool calls with a
  compact function-call syntax: `tool(key: value)` instead of
  `tool: name`. Strings are quoted and truncated, arrays show their
  first two elements, and hashes collapse to `{…}`, making it easier
  to see what arguments the model is passing. The `tool done` status
  message has been removed since the tool call itself conveys
  completion information.

### Change

* **Refresh model metadata** <br>
  Update model listings, pricing, and capabilities across providers.
  Fix GPT-5.6 model family names in the OpenAI registry (`gpt` to
  `gpt-sol`, `gpt-nano` to `gpt-luna`, `gpt-mini` to `gpt-terra`).
  Add OpenAI models (`gpt-5.6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`)
  to the AWS Bedrock registry. Update DeepInfra pricing for
  `DeepSeek-V3` and `Sky-T1-32B-Preview`. Fix Google model knowledge
  cutoff dates.

* **repl: control the loop with catch & throw** <br>
  The curses-based REPL input loop now uses `catch(:exit)` and
  `throw(:exit)` instead of returning the `:exit` symbol and
  breaking out of the loop. This enables the `/command` syntax
  without requiring an `:exit` return value to be propagated
  through a potentially deeply nested call path.

* **repl: replace Ctrl+D with shell-like delete-at-cursor** <br>
  The curses-based REPL input now treats Ctrl+D as a delete action
  that removes the character at the current cursor position, matching
  the shell/Emacs convention where Ctrl+D deletes the character under
  the cursor instead of signalling end-of-file. The previous Ctrl+D
  behaviour (exiting the REPL) is superseded by the `/exit` command.

* **repl: switch to 'Thinking' mode after tool return** <br>
  The curses-based REPL status line now switches to "Thinking" mode
  after a tool returns, so the user can see the agent is processing
  the tool result rather than showing a stale tool-call status.

### Fix

* **agent: fix a subtle typo in the ensure clause** <br>
  Fix a subtle typo in `LLM::Agent` where the deprecated `trace` local
  variable was given preference over `tracer` (the preferred local name)
  in an `ensure` clause. The `trace` local was supported for backward
  compatibility but the ensure clause still referenced `trace` instead of
  `tracer`, which meant the previous tracer was never restored when the
  REPL session ended.

* **repl: restore the cursor in the input area** <br>
  Remove the `Curses.curs_set(0)` call from the REPL redraw method,
  which was inadvertently hiding the cursor and making it impossible
  to see the current position in the input area. The input field is
  now always drawn at its full height so the cursor position is
  correctly maintained after each redraw.

## v12.3.1

Changes since `v12.3.0`.

This release fixes a flickering issue in the curses-based REPL redraw.
The full-screen clear that caused visible flickering has been replaced
with a targeted cursor-hide approach, and stale rows from a larger
transcript are now explicitly cleared to prevent ghost text from
lingering when the transcript shrinks.

### Fix

* **repl: fix redraw flicker** <br>
  Replace `Curses.clear` with `Curses.curs_set(0)` in the REPL redraw
  method to avoid a full screen clear that caused visible flickering
  during redraws. The drawing order is also adjusted so the status line
  is drawn before the divider, and stale rows left over from a larger
  transcript are now explicitly cleared to prevent ghost text from
  lingering when the transcript shrinks.

## v12.3.0

Changes since `v12.2.0`.

This release brings major improvements to the curses-based REPL
(`LLM::Agent#repl`). The status line now shows a context-usage bar and
running cost counter, the input field expands to three rows with
full cursor navigation, model responses are rendered as styled markdown,
and the UI stays responsive while the agent is working by running
requests in a separate thread. A new `LLM::Stream::IO` and
`LLM::Stream::Disabled` provide a uniform stream representation across
all stream types.

Mistral OCR support is added for extracting text from images and
documents via the `/v1/ocr` endpoint. The `skills:` and `tools:` options
on `LLM::Agent#repl` let you attach additional tools or skill directories
for the duration of a session. `LLM::Object#merge!` rounds out the
in-place merge API, and a new `LLM.logger` convenience method creates
tracer logger instances with less verbosity.

### Add

* **Add `LLM.logger` convenience method** <br>
  Add `LLM.logger(llm, ...)` as a shorter, less verbose way to create an
  `LLM::Tracer::Logger` instance. Takes a provider and optional keyword
  arguments forwarded to the logger constructor.

* **Add `skills:` option to `LLM::Agent#repl`** <br>
  `LLM::Agent#repl` now accepts a `skills:` keyword argument that attaches
  one or more skill directories (containing `SKILL.md`) for the duration of
  the repl session. Skills are loaded and converted to tools, combining with
  any tools already configured on the agent, and are discarded when the
  session ends.

* **Add `LLM::Provider#ocr` base method** <br>
  Add a base `ocr(...)` method to `LLM::Provider` that raises `NotImplementedError`
  by default, establishing a common interface for providers that support OCR
  (Optical Character Recognition) on images and documents.

* **Add Mistral OCR endpoint support** <br>
  The Mistral provider now supports OCR via its `/v1/ocr` endpoint. Call
  `mistral.ocr(image_url: ...)` for images or `mistral.ocr(document_url: ...)`
  for documents (e.g., PDFs). Returns an `LLM::Response` with extracted pages,
  markdown content, and structured block data.

* **Add `LLM::Object#merge!`** <br>
  Add `LLM::Object#merge!` for in-place merging of hash data into an
  `LLM::Object` instance, complementing the existing `#merge` method.

* **Add `LLM::Stream::IO` and `LLM::Stream::Disabled`** <br>
  `LLM::Stream::IO` wraps IO-like objects as stream targets, forwarding
  streamed content via `#<<`. `LLM::Stream::Disabled` represents an explicitly
  disabled stream with no-op callbacks.

  This is part of an internal refactoring that lets all stream values: IO
  objects, `true`, `false`, `nil`, and `LLM::Stream` instances themselves
  be represented by the same `LLM::Stream` interface via the new
  `LLM::Stream.try` factory method.

  Before this change the codebase had to perform ad-hoc type checks
  (e.g. `if LLM::Stream === stream`) scattered throughout. After this
  change all stream handling goes through a single uniform path, and
  providers check `#enabled?` to decide whether to request streaming
  from the API.

### Change

* **repl: rename `trace:` to `tracer:`** <br>
  The `trace:` keyword argument in `LLM::Agent#repl` has been renamed to
  `tracer:` for consistency with the rest of the codebase. The old `trace:`
  name still works with a deprecation warning.

* **repl: add context-usage bar and cost counter to the status line** <br>
  The curses-based REPL status line now shows a small progress bar that
  indicates how much of the model's context window remains as a percentage,
  alongside a running cost estimate rendered on the right side of the status
  line. The input line has been updated to show the provider name as a prefix.
  Estimates are best-effort and depend on registry pricing data (see `data/`).

* **repl: keep the UI responsive while a request is in progress** <br>
  The curses-based REPL now spawns the agent request in a separate thread
  and communicates streamed output through a queue, so the curses UI stays
  responsive during model processing. Users can continue to scroll through
  the transcript while the agent is working.

* **repl: style transcript rows as structured data with bold labels** <br>
  The curses-based REPL transcript now stores rows as structured data with
  style metadata instead of plain strings, enabling bold rendering of the
  `user:` and `agent:` labels for improved readability during interactive
  sessions.

* **repl: render a small subset of markdown** <br>
  The curses-based REPL now renders model responses as styled markdown.
  Headers and strong text render in bold, emphasis renders in underline,
  and code spans and blocks are highlighted with inverted colors. Streaming
  content is buffered and re-rendered on each tick so the transcript reads
  cleanly as the agent responds. Requires the optional `kramdown` gem.

* **repl: add cursor LEFT/RIGHT movement to the input line** <br>
  The curses-based REPL input now supports cursor movement with the left
  and right arrow keys, enabling in-place text editing before submitting
  a prompt. The cursor position is tracked visually and moves backwards
  on left-arrow and forwards on right-arrow.

* **repl: add Ctrl+A and Ctrl+E keybindings to the input line** <br>
  The curses-based REPL input now supports Ctrl+A to jump the cursor to
  the start of the input line and Ctrl+E to jump it to the end, matching
  common terminal editing conventions.

* **repl: add `tools:` option to `LLM::Agent#repl`** <br>
  `LLM::Agent#repl` now accepts a `tools:` keyword argument that attaches
  additional tool classes or instances for the duration of the repl session.
  These tools are combined with any tools already configured on the agent,
  and are discarded when the session ends.

* **repl: add repl support to ActiveRecord and Sequel agent models** <br>
  `acts_as_agent` (ActiveRecord) and `plugin :agent` (Sequel) models now
  expose a `repl` method that delegates to the underlying agent's
  read-eval-print loop. This allows interactive debugging and inspection
  of persisted agent state at runtime. Note that changes made during a
  repl session do not persist back to the database.

* **repl: add extra padding between markdown nodes** <br>
  The curses-based REPL markdown renderer now adds extra vertical spacing
  between certain markdown elements: paragraphs, headers, and codeblocks
  for improved readability of model responses.

* **repl: add a visual divider between transcript and the rows below it** <br>
  The curses-based REPL now draws a horizontal divider line (using a unicode
  `─` character) to separate the transcript area from the status and input
  rows below it. A single empty buffer row is also added between the
  transcript and the divider, preventing transcript text from running too
  close to the status and input rows.

* **repl: expand input field to 3 rows** <br>
  The curses-based REPL input field now spans three rows instead of one,
  wrapping text that exceeds the terminal width onto subsequent lines. A
  scrollable viewport follows the cursor so the active line stays visible,
  and common navigation commands (Ctrl+A, Ctrl+E, cursor keys) work across
  all three rows of the expanded input area.

* **Refresh OpenAI model metadata** <br>
  Add new OpenAI models to the registry, including `gpt-5.6`,
  `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-5.6-sol`, and
  `gpt-realtime-2.1`, with associated pricing, capabilities, and
  limits.

### Fix

* **Fix Ollama non-streaming response handling** <br>
  Fix the Ollama provider to properly handle the non-streaming path. When
  the provider returns a raw NDJSON response body (instead of streaming),
  the response is now parsed and merged into a single `LLM::Object` before
  being returned to the caller. Previously the non-streaming path was
  effectively broken and would fail to produce a valid completion response.

* **repl: handle a negative context window allowance in the usage bar** <br>
  Fix a crash in the curses-based REPL context-usage bar when the context
  window allowance is exceeded (used > total). The negative width value that
  resulted from this edge case could cause curses errors; it now gracefully
  defaults to `0%` and zero bar width.

* **Fix YARD documentation across provider and tool files** <br>
  Fix unnamed, misnamed, and missing `@param` tags in `LLM::Repl::Status`,
  `LLM::Tool::Git`, `LLM::Tool::Pwd`, `LLM::Tool::Rg`, and
  `LLM::Tool::SwapText`.

## v12.2.0

Changes since `v12.1.0`.

This release adds Mistral as a new provider with chat completions, streaming, tool calls,
structured outputs, file/image attachments, and embeddings support. It introduces
the `trace:` option to `LLM::Agent#repl` for keeping the tracer active during
interactive sessions.

Several fixes land for the Google provider (generationConfig parameter leakage),
`LLM::Context#tracer=` (always assigning nil), `LLM::Provider#with_tracer(nil)`
(nil fallback), and `LLM::Context#repair!` (dropping Struct returns).

The default HTTP timeout has been increased from 60s to 180s to better accommodate
reasoning models and large structured outputs, and the Anthropic default model has
been updated to `claude-opus-4-8`. Model metadata has been refreshed across
Anthropic, AWS Bedrock, DeepInfra, Google, and xAI, with Mistral model data added
to the registry.

### Add

* **Add `trace:` option to `LLM::Agent#repl`** <br>
  `LLM::Agent#repl` now accepts a `trace:` keyword argument. By default
  the tracer is disabled for the duration of the repl session to prevent
  curses UI interference from output written to `$stdout` or `$stderr`.
  Set `trace: true` to keep the tracer active during the session, which
  is useful when the tracer writes to a file rather than the terminal.

* **Add a new provider: LLM::Mistral** <br>
  [Mistral](https://mistral.ai) is now supported through its
  OpenAI-compatible API. The provider supports chat completions,
  streaming, tool calls, structured output (schema), file/image
  attachments, and embeddings. Use `LLM.mistral(...)` to create a
  provider instance.

* **Add `LLM.mistral(...)` convenience method** <br>
  A new top-level accessor (`LLM.mistral`) returns an `LLM::Mistral`
  provider instance, matching the pattern used by other providers.

### Fix

* **Fix Google `generationConfig` parameter leakage** <br>
  Fix a bug in the Google provider where non-generation parameters
  (`role`, `model`, `messages`, `stream`) were leaking into the
  `generationConfig` object alongside legitimate generation config
  parameters such as `temperature`. Non-config parameters are now
  filtered out before constructing `generationConfig`.

* **Fix `LLM::Context#tracer=` always assigning `nil`** <br>
  The `LLM::Context#tracer=` setter had a bug where it always assigned
  `nil` regardless of the tracer value passed. It now correctly assigns
  the given tracer or falls back to `LLM::Tracer::Null`.

* **Fix `LLM::Provider#with_tracer(nil)` fallback** <br>
  `LLM::Provider#with_tracer(nil)` now falls back to
  `LLM::Tracer::Null` instead of setting a `nil` tracer directly.

* **Fix `LLM::Context#repair!` dropping `Struct` returns** <br>
  `LLM::Context#repair!` used `[*prompt]` to wrap the prompt before
  grepping for return objects. Since `LLM::Function::Return` is a
  `Struct`, the splat operator expanded it into its member values
  instead of wrapping it, causing the grep to silently drop returns.
  The fix wraps both sources in an array before flattening.

### Change

* **Increase default provider timeout from 60s to 180s** <br>
  The default HTTP timeout for all providers has been increased from
  60 to 180 seconds to better accommodate long-running requests such
  as reasoning models and large structured outputs.

* **Change Anthropic default model to `claude-opus-4-8`** <br>
  The default Anthropic chat model has been updated from
  `claude-sonnet-4-20250514` to `claude-opus-4-8`, reflecting the
  latest model release from Anthropic.

* **Refresh model metadata** <br>
  Update model listings, pricing, and capabilities for Anthropic,
  AWS Bedrock, DeepInfra, Google, and xAI. Add Mistral model data
  to the registry.

## v12.1.0

Changes since `v12.0.0`.

This release adds `LLM::Agent#repl` with a curses-based
interactive read-eval-print loop. It requires the optional
dependency `curses` and it is probably the most notable
feature in this release.

Multiple _opt-in_ tools have been added to the `llm/tools/*.rb`
directory. They serve as examples and as general-purpose tools
that happen to power the repository's agents.

Other changes include small-ish bug fixes. <br>
As always, see the changelog details for a thorough overview.

### Add

* **Add `LLM::Agent#repl`** <br>
  Add a curses-based read-eval-print loop for `LLM::Agent` that lets
  developers interact with an agent after it has been set up or has
  performed a task. It is similar to `binding.irb`: once you exit,
  you can continue with the rest of your program. It requires the
  `curses` gem.

* **Add `#tracer=` setter on Provider, Context and Agent** <br>
  `LLM::Provider`, `LLM::Context` and `LLM::Agent` can now configure
  the tracer after initialization via the `#tracer=` setter. It accepts
  a subclass of `LLM::Tracer` or `nil` to disable the tracer.

* **Add `LLM::Tool::Shell`** <br>
  Add a built-in shell tool that can run a command with arguments. <br>
  It must be required explicitly with `require "llm/tools/shell"` and
  requires the `test-cmd.rb` gem.

* **Add `LLM::Tool::ReadFile`** <br>
  Add a built-in tool for reading the contents of a file, with optional
  `start` and `stop` line offsets. <br>
  It must be required explicitly with `require "llm/tools/read_file"`.

* **Add `LLM::Tool::Chdir`** <br>
  Add a built-in tool for changing the current working directory. <br>
  It must be required explicitly with `require "llm/tools/chdir"`.

* **Add `LLM::Tool::Git`** <br>
  Add a built-in tool that can perform git actions (`log`, `diff`,
  `show`, `commit`, `checkout`, `branch`). <br>
  It must be required explicitly with `require "llm/tools/git"` and requires the `test-cmd.rb` gem.

* **Add `LLM::Tool::Rg`** <br>
  Add a built-in tool that wraps the `rg` (ripgrep) command for
  recursively searching the current directory for patterns. <br>
  It must be required explicitly with `require "llm/tools/rg"` and requires the `test-cmd.rb` gem.

* **Add `LLM::Tool::SwapText`** <br>
  Add a built-in tool that can replace an exact snippet of text in a
  file with a new piece of text. <br>
  It must be required explicitly with `require "llm/tools/swap_text"`.

* **Add `LLM::Tool::Pwd`** <br>
  Add a built-in tool that returns the current working directory. <br>
  It must be required explicitly with `require "llm/tools/pwd"`.

* **Add `LLM::Tool::WriteFile`** <br>
  Add a built-in tool that can write a given string to a given file
  path. <br>
  It must be required explicitly with `require "llm/tools/write_file"`.

* **Add `LLM::Tool::Mkdir`** <br>
  Add a built-in tool that can create a tree of new directories. <br>
  It must be required explicitly with `require "llm/tools/mkdir"` and
  requires the `test-cmd.rb` gem.

### Change

* **Change LlamaCpp default port (8080 => 8013)** <br>
  The default port for the LlamaCpp provider has changed from `8080` to
  `8013` since llamacpp itself defaults to that port.

* **Change LlamaCpp default model to `nil`** <br>
  The default model for LlamaCpp is now `nil`, letting whatever model
  is served by the llamacpp server act as the default. Previously it
  defaulted to `qwen3`.

### Fix

* **Fix `LLM::Agent.tools` Symbol resolution** <br>
  When an agent defined tools via `tools :method_name`, the resolved
  symbol was incorrectly forwarded as `[:method_name]` (an array) to
  `LLM::Context`. This fix copies the same pattern used by other
  attribute resolvers (e.g., `skills`) so a single Symbol is resolved
  through the agent instance correctly.

* **Encode strings as UTF-8 in the JSON adapter** <br>
  The `json` gem will reject BINARY-encoded strings from version 3 and
  beyond. The `LLM::JSONAdapter.dump` method now walks serialized data
  and encodes every string into UTF-8, using `String#scrub` to replace
  bytes that are not valid UTF-8.
