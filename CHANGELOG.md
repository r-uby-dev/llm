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
> a [r.uby.dev](https://r.uby.dev) project

## What's next

These changes have not yet been released. <br>
They cover changes made since the last public
release `v11.3.1` and will be part of the next
major release: `v12.0.0`.

### Breaking

* **OpenAI: default to the Responses API** <br>
  The responses API has both models and features that are unavailable
  on the chat completions API, and the responses API appears to be
  the API of the future for OpenAI.

  Worth noting: the llm.rb implementation does **not** store state
  server-side by default. This can be changed with the `store: true`
  option. The legacy chat completions API can be accessed with the
  `mode: :completions` option.

  llm.rb has had support for the responses API for quite
  a while but it was not the default, and a number of bugs
  were found and fixed during the process of making it the
  default.

* **OpenAI: use gpt-image for image generation** <br>
  The `dalle` models are in the process of being deprecated, and support
  has been dropped from llm.rb. The `gpt-image` models are the next-generation
  image-generation models from OpenAI.

* **xAI: provide images as base64-encoded data** <br>
  Both xAI, and OpenAI had the option to generate images via a URL
  you can fetch, or as a base64-encoded string embedded directly
  in the response.

  OpenAI is moving away from the URL transport since deprecating dalle,
  and with that in mind, llm.rb has dropped support for the URL transport
  across all providers that supported it.

  Google, xAI, and OpenAI now consistently provide generated and modified
  images as a base64-encoded string.

* **ActiveRecord: yield `LLM::Agent` to `acts_as_agent`** <br>
  With this change we yield an instance of `LLM::Agent` to the `acts_as_agent`
  method, and drop the methods (such as `model`, `instructions`, etc) that
  were previously defined directly on the model. This keeps the number of
  methods that llm.rb adds to an ActiveRecord model at a minimum and retains
  the same capabilities as before.

* **Sequel: yield `LLM::Agent` to `plugin(:agent)`** <br>
  Ditto as above but for Sequel.

* **Remove the langsmith tracer** <br>
  This code was contributed by a third party but contains
  many anti-patterns that are against llm.rb conventions
  and best practices. It was merged without oversight or
  review, and basically against the ethos of open source.

  I also don't have a langsmith account to maintain the
  code. The alternative is the `LLM::Tracer::Telemetry` class
  that was originally written by me, and serves as a
  general-purpose OTP tracer.

### Add

* **Add a new provider: LLM::DeepInfra** <br>
  [DeepInfra](https://deepinfra.com) provide OpenAI-compatible
  endpoints for a large catalog of hosted open-source and
  open-weight models.

  Capabilities like tool calling, structured outputs, and
  reasoning can depend on the model.

* **Add new image provider: LLM::DeepInfra::Images** <br>
  [DeepInfra](https://deepinfra.com) provide access to
  diverse set of text-to-image models. Learn more about the
  available models on their [text-to-image models](https://deepinfra.com/models/text-to-image)
  page.

* **xAI: add `LLM::XAI::Images#edit`** <br>
  With this change it is possible to both generate images
  from a prompt, and edit an existing image with a prompt.
  xAI now has the same edit and create capabilities that
  OpenAI has.

* **Add `LLM::Schema.defaults`** <br>
  This method lets you map multiple property names to
  different default values. It is similar to `LLM::Schema.required`
  in the sense that it is called after the properties of
  a schema have been defined.

* **OpenAI: add local file support to the Responses API** <br>
  Our responses API implementation lacked local file support. <br>
  This change fixes that by supporting both image, document,
  and other media types that OpenAI may support.

* **Add `LLM::Response#id` across all providers**
  This method was previously implemented via `method_missing`,
  and the field name could change depending on the provider.
  The new method is a catch-all that provides a single method
  that works across all providers.

### Fix

* **Fix Google `temperature` parameter fall-through** <br>
  Ensure provider-level `temperature` and other `generationConfig`
  parameters are forwarded to the API correctly instead of being
  silently dropped.

* **Fix Google `generationConfig` collisions** <br>
  Prevent duplicate or conflicting `generationConfig` keys in the
  Google request adapter.

### Change

* **Change OpenAI defaults** <br>
  The default chat model is now `gpt-5.4-mini`. <br>
  The default image model is now `gpt-image`.

* **Change google defaults** <br>
  The default chat model is now `gemini-3.1-flash-lite` <br>
  The default embeddings model is now `gemini-embedding-2`

* **Change xAI defaults** <br>
  The default chat model is now `grok-4.3`. <br>
  The default image model is now `grok-imagine-image-quality`.

* **Return an `LLM::Object` from `LLM::Response#content!`** <br>
  The Hash-like, indifferent access data structure known as
  `LLM::Object` provides a convenient interface around a Hash
  object. It allows method access via `obj.key`, and decays
  into a Hash in many cases.

  The `LLM::Response#content!` method now wraps its content
  in an `LLM::Object` but only after it has parsed its
  content (a JSON string) into a Ruby data structure.

* **Refresh model metadata** <br>
  Update `data/*.json` files with current provider model listings,
  pricing, and capabilities.

## v11.3.1

Changes since `v11.3.0`.

This release rebrands the project under the r.uby.dev umbrella, removes
the Jekyll-based docs site in favor of a pure-markdown deepdive, and
cleans up YARD documentation across the codebase.

### Change

* **Rebrand to r.uby.dev** <br>
  Update README.md with the new logo, streamlined copy, and r.uby.dev
  URLs. Rewrite `resources/deepdive.md` as a concise walkthrough and
  bundle it with the gem. Remove the `docs/` directory (Jekyll site).
  Update all references from `llmrb.github.io` to `r.uby.dev`.

* **Update gemspec** <br>
  Update homepage, metadata URLs, email, and author list. Switch the
  YARD markdown processor from kramdown to redcarpet.

### Fix

* **Fix YARD documentation** <br>
  Fix unnamed, misnamed, and missing `@param` tags across provider
  adapters, transport classes, stream, tool, schema, registry, agent,
  and ActiveRecord integration files. Fix backtick-wrapped constant
  references and other YARD formatting issues.

## v11.3.0

Changes since `v11.2.0`.

This release promotes `LLM::Agent` as the default high-level runtime,
raises `LLM::NotFoundError` for provider 404 responses, and adds
Symbol resolution to `LLM::Agent.confirm` and `LLM::Agent.skills` for
dynamic tool confirmation and skill lists.

### Add

* **Raise `LLM::NotFoundError` for provider 404 responses** <br>
  Raise `LLM::NotFoundError` when a provider returns HTTP 404. One
  example is calling the embeddings API on DeepSeek
  (`LLM.deepseek(...).embed(["foobar"])`), which returns 404 because
  DeepSeek does not implement that endpoint.

* **Add Symbol resolution to `LLM::Agent.confirm`** <br>
  When `confirm` receives a single Symbol argument, it stores it
  as-is instead of converting it to a string array. At initialization
  time, `resolve_option` resolves the Symbol by calling the method
  with that name on the agent instance, and the result is converted
  to strings. This allows dynamic tool confirmation lists:

      class MyAgent < LLM::Agent
        confirm :tools_that_need_confirmation

        def tools_that_need_confirmation
          some_condition ? %w[delete destroy] : %w[delete]
        end
      end

  Ported from llmrb/mruby-llm@89a232e3 and @2dd04e2d.

  Extend the same pattern to `LLM::Agent.skills` so the skills DSL
  accepts a Symbol that resolves through the agent instance at
  initialization time.

### Change

* **Clarify `LLM::Agent` as the default high-level runtime** <br>
  Document that `LLM::Context` remains at the heart of llm.rb, but
  `LLM::Agent` is the better default unless an application needs advanced
  manual tool loops. `LLM::Agent` manages the tool loop for callers and
  enables guards against runaway or repeated tool-call loops.

## v11.2.0

Changes since `v11.1.0`.

This release adds `LLM::Function#skill?` and `LLM::Tool#skill?` so
callers can inspect whether a function or tool is backed by a skill.

It introduces `LLM::Transport::Request` as a transport-agnostic request
object so providers no longer depend directly on `Net::HTTP` request
classes, and adds an optional Curb (libcurl) backend alongside symbolic
transport shortcuts such as `transport: :curb`.

MCP and A2A clients now accept `persistent: true` matching provider configuration.
Several fixes land for tool return callback emission, function comparison by
tool call ID, function array filtering, skill tool inheritance, and JSON generator
state compatibility on Ruby 4.

### Add

* **Add `LLM::Function#skill?`** <br>
  Add `skill?` to `LLM::Function` so callers can check whether a
  function is backed by a skill tool.

* **Add `LLM::Tool.skill?` and `LLM::Tool#skill?`** <br>
  Add class-level `skill?` and instance-level `skill?` to
  `LLM::Tool`, matching the existing `mcp?` and `a2a?` pattern.

* **Add `LLM::Transport::Request`** <br>
  Add `LLM::Transport::Request` as a transport-agnostic request object
  and update providers to build requests without depending directly on
  Net::HTTP request classes. The built-in Net::HTTP transports still
  accept existing Net::HTTP request objects through a compatibility
  bridge, while alternative transports can handle the generic request
  shape directly.

* **Add optional Curb transport support** <br>
  Add `LLM::Transport::Curb`, an optional libcurl-backed transport
  that can be selected with `transport: :curb`. Providers already
  emit `LLM::Transport::Request` objects, so the Curb backend can
  execute requests without routing through Net::HTTP.

* **Add symbolic transport shortcuts** <br>
  Allow providers, MCP HTTP clients, and A2A HTTP clients to accept
  transport shortcuts such as `transport: :curb` and
  `transport: :net_http_persistent`.

* **Add persistent HTTP selection to MCP and A2A clients** <br>
  Allow MCP and A2A HTTP clients to accept `persistent: true`, matching
  provider configuration and selecting the persistent Net::HTTP
  transport by default.

### Fix

* **Support JSON generation state on Ruby 4** <br>
  Handle JSON generator state objects in the standard JSON adapter so
  schema objects serialize correctly when Ruby 4 calls custom `to_json`
  methods during provider request generation.

* **Emit tool return callbacks for direct context waits** <br>
  Emit `LLM::Stream#on_tool_return` when `LLM::Context#wait` executes
  pending tool work directly instead of draining `LLM::Stream::Queue`.

* **Emit confirmed tool return callbacks once** <br>
  Emit `LLM::Stream#on_tool_return` for confirmed and cancelled tool
  calls, and exclude confirmed functions from later waits so mixed
  confirmed and unconfirmed tool batches do not execute confirmed tools
  twice.

* **Compare functions by tool call ID** <br>
  Add `LLM::Function#==`, `#eql?`, and `#hash` so pending function
  collections can compare tool calls by provider-assigned ID instead of
  object identity.

* **Preserve function array behavior after filtering** <br>
  Preserve `LLM::Function::Array` behavior when subtracting function
  arrays so filtered tool batches can still spawn through the normal
  function array API.

* **Prevent skills from inheriting skill-backed tools** <br>
  Exclude skill-backed tools when a skill sub-agent uses `tools:
  inherit`, preventing skills loaded through a parent context from
  being recursively exposed to nested skill agents.

## v11.1.0

Changes since `v11.0.0`.

This release adds the `inherit` directive for skill sub-agents so they can
inherit access to the local, MCP, and A2A tools available to their parent
agent. It introduces class-level `required %i[...]` declarations to
`LLM::Schema` and wraps `LLM::Function#arguments` in `LLM::Object` for
method-style argument access. The OpenTelemetry tracer now samples all spans
regardless of environment, and the tool-call loop repair step prevents stale
history from being sent on follow-up requests.

### Add

* **Add support for the `inherit` directive in skills** <br>
  Add support for the `inherit` directive so a skill sub-agent can
  inherit access to the local, MCP, and A2A tools available to its
  parent agent.

* **Add class-level `required %i[...]` support to `LLM::Schema`** <br>
  Add class-level `required %i[...]` declarations to `LLM::Schema`, so
  schema classes can mark existing properties as required the same way
  `LLM::Tool` params already can.

* **Wrap function arguments in `LLM::Object`** <br>
  Wrap `LLM::Function#arguments` in `LLM::Object`, so function
  implementations can read arguments with method-style access while
  still invoking runners with keyword arguments.

### Fix

* **Ensure all traces are sampled regardless of environment** <br>
  Explicitly pass `Samplers::ALWAYS_ON` when creating the OpenTelemetry
  `TracerProvider` so the in-memory exporter always captures every span,
  regardless of the `OTEL_TRACES_SAMPLER` environment variable.

* **Always close the tool call loop before sending follow-up requests** <br>
  Add a repair step in `Context#talk` that closes assistant tool-call
  messages without matching tool responses before the next provider
  request is sent. This prevents stale tool-call history from being sent
  on follow-up requests, which some providers reject as invalid.

## v11.0.0

Changes since `v10.0.0`.

This release removes several deprecated or unused APIs, including the `#chat`
alias from contexts and agents, the `LLM::Function#register` alias, and the
unused positional `llm` argument from MCP constructors. Generated MCP and A2A
tools are no longer added to the global tool registry by default.

On the additions side, it introduces the A2A (Agent2Agent) protocol client,
a new `#ask` convenience interface on contexts and agents, one-shot stdio MCP
requests outside `#session`, `LLM::Function#def` as a short alias for
`LLM::Function#define`, `LLM::File#exist?`, and `LLM::Tool.a2a?`.

### Breaking

* **Remove the unused `llm` argument from MCP clients** <br>
  Remove the unused positional `llm` argument from `LLM::MCP.new`,
  `LLM::MCP.stdio`, `LLM::MCP.http`, and `LLM.mcp`.

* **Stop globally registering generated MCP and A2A tools** <br>
  Generated tools returned by `LLM::Tool.mcp(...)` and
  `LLM::Tool.a2a(...)` are no longer added to the global
  `LLM::Tool.registry` or `LLM::Function.registry`. They still work
  when passed directly to a context or agent, but registry-based lookup
  now only sees normal loaded `LLM::Tool` subclasses.

* **Remove `LLM::Function#register`** <br>
  Remove the `LLM::Function#register` alias and prefer
  `LLM::Function#define` or `LLM::Function#def` when binding a
  function to its implementation. The `register` alias was too easy to
  confuse with the class-level `LLM::Tool.register` and
  `LLM::Function.register` registry APIs.

* **Remove the `#chat` alias from contexts and agents** <br>
  Remove the `LLM::Context#chat` and `LLM::Agent#chat` aliases. Prefer
  `#talk` for all context and agent turns.

### Add

* **Add `LLM::Function#def`** <br>
  Add `LLM::Function#def` as a short alias for
  `LLM::Function#define` when binding a function instance to its
  implementation.

* **Add `LLM::MCP#session`** <br>
  Add `LLM::MCP#session` as an alias for `LLM::MCP#run`, and prefer it
  in examples for scoped stdio MCP sessions that should stay alive
  across discovery and tool calls.

* **Add `#ask` to contexts and agents** <br>
  Add `LLM::Context#ask` and `LLM::Agent#ask` as a RubyLLM-compatible
  convenience interface over `#talk`. `#ask` accepts a prompt, optional
  `with:` attachments, an optional `stream:` target, and an optional
  block for streamed chunks, and returns an `LLM::Response`.

* **Add `LLM::File#exist?`** <br>
  Add `LLM::File#exist?` as a small convenience wrapper for checking
  whether a local file exists on disk.

* **Allow one-shot stdio MCP requests outside `#session`** <br>
  Allow `mcp.tools`, `mcp.prompts`, `mcp.find_prompt(...)`, and
  `mcp.call_tool(...)` to work outside `mcp.session` by starting and
  stopping a stdio transport on demand when needed. This makes stdio
  MCP usable without an explicit session block, while keeping
  `mcp.session` as the preferred pattern for efficient, stateful
  stdio workflows.

* **Add A2A client support** <br>
  Add `LLM::A2A`, a client for the Agent2Agent (A2A) protocol with
  REST and JSON-RPC bindings. Remote agent skills can be exposed as
  `LLM::Tool` classes and used through `LLM::Context` or `LLM::Agent`,
  and the client also supports direct messaging, streaming, task
  operations, push notification configuration, extended agent cards,
  persistent HTTP transport selection, and optional REST `base_path`
  prefixing.

  Refactor shared MCP/A2A HTTP transport setup into
  `LLM::Transport::Utils`, and extend
  `LLM::Transport::StreamDecoder` to accept a callback block directly.

* **Add `LLM::Tool.a2a?`** <br>
  Add `LLM::Tool.a2a?` and mark generated A2A-backed tool classes so
  callers can distinguish them from local or MCP tools.

### Fix

* **Fix context and agent JSON serialization through `LLM.json`** <br>
  Fix `LLM::Context#to_json` and `LLM::Agent#to_json` to serialize
  through `LLM.json.dump(...)` instead of plain `to_json`.

* **Fix block-form ORM agent DSL forwarding** <br>
  Fix block-form `model { ... }`, `tools { ... }`, and
  `schema { ... }` declarations in the ActiveRecord and Sequel agent
  wrappers so persisted agent models configure the internal agent class
  the same way `LLM::Agent` does.

* **Fix missing `skills` in ORM agent wrappers** <br>
  Fix the ActiveRecord and Sequel agent wrappers to expose `skills`, so
  persisted agent models can declare skills the same way as
  `LLM::Agent`.

* **Fix `acts_as_agent#ctx` return type** <br>
  Fix the ActiveRecord `acts_as_agent` wrapper so its `ctx` helper
  returns the wrapped `LLM::Agent` instead of returning the underlying
  `LLM::Context` directly.

## v10.0.0

Changes since `v9.0.0`.

This release removes the `LLM::Context#respond` method, and
also removes the deprecated `LLM::Bot` alias. **All** class-level
agent tunables can now be resolved lazily via a Symbol (method name),
or a Proc. The `LLM::Agent` class can now confirm a tool call
before it happens, and the `LLM::Schema` class has been extended
to support `Array[String,Integer]` as a shorthand for
`Array[AnyOf[String, Integer]]`. The `LLM::Stream` class has
had its public method surface reduced to help avoid accidental
collisions.

### Breaking

* **Unify context turns under `#talk`** <br>
  Remove `LLM::Context#respond` and route responses-mode turns through
  `LLM::Context#talk` with `mode: :responses` instead.

* **Remove the `LLM::Bot` alias** <br>
  Remove the backward-compatible `LLM::Bot` alias for `LLM::Context`.
  Use `LLM::Context` directly instead.

### Add

* **Add shared option resolution through `LLM::Utils`** <br>
  Add `LLM::Utils.resolve_option` for resolving configured values as
  literals, procs, symbol-named methods, or duplicated hashes, and use
  it in agent and ORM option resolution paths.

* **Resolve all class-level agent tunables via Proc** <br>
  Let `model`, `tools`, `skills`, `schema`, `stream`, and `tracer`
  declared with a block be lazily evaluated against the agent instance
  at initialization time, matching how `stream` and `tracer` already
  worked.

  Add `LLM::Agent#params` for direct access to the underlying context
  parameters.

  Ported from mruby-llm.

* **Support `Array[...]` schema and tool param types** <br>
  Let `LLM::Schema` properties and `LLM::Tool` params accept
  `Array[...]` type declarations, including mixed item unions that are
  serialized as `anyOf` array items.

* **Add `LLM::Provider#key?`** <br>
  Add `key?` to providers so callers can check whether a non-blank API
  key has been configured.

* **Add agent tool confirmation hooks** <br>
  Add `LLM::Agent.confirm` and `LLM::Agent#on_tool_confirmation` so
  selected tools can be approved or cancelled before execution. Pending
  tool resolution now relies on `LLM::Context#functions` so confirmed
  tools are not executed twice when mixed with unconfirmed tool calls.

* **Add `LLM::Function#spawn(:call).wait`** <br>
  Add task-shaped sequential execution support for direct
  `LLM::Function#spawn(:call).wait`.

### Fix

* **Reduce private internal methods on `LLM::Stream`** <br>
  Remove `tool_not_found` and `__tools__` from `LLM::Stream`. The
  `__tools__` logic is inlined directly into `__find__` since that
  was its only caller. The `tool_not_found` utility method was unused
  externally and added unnecessary surface to LLM::Stream.

  Ported from mruby-llm.

## v9.0.0

Changes since `v8.1.0`.

This release deepens llm.rb's transport and cost-tracking surface. It
replaces the old mutable `persist!` API with constructor-driven transport
selection, removes `#call` from contexts and agents in favor of explicit
`ctx.wait(:call)`, makes queued stream waits strategy-free, and deletes
the unused `LLM::Utils` module.

It adds cache read/write token tracking
with corresponding cost components, audio and image token pricing,
`LLM::Context#functions?` for queue-aware tool loops,
`LLM::Agent.stream` DSL support, and exposes `#stream` readers on
contexts and agents.

The HTTP transport layer has been refactored around shared backends so
providers, MCP, and custom transports all use the same normalized
response interface.

### Breaking

* **Remove `#call` as a context and agent tool-loop API** <br>
  Remove `LLM::Context#call(:functions)` and `LLM::Agent#call(:functions)`.
  Tool loops should use `ctx.wait(:call)` or `agent.wait(:call)` instead.
  The ActiveRecord and Sequel wrappers no longer expose `#call` passthroughs
  for stored llm.rb contexts.

* **Make HTTP transport selection constructor-driven** <br>
  Remove public `persist!` and `.persistent` mutation APIs from
  providers, transports, and MCP clients. Select persistent behavior at
  construction time with `persistent: true`, `LLM::Transport.net_http`,
  `LLM::Transport.net_http_persistent`, or an explicit `transport:`
  override.

* **Make queued stream waits strategy-free** <br>
  Change `LLM::Stream::Queue#wait` to resolve queued work by the actual
  task types already present in the queue instead of accepting an
  external wait strategy. `LLM::Stream#wait(...)` remains compatible but
  now ignores its arguments when delegating to the queue.

* **Remove unused `LLM::Utils`** <br>
  Delete the `LLM::Utils` module and remove its remaining unused
  provider includes and top-level require.

### Add

* **Expose `#stream` readers on contexts and agents** <br>
  Add public `LLM::Context#stream` and `LLM::Agent#stream` accessors so
  callers can inspect the active stream object directly.

* **Track cache read and write tokens in usage** <br>
  Add `cache_read_tokens` and `cache_write_tokens` to `LLM::Usage` and
  preserve them through completion usage adaptation and context usage
  aggregation.

* **Add `LLM::Context#functions?` for queue-aware tool loops** <br>
  Add `functions?` to `LLM::Context` and the ActiveRecord and Sequel
  wrappers so callers can detect pending tool work through either the
  bound stream queue or unresolved functions, and update the docs to
  prefer `while ctx.functions?` over `ctx.functions.any?` in tool-loop
  examples.

* **Add `:call` as a first-class wait strategy** <br>
  Add `:call` to pending-function wait paths so `ctx.wait(:call)` can
  prefer queued streamed work when present and otherwise fall back to
  direct sequential function execution through `spawn(:call).wait`.

* **Read provider cache usage into completion responses** <br>
  Read cache read tokens from provider usage metadata, including OpenAI
  `usage.prompt_tokens_details` and Anthropic
  `usage.cache_read_input_tokens`. Read Anthropic cache write tokens
  from `usage.cache_creation_input_tokens`, and expose explicit
  zero-valued `cache_write_tokens` methods on providers that do not
  report cache creation usage.

* **Extend cost tracking with cache write pricing** <br>
  Extend `LLM::Cost` with `cache_read_costs`, `cache_write_costs`, and
  `reasoning_costs` alongside the existing `input_costs` and
  `output_costs`. Add `#to_h` for structured cost insight and update
  `ctx.cost` to calculate all available components from registry
  pricing data.

* **Price input and output audio separately** <br>
  Track `input_audio_tokens` and `output_audio_tokens` in usage and
  include `input_audio_costs` and `output_audio_costs` in `LLM::Cost`
  so multimodal requests report accurate audio spend.

* **Track image tokens in input cost reporting** <br>
  Add `input_image_tokens` to usage and include `input_image_costs` in
  `LLM::Cost` using the model's generic input rate so image-bearing
  prompts report their input spend.

* **Add `LLM::Agent.stream` DSL support** <br>
  Let agents define a default `stream` through the class DSL, including
  block-based stream construction so each agent instance can resolve its
  stream the same way `tracer` does.

### Change

* **Refactor HTTP transports around shared backends** <br>
  Split `Net::HTTP` and `Net::HTTP::Persistent` into separate
  `LLM::Transport` implementations, move HTTP-specific request helpers
  and response execution into the shared transport layer, and let MCP
  HTTP wrap those transports instead of maintaining a separate
  transient/persistent client split.

* **Share transport overrides across providers and MCP** <br>
  Let both provider construction and `LLM::MCP.http(...)` accept
  `LLM::Transport` instances or classes as HTTP transport overrides, so
  callers can reuse the same transport implementation across the
  runtime.

* **Let custom transports adapt their own response objects** <br>
  Introduce a transport response interface so custom transports can
  adapt backend-specific response objects to one normalized shape and
  have them work with the existing provider execution and error-handling
  code.

## v8.1.0

Changes since `v8.0.0`.

This release adds Amazon Bedrock provider support through the Converse
API, including AWS SigV4 request signing, event stream decoding,
structured output through `schema:`, and a models.dev-backed registry.
It exposes `llm.models.all` for Bedrock via the ListFoundationModels
API and adds `LLM::Object#transform_values!` for in-place value
transformation. Several Bedrock-specific fixes land as well, including
response id exposure, blank text block suppression in tool turns, and
DSML tool-marker filtering in streamed text.

### Add

* **Add AWS Bedrock provider support** <br>
  Add `LLM.bedrock(...)` with Bedrock Converse chat support, AWS SigV4
  request signing, Bedrock event stream decoding, structured output
  support through `schema:`, and models.dev-backed `bedrock.json`
  registry generation.

* **Add AWS Bedrock Models endpoint support** <br>
  Add `llm.models.all` for Bedrock via the ListFoundationModels API,
  including SigV4 signing for the control-plane endpoint and normalized
  `LLM::Model` collection responses.

* **Add `LLM::Object#transform_values!`** <br>
  Let `LLM::Object` transform stored values in place through
  `#transform_values!`.

### Fix

* **Expose response ids on Bedrock completion responses** <br>
  Read the Bedrock request id into `LLM::Response#id` for completion
  responses adapted from the Converse API.

* **Avoid blank assistant text blocks in Bedrock tool turns** <br>
  Stop replaying assistant tool-call messages with empty text content
  blocks that Bedrock rejects.

* **Suppress Bedrock DSML tool markers in streamed text** <br>
  Filter `"\u003c\u003cDSML\u003efunction_calls\u003e\u003e"` markers out of streamed Bedrock
  assistant text so tool-call sentinels do not leak into user-visible
  output.

## v8.0.0

Changes since `v7.0.0`.

This release adds Unix-fork concurrency for process-isolated tool
execution, extends `LLM::Object` with `#merge` and `#delete`, and drops
Ruby 3.2 support due to a segfault observed with the `:fork` path. It
promotes `LLM::Pipe` to the top-level namespace and adds
`persistent: true` on `LLM::MCP.http` for direct persistent transport
configuration. `LLM::Function#runner` is exposed as public API, agent
tracer overrides are supported, fiber execution now uses `Fiber.schedule`,
missing optional dependencies raise clearer `LLM::LoadError` guidance,
and ActiveRecord wrapper plumbing is deduplicated between `acts_as_llm`
and `acts_as_agent`.

### Breaking

* **Drop Ruby 3.2 support** <br>
  Stop supporting Ruby 3.2 due to a segfault observed with the `:fork`
  tool concurrency strategy.

### Add

* **Add `LLM::Object#merge`** <br>
  Let `LLM::Object` return a new wrapped object when merging hash-like
  data through `#merge`.

* **Add `LLM::Object#delete`** <br>
  Let `LLM::Object` delete keys directly through `#delete`.

### Change

* **Add fork-based tool concurrency** <br>
  Add `:fork` as a new concurrency strategy for `LLM::Function#spawn`,
  `LLM::Function::Array#wait`, and `LLM::Agent.concurrency` that runs
  class-based tools in isolated child processes. Fork-backed tools support
  tracer callbacks, `on_interrupt`/`on_cancel` hooks, and `alive?` checks.
  Requires the `xchan` gem for inter-process communication with `:fork`.
  This is especially useful for tools that need process isolation, such as
  running shell commands or handling unsafe data.

* **Promote `LLM::Pipe` from MCP namespace to top-level** <br>
  Move `LLM::MCP::Pipe` to `LLM::Pipe` so the pipe abstraction is available
  outside MCP internals. The new class adds a `binmode:` option for binary
  pipes. `LLM::MCP::Command` and related MCP transport code have been updated
  to use `LLM::Pipe`.

* **Allow `persistent: true` on `LLM::MCP.http`** <br>
  Let `LLM::MCP.http(...)` enable persistent HTTP transport directly
  through `persistent: true` at construction time.

* **Expose `LLM::Function#runner` as public API** <br>
  Promote the internal runner instantiation to a public `runner` method on
  `LLM::Function`, so callers can inspect or reuse the resolved tool instance
  that a function wraps.

* **Allow agent instance tracer overrides** <br>
  Let `LLM::Agent.new(..., tracer: ...)` override the class-level tracer
  for that agent instance.

* **Make `:fiber` use scheduler-backed fibers** <br>
  Change `:fiber` tool execution to use `Fiber.schedule` and require
  `Fiber.scheduler`, instead of wrapping direct calls in raw fibers. This
  gives `:fiber` a real cooperative concurrency model instead of acting as
  a thin wrapper around sequential execution.

* **Read stored values from zero-argument `LLM::Object` method calls** <br>
  Let calls like `obj.delete`, `obj.fetch`, `obj.merge`, `obj.key?`,
  `obj.dig`, `obj.slice`, or `obj.keys` return a stored value when that
  method name exists as a key and no arguments are given.

* **Harden `LLM::Object` against arbitrary key names** <br>
  Move internal lookup logic off `LLM::Object` instances and onto the
  singleton class instead, making stored keys like `method_missing`
  more resilient while preserving normal dynamic field access.

* **Deduplicate ActiveRecord wrapper plumbing** <br>
  Move shared ActiveRecord wrapper defaults and utility methods into
  `LLM::ActiveRecord`, reducing duplication between `acts_as_llm` and
  `acts_as_agent`.

* **Raise clearer errors for missing optional runtime dependencies** <br>
  Route optional `async`, `xchan`, and `net/http/persistent` loads
  through `LLM.require` so missing runtime gems raise `LLM::LoadError`
  with installation guidance instead of leaking raw `LoadError`
  exceptions.

### Fix

* **Avoid `RuntimeError` from `Async::Task.current` lookups** <br>
  Check `Async::Task.current?` before reading the current Async task so
  provider transports fall back to `Fiber.current` without raising when
  no Async task is active.

* **Serialize `LLM::Object` values correctly through `LLM.json`** <br>
  Make `LLM::Object#to_json` call `LLM.json.dump(to_h, ...)` so
  `LLM::Object` values serialize through the llm.rb JSON adapter.

## v7.0.0

Changes since `v6.1.0`.

This release turns agent tool-loop limit errors into in-band advisory
returns so the LLM can react to rate limits and continue the loop. It
adds `tool_attempts: nil` as a way to opt out of advisory tool-limit
returns entirely, and fixes the default provider HTTP path to keep
`net-http-persistent` optional when not explicitly enabled.

### Breaking

* **Return in-band tool-loop limit errors from agents** <br>
  Stop raising `LLM::ToolLoopError` when an agent exhausts its tool loop
  attempt budget, and instead send advisory `LLM::Function::Return`
  errors back through the model so the LLM can react to the rate limit
  in-band and continue the loop.

* **Allow `tool_attempts: nil` to disable advisory tool-limit returns** <br>
  Keep the default `tool_attempts` budget at `25`, but treat an explicit
  `tool_attempts: nil` as an opt-out that disables advisory tool-limit
  returns entirely.

### Fix

* **Keep `net-http-persistent` optional on normal HTTP requests** <br>
  Stop the default provider HTTP path from loading `net/http/persistent`
  unless persistent transport support is explicitly enabled.

## v6.1.0

Changes since `v6.0.0`.

This release tightens interrupt and compaction behavior for long-running
contexts. It adds `LLM::Buffer#rindex`, supports percentage-based token
thresholds in `LLM::Compactor`, tracks persisted compaction state through
context serialization, reliably interrupts Async-backed requests, preserves
valid tool-call history on cancellation, keeps concurrent skill tool loops
running on streamed agents, and returns zero-valued usage objects when no
provider usage has been recorded yet.

### Change

* **Add `LLM::Buffer#rindex`** <br>
  Add `LLM::Buffer#rindex` as a direct forward to the underlying message
  array so callers can find the last matching message index through the
  buffer API.

* **Support percentage compaction token thresholds** <br>
  Let `LLM::Compactor` accept `token_threshold:` values like `"90%"` so
  compaction can trigger at a percentage of the active model context
  window.

### Fix

* **Interrupt Async-backed requests reliably** <br>
  Track request ownership through the provider transport so contexts use
  the active Async task when available, letting `ctx.interrupt!`
  reliably cancel streamed requests under Async runtimes and surface
  them as `LLM::Interrupt`.

* **Preserve valid tool-call history on cancellation** <br>
  Append cancelled tool-return messages for unresolved tool calls during
  `ctx.interrupt!` so follow-up provider requests do not fail with
  invalid tool-call history after pending tool work is cancelled.

* **Preserve concurrent skill tool loops on streamed agents** <br>
  Propagate the active agent concurrency through the effective request
  stream so nested skill agents keep using queued `wait(...)` tool
  execution instead of falling back to direct `:call` execution.

* **Track persisted compaction state on contexts** <br>
  Mark contexts as compacted after `LLM::Compactor#compact!`, persist and
  restore that state through context serialization, and clear it after the
  next successful model response.

* **Return zero-valued usage objects from contexts** <br>
  Make `LLM::Context#usage` consistently return an `LLM::Object`, using a
  zero-valued usage object when no provider usage has been recorded yet.

## v6.0.0

Changes since `v5.4.0`.

This release simplifies the ORM persistence contract around serialized
`data` state, removing the assumption of reserved `provider`, `model`, and
usage columns. Provider selection must now come from `provider:` hooks,
model defaults come from `context:` or agent DSL, and usage is read from the
serialized runtime state. Alongside this breaking change, Sequel JSON and
JSONB persistence is fixed, ractor-backed tools now fire tracer callbacks,
and `LLM::RactorError` is raised for unsupported ractor tool work.

### Change

* **Simplify ORM persistence to serialized `data` state** <br>
  Change the built-in ActiveRecord and Sequel wrappers to treat serialized
  `data` as the persistence contract, instead of assuming reserved
  `provider`, `model`, and usage columns. Provider selection must now come
  from `provider:` hooks that resolve a real `LLM::Provider` instance, model
  defaults come from `context:` or agent DSL, and `usage` is read from the
  serialized runtime state.

### Fix

* **Fix Sequel JSON and JSONB persistence** <br>
  Load Sequel PostgreSQL JSON support when `plugin :llm` is configured with
  `format: :json` or `:jsonb`, and wrap structured payloads correctly so
  persisted context state can be stored in PostgreSQL JSON columns.

* **Trace ractor-backed tool callbacks** <br>
  Make tool tracers fire `on_tool_start` and `on_tool_finish` for
  class-based `:ractor` execution too, so ractor-backed tool calls show up
  in tracer callbacks like the other concurrent tool paths.

* **Raise `LLM::RactorError` for unsupported ractor tool work** <br>
  Add `LLM::RactorError` and fail fast when `:ractor` execution is requested
  for unsupported tool types such as skill-backed tools, instead of letting
  deeper Ruby isolation errors leak out later in execution.

* **Delegate interrupt to concurrent task implementations** <br>
  Make `LLM::Function::Task#interrupt!` delegate to the underlying fork or
  ractor task when it supports interruption, so `ctx.interrupt!` and
  `task.interrupt!` work correctly for fork- and ractor-backed tool
  execution.

## v5.4.0

Changes since `v5.3.0`.

This release expands tracer support around agentic execution. It lets
`LLM::Agent` define scoped tracers through the agent DSL and fixes concurrent
tool execution so those scoped tracers stay attached when work crosses
thread, task, fiber, and skill boundaries.

### Change

* **Add agent-scoped tracers** <br>
  Let `LLM::Agent` classes define `tracer ...` or `tracer { ... }` so an
  agent can carry its own tracer without replacing the provider's default
  tracer. The resolved tracer is scoped to that agent's turns, tool loops,
  and pending tool access. Available through the `acts_as_agent` and Sequel
  agent plugin `tracer` DSL too.

### Fix

* **Preserve scoped tracers across concurrent tool work** <br>
  Keep agent- and request-scoped tracers attached when tool execution
  crosses `:thread`, `:task`, or `:fiber` boundaries, including skill
  execution, so spawned work does not fall back to the provider default
  tracer.

## v5.3.0

Changes since `v5.2.1`.

This release deepens llm.rb's request-rewriting and tool-definition surface.
It adds transformer lifecycle hooks to `LLM::Stream` so UIs can surface work
like PII scrubbing before a request is sent, and it adds a more explicit
OmniAI-style tool DSL form with `parameter` plus separate `required`
declarations while keeping the older `param ... required: true` style working.

### Change

* **Add transformer stream lifecycle hooks** <br>
  Add `on_transform` and `on_transform_finish` to
  `LLM::Stream` so UIs can surface request rewriting work such as PII
  scrubbing before a request is sent to the model.

* **Add a separate `required` tool DSL form** <br>
  Add `parameter` as an alias of `param` and support `required %i[...]`
  as a separate declaration, inspired by OmniAI-style tools, while keeping
  the existing `param ... required: true` form working too.

## v5.2.1

Changes since `v5.2.0`.

This release tightens the streamed queue fix from `v5.2.0` for concurrent
workloads. Request-local streams now stay bound long enough for `wait` to
drain queued work and then clear cleanly so later waits fall back to the
context's configured stream.

### Fix

* **Reset request-local streams after `wait` drains queued work** <br>
  Keep per-call `stream:` bindings alive through `LLM::Context#wait` so
  queued streamed tool work still resolves correctly, then clear the
  request-local stream after the wait completes to avoid leaking it into
  later turns.

## v5.2.0

Changes since `v5.1.0`.

This release adds current DeepSeek V4 support through refreshed provider
metadata, including `deepseek-v4-flash` and `deepseek-v4-pro`, while fixing
request-local queue handling for concurrent streamed workloads so `wait` and
interruption use the active per-call stream correctly.

### Change

* **Add `LLM::MCP#run` for scoped MCP client lifecycle** <br>
  Add `LLM::MCP#run` so MCP clients can be started for the duration of a
  block and then stopped automatically, which simplifies the usual
  `start`/`stop` pattern in examples and application code.

* **Refresh provider model metadata** <br>
  Add current DeepSeek and OpenAI model metadata to `data/` and update the
  Google Gemini model entry to match the current provider naming.

### Fix

* **Reject unsupported DeepSeek multimodal prompt objects early** <br>
  Raise `LLM::PromptError` for `image_url`, `local_file`, and
  `remote_file` in DeepSeek chat requests instead of sending invalid
  OpenAI-compatible payloads that the provider rejects at runtime.

* **Preserve DeepSeek reasoning content across tool turns** <br>
  Replay `reasoning_content` when serializing prior assistant messages for
  DeepSeek chat completions, so thinking-mode tool calls can continue into
  follow-up requests without triggering invalid request errors.

* **Default DeepSeek to `deepseek-v4-flash`** <br>
  Change `LLM::DeepSeek#default_model` to `deepseek-v4-flash` so new
  contexts and default provider usage align with the current preferred chat
  model.

* **Use per-call streams when waiting on streamed tool work** <br>
  Track request-local streams bound through `talk(..., stream:)` and
  `respond(..., stream:)` so `LLM::Context#wait` and interruption-aware
  queue handling use the active stream instead of falling back to pending
  function spawning.

## v5.1.0

Changes since `v5.0.0`.

This release tightens streamed tool execution around the actual request-local
runtime state. It fixes streamed resolution of per-request tools and makes
that streamed path work cleanly with `LLM.function(...)`, MCP tools, bound
tool instances, and normal tool classes.

### Fix

* **Resolve request-local tools during streaming** <br>
  Resolve streamed tool calls through `LLM::Stream` request-local tools
  before falling back to the global registry, so per-request tools and bound
  tool instances work correctly during streaming.

* **Support `LLM.function(...)` and MCP tools in streamed tool resolution** <br>
  Let streamed tool resolution use the current request tool set, so
  `LLM.function(...)`, MCP tools, bound tool instances, and normal
  `LLM::Tool` classes all work through the same streamed tool path.

## v5.0.0

Changes since `v4.23.0`.

This release expands llm.rb from an execution runtime into a more explicit
supervision and transformation runtime. It adds context-level guards,
transformers, and loop supervision through `LLM::LoopGuard`, while deepening
long-lived context behavior through compaction, interruption hooks, and
streamed `ctx.spawn(...)` tool execution.

### Change

* **Make compactor thresholds explicit** <br>
  Require `message_threshold:` and `token_threshold:` to be opted into
  explicitly, so `LLM::Compactor` only compacts automatically when one of
  those thresholds is configured. Context-window-derived token limits can be
  computed by the caller when needed.

* **Allow assigning a compactor through `LLM::Context`** <br>
  Let `LLM::Context` accept `ctx.compactor = ...` in addition to the
  constructor `compactor:` option, so compactor config can be assigned or
  replaced after context initialization.

* **Mark compaction summaries in message metadata** <br>
  Mark compaction summaries with `extra[:compaction]` and
  `LLM::Message#compaction?`, so applications can detect or hide synthetic
  summary messages in conversation history.

* **Add cooperative tool interruption hooks** <br>
  Let `ctx.interrupt!` notify queued tool work through `on_interrupt`, so
  running tools can clean up cooperatively when a context is cancelled.

* **Add `LLM::Context` guards** <br>
  Add a new `guard` capability to `LLM::Context` so execution can be
  supervised at the runtime level. The built-in `LLM::LoopGuard` detects
  repeated tool-call patterns and stops stuck agentic loops through in-band
  `LLM::GuardError` returns. `LLM::Agent` enables this guard by default.

* **Add `LLM::Context` transformers** <br>
  Add a new `transformer` capability to `LLM::Context` so prompts and params
  can be rewritten before provider requests are sent. This makes it possible
  to apply context-wide behaviors such as PII scrubbing or request-level
  param injection without rewriting every `talk` and `respond` call site.

## v4.23.0

Changes since `v4.22.0`.

This release expands llm.rb's runtime surface for long-lived contexts and
stateful tools. It adds built-in context compaction through `LLM::Compactor`,
lets explicit `tools:` arrays accept bound `LLM::Tool` instances, and fixes
OpenAI-compatible no-arg tool schemas for stricter providers such as xAI.

### Change

* **Add `LLM::Compactor` for long-lived contexts** <br>
  Add built-in context compaction through `LLM::Compactor`, so older history
  can be summarized, retained windows can stay bounded, compaction can run on
  its own `model:`, thresholds can be configured explicitly, and
  `LLM::Stream` can observe the lifecycle through `on_compaction` and
  `on_compaction_finish`.

* **Allow bound tool instances in explicit tool lists** <br>
  Let explicit `tools:` arrays accept `LLM::Tool` instances such as
  `MyTool.new(foo: 1)`, so tools can carry bound state without changing the
  global tool registry model.

### Fix

* **Fix xAI/OpenAI-compatible no-arg tool schemas** <br>
  Send an empty object schema for tools without declared parameters instead
  of `null`, so stricter providers such as xAI accept mixed tool sets that
  include no-arg tools.

## v4.22.0

Changes since `v4.21.0`.

This release deepens the runtime shape of llm.rb. It reduces helper-method
surface on persisted ORM models, expands real ORM coverage, and makes skills
behave more like bounded sub-agents with inherited recent context and proper
instruction injection.

### Change

* **Reduce ActiveRecord wrapper model surface** <br>
  Move helper methods such as option resolution, column mapping,
  serialization, and persistence into `Utils` for the ActiveRecord
  wrappers so wrapped models include fewer internal helper methods.

* **Reduce Sequel wrapper model surface** <br>
  Move helper methods such as option resolution, column mapping,
  serialization, and persistence into `Utils` for the Sequel wrappers
  so wrapped models include fewer internal helper methods.

* **Expand ORM integration coverage** <br>
  Add broader ActiveRecord and Sequel coverage for persisted context and
  agent wrappers, including real SQLite-backed records and cassette-backed
  OpenAI persistence paths.

* **Make skills inherit recent parent context** <br>
  Run `LLM::Skill` with a curated slice of recent parent user and assistant
  messages, prefixed with `Recent context:`, so skills behave more like
  task-scoped sub-agents instead of instruction-only helpers.

### Fix

* **Fix Sequel `plugin :agent` load order** <br>
  Require the shared Sequel plugin support from `LLM::Sequel::Agent` so
  `plugin :agent` can load independently without raising
  `uninitialized constant LLM::Sequel::Plugin`.

* **Make skill execution inherit parent context request settings** <br>
  Run `LLM::Skill` through a parent `LLM::Context` instead of a bare
  provider so nested skill agents inherit context-level settings such as
  `mode: :responses`, `store: false`, streaming, and other request defaults,
  while still keeping skill-local tools and avoiding parent schemas.

* **Keep agent instructions when history is preseeded** <br>
  Inject `LLM::Agent` instructions once unless a system message is already
  present, so agents and nested skills still get their instructions when
  they start with inherited non-system context.

## v4.21.0

Changes since `v4.20.2`.

This release expands higher-level composition in llm.rb. It adds Sequel agent
persistence through `plugin :agent` and introduces directory-backed skills
that load from `SKILL.md`, resolve named tools, and plug directly into
`LLM::Context` and `LLM::Agent`.

### Change

* **Add `plugin :agent` for Sequel models** <br>
  Add Sequel support for `plugin :agent`, similar to ActiveRecord's
  `acts_as_agent`, so models can wrap `LLM::Agent` with built-in
  persistence.

* **Load directory-backed skills through `LLM::Context` and `LLM::Agent`** <br>
  Add `skills:` to `LLM::Context` and `skills ...` to `LLM::Agent` so
  directories with `SKILL.md` can be loaded, resolved into tools, and run
  through the normal llm.rb tool path.

## v4.20.2

Changes since `v4.20.1`.

This patch release improves runtime behavior around interruption and mixed
concurrency waits. It also rounds out response API uniformity for Google
completion responses.

### Fix

* **Expose Google completion response IDs through `.id`** <br>
  Add `LLM::Response#id` support to Google completion responses so tracer
  and caller code can rely on the same API used by other providers.

* **Track interrupt ownership on the active request** <br>
  Bind `LLM::Context` interruption to the fiber running `talk` or `respond`
  so `interrupt!` works correctly when requests are started outside the
  context's initialization fiber.

### Change

* **Allow mixed concurrency strategies in `wait(...)`** <br>
  Let `LLM::Context#wait`, `LLM::Stream#wait`, and `LLM::Agent.concurrency`
  accept arrays such as `[:thread, :ractor]` so mixed tool sets can wait on
  more than one concurrency strategy.

## v4.20.1

Changes since `v4.20.0`.

This patch release fixes ORM option resolution in the Sequel and
ActiveRecord wrappers. Symbol-based `provider:` and `context:` hooks now
resolve correctly, and internal default option constants are referenced
explicitly instead of relying on nested constant lookup.

### Fix

* **Fix symbol-based ORM option hooks for provider and context hashes** <br>
  Make `provider:` and `context:` resolve symbol hooks through the model in
  the Sequel plugin and ActiveRecord wrappers instead of falling back to an
  empty hash.

* **Fix ORM wrapper constant lookup for option defaults** <br>
  Qualify internal `EMPTY_HASH` / `DEFAULTS` references in the Sequel plugin
  and ActiveRecord wrappers so option resolution does not depend on nested
  constant lookup quirks.

## v4.20.0

Changes since `v4.19.0`.

This release adds better support for tagged prompt content. `LLM::Context`
can now serialize and restore `image_url`, `local_file`, and `remote_file`
content cleanly, and `LLM::Message` now exposes helpers for inspecting
tagged image and file attachments.

### Change

* **Round-trip tagged prompt objects through `LLM::Context`** <br>
  Teach `LLM::Context` serialization and restore to preserve
  `image_url`, `local_file`, and `remote_file` content across
  `to_json` / `restore`.

* **Add attachment helpers to `LLM::Message`** <br>
  Add `image_url?`, `image_urls`, `file?`, and `files` so callers can
  inspect messages for tagged image and file content more directly.

## v4.19.0

Changes since `v4.18.0`.

This release tightens the ActiveRecord and ORM integration layer. It adds
inline agent DSL blocks to `acts_as_agent` so agent defaults can be defined
where the wrapper is declared, and it exposes the resolved provider through
public `llm` methods on the ActiveRecord and Sequel wrappers.

### Change

* **Make ORM provider access public through `llm`** <br>
  Expose the resolved provider on the Sequel plugin and the ActiveRecord
  `acts_as_llm` / `acts_as_agent` wrappers through a public `llm` method.

* **Allow inline agent DSL blocks in `acts_as_agent`** <br>
  Let ActiveRecord models configure `model`, `tools`, `schema`,
  `instructions`, and `concurrency` directly inside the `acts_as_agent`
  declaration block.

## v4.18.0

Changes since `v4.17.0`.

This release improves tracing and tool execution behavior across llm.rb.
It makes provider tracers default to the provider instance, adds
`LLM::Provider#with_tracer` for scoped overrides, restores tool tracing for
concurrent and streamed tool execution, extends streamed tracing to MCP tools,
and adds symbol-based ORM option hooks alongside experimental ractor tool
concurrency.

### Change

* **Make provider tracers default to the provider instance** <br>
  Change `llm.tracer = ...` so it sets a provider default tracer instead of
  relying on scoped fiber-local state alone. This makes tracer configuration
  behave more predictably across normal tasks, threads, and fibers that share
  the same provider instance.

* **Add `LLM::Provider#with_tracer` for scoped overrides** <br>
  Add `with_tracer` as the opt-in escape hatch for request- or turn-scoped
  tracer overrides. Use it when you want temporary tracing on the current
  fiber without replacing the provider's default tracer.

* **Trace concurrent tool calls outside ractors** <br>
  Make tool tracing fire correctly when functions run through `:thread`,
  `:task`, or `:fiber` concurrency. Experimental `:ractor` execution still
  does not emit tool tracer events.

* **Trace streamed tool calls, including MCP tools** <br>
  Bind stream metadata through `LLM::Stream#extra` so streamed tool calls
  inherit tracer and model context before they are handed to `on_tool_call`.
  This restores tool tracing for streamed MCP and local tool execution.

* **Support symbol-based ORM option hooks** <br>
  Let `provider:`, `context:`, and `tracer:` on the Sequel plugin and
  the ActiveRecord `acts_as_llm` / `acts_as_agent` wrappers resolve through
  model method names as well as procs.

* **Add experimental ractor tool concurrency** <br>
  Add `:ractor` support to `LLM::Function#spawn`, `LLM::Function::Array#wait`,
  `LLM::Stream#wait`, and `LLM::Agent.concurrency` so class-based tools with
  ractor-safe arguments and return values can run in Ruby ractors and report
  their results back into the normal LLM tool-return path. MCP tools are not
  supported by the current `:ractor` mode, but mixed workloads can still
  branch on `tool.mcp?` and choose a supported strategy per tool. `:ractor`
  is especially useful for CPU-bound tools, while `:task`, `:fiber`, or
  `:thread` may be a better fit for I/O-bound work.

## v4.17.0

Changes since `v4.16.1`.

This release expands agent support across llm.rb. It brings `LLM::Agent`
closer to `LLM::Context`, adds configurable automatic tool concurrency
including experimental ractor support for class-based tools,
extends persisted ORM wrappers with more of the context runtime surface and
tracer hooks, and introduces built-in ActiveRecord agent persistence through
`acts_as_agent`.

### Change

* **Add configurable tool concurrency to `LLM::Agent`** <br>
  Add the class-level `concurrency` DSL to `LLM::Agent` so automatic
  tool loops can run with `:call`, `:thread`, `:task`, `:fiber`, or
  experimental `:ractor` support for class-based tools instead of
  always executing sequentially.

* **Bring `LLM::Agent` closer to `LLM::Context`** <br>
  Expand `LLM::Agent` so it exposes more of the same runtime surface as
  `LLM::Context`, including returns, interruption, mode, cost, context
  window, structured serialization, and other context-backed helpers,
  while still auto-managing tool loops.

* **Refresh agent docs and coverage** <br>
  Update the README and deep dive to explain the current role of
  `LLM::Agent`, add examples that show automatic tool execution and
  concurrency, and add focused specs for the expanded agent surface and
  tool-loop behavior.

* **Add ORM tracer hooks for persisted contexts** <br>
  Add `tracer:` to both the Sequel plugin and `acts_as_llm` so models
  can resolve and assign tracers onto the provider used by their persisted
  `LLM::Context`.

* **Bring persisted ORM wrappers closer to `LLM::Context`** <br>
  Expand both the Sequel plugin and `acts_as_llm` so record-backed
  contexts expose more of the same runtime surface as `LLM::Context`,
  including mode, returns, interruption, prompt helpers, file helpers,
  and tracer access.

* **Add ActiveRecord agent persistence with `acts_as_agent`** <br>
  Add `acts_as_agent` for ActiveRecord models that should wrap
  `LLM::Agent`, reusing the same record-backed runtime shape as
  `acts_as_llm` while letting tool execution be managed by the agent.

## v4.16.1

Changes since `v4.16.0`.

This release tightens ORM persistence by removing an unnecessary JSON
round-trip when restoring structured `:json` and `:jsonb` context
payloads.

### Change

* **Restore structured ORM payloads directly** <br>
  Teach `LLM::Context#restore` to accept parsed data payloads and use
  that path from the ActiveRecord and Sequel persistence wrappers for
  `format: :json` and `:jsonb`, avoiding a redundant
  `Hash -> JSON string -> Hash` round-trip on restore.

## v4.16.0

Changes since `v4.15.0`.

This release expands ORM support with built-in ActiveRecord persistence
and improves compatibility with OpenAI-compatible gateways, proxies, and
self-hosted servers that use non-standard API root paths.

### Change

* **Support OpenAI-compatible base paths** <br>
  Add `base_path:` to provider configuration so OpenAI-compatible
  endpoints can vary both host and API prefix. This supports providers,
  proxies, and gateways that keep OpenAI request shapes but use
  non-standard URL layouts such as DeepInfra's `/v1/openai/...`.

* **Add ActiveRecord context persistence with `acts_as_llm`** <br>
  Add a built-in ActiveRecord wrapper that mirrors the Sequel plugin
  API so applications can persist `LLM::Context` state on records with
  default columns, provider/context hooks, validation-backed writes,
  and `format: :string`, `:json`, or `:jsonb` storage.

## v4.15.0

Changes since `v4.14.0`.

### Change

* **Reduce OpenAI stream parser merge overhead** <br>
  Special-case the most common single-field deltas, streamline
  incremental tool-call merging, and avoid repeated JSON parse attempts
  until streamed tool arguments look complete.

* **Cache streaming callback capabilities in parsers** <br>
  Cache callback support checks once at parser initialization time in
  the OpenAI, OpenAI Responses, Anthropic, Google, and Ollama stream
  parsers instead of repeating `respond_to?` checks on hot streaming
  paths.

* **Reduce OpenAI Responses parser lookup overhead** <br>
  Special-case the hot Responses API event paths and cache the current
  output item and content part so streamed output text deltas do less
  repeated nested lookup work.

* **Add a Sequel context persistence plugin** <br>
  Add `plugin :llm` for Sequel models so apps can persist
  `LLM::Context` state with default columns and pass provider setup
  through `provider:` when needed. The plugin now also supports
  `format: :string`, `:json`, or `:jsonb` for text and native JSON
  storage when Sequel JSON typecasting is enabled.

* **Improve streaming parser performance** <br>
  In the local replay-based `stream_parser` benchmark versus `v4.14.0`
  (median of 20 samples, 5000 iterations), plain Ruby is a
  small overall win: the generic eventstream path is about 0.4%
  faster, the OpenAI stream parser is about 0.5% faster, and the
  OpenAI Responses parser is about 1.6% faster, with unchanged
  allocations. Under YJIT on the same benchmark harness, the generic
  eventstream path is about 0.9% faster and the OpenAI stream parser
  is about 0.4% faster, while the OpenAI Responses parser is about
  0.7% slower, also with unchanged allocations.

  Compared to `v4.13.0`, the larger `v4.14.0` streaming gains still
  hold. The generic eventstream path remains dramatically faster than
  `v4.13.0`, the OpenAI stream parser remains modestly faster, and the
  OpenAI Responses parser is roughly flat to slightly better depending
  on runtime. In other words, current keeps the large eventstream win
  from `v4.14.0`, adds only small incremental changes beyond that, and
  does not turn the post-`v4.14.0` parser work into another large
  benchmark jump.

## v4.14.0

Changes since `v4.13.0`.

This release adds request interruption for contexts, reworks provider
HTTP internals for lower-overhead streaming, and fixes MCP clients so
parallel tool calls can safely share one connection.

### Add

* **Add request interruption support** <br>
  Add `LLM::Context#interrupt!`, `LLM::Context#cancel!`, and
  `LLM::Interrupt` for interrupting in-flight provider requests,
  inspired by Go's context cancellation.

### Change

* **Rework provider HTTP transport internals** <br>
  Rework provider HTTP around `LLM::Provider::Transport::HTTP` with
  explicit transient and persistent transport handling.

* **Reduce SSE parser overhead** <br>
  Dispatch raw parsed values to registered visitors instead of building
  an `Event` object for every streamed line.

* **Reduce provider streaming allocations** <br>
  Decode streamed provider payloads directly in
  `LLM::Provider::Transport::HTTP` before handing them to provider
  parsers, which cuts allocation churn and gives a small streaming
  speed bump.

* **Reduce generic SSE parser allocations** <br>
  Keep unread event-stream buffer data in place until compaction is
  worthwhile, which lowers allocation churn in the remaining generic
  SSE path.

* **Improve streaming parser performance** <br>
  In the local replay-based `stream_parser` benchmark versus `v4.13.0`
  (median of 20 samples, 5000 iterations):
  Plain Ruby: the generic eventstream path is about 53% faster with
  about 32% fewer allocations, the OpenAI stream parser is about 11%
  faster with about 4% fewer allocations, and the OpenAI Responses
  parser is about 3% faster with unchanged allocations.
  YJIT on the current parser benchmark harness: the current tree is
  about 26% faster than non-YJIT on the generic eventstream path,
  about 18% faster on the OpenAI stream parser, and about 16% faster
  on the OpenAI Responses parser, with allocations unchanged.

### Fix

* **Support parallel MCP tool calls on one client** <br>
  Route MCP responses by JSON-RPC id so concurrent tool calls can
  share one client and transport without mismatching replies.

* **Use explicit MCP non-blocking read errors** <br>
  Use `IO::EAGAINWaitReadable` while continuing to retry on
  `IO::WaitReadable`.

## v4.13.0

Changes since `v4.12.0`.

This release expands MCP prompt support, improves reasoning support in the
OpenAI Responses API, and refreshes the docs around llm.rb's runtime model,
contexts, and advanced workflows.

### Add

- Add `LLM::MCP#prompts` and `LLM::MCP#find_prompt` for MCP prompt support.

### Change

- Rework the README around llm.rb as a runtime for AI systems.
- Add a dedicated deep dive guide for providers, contexts, persistence,
  tools, agents, MCP, tracing, multimodal prompts, and retrieval.

### Fix

All of these fixes apply to MCP:

- fix(mcp): raise `LLM::MCP::MismatchError` on mismatched response ids.
- fix(mcp): normalize prompt message content while preserving the original payload.

All of these fixes apply to OpenAI's Responses API:

- fix(openai): emit `on_reasoning_content` for streamed reasoning summaries.
- fix(openai): skip `previous_response_id` on `store: false` follow-up calls.
- fix(openai): fall back to an empty object schema for tools without params.
- fix(openai): preserve original tool-call payloads on re-sent assistant tool messages.
- fix(openai): emit `output_text` for assistant-authored response content.
- fix(openai): return `nil` for `system_fingerprint` on normalized response objects.

## v4.12.0

Changes since `v4.11.1`.

This release expands advanced streaming and MCP execution while reframing
llm.rb more clearly as a system integration layer for LLMs, tools, MCP
sources, and application APIs.

### Add

- Add `persistent` as an alias for `persist!` on providers and MCP transports.
- Add `LLM::Stream#on_tool_return` for observing completed streamed tool work.
- Add `LLM::Function::Return#error?`.

### Change

- Expect advanced streaming callbacks to use `LLM::Stream` subclasses
  instead of duck-typing them onto arbitrary objects. Basic `#<<`
  streaming remains supported.

### Fix

- Fix Anthropic tools without params by always emitting `input_schema`.
- Fix Anthropic tool-only responses to still produce an assistant message.
- Fix Anthropic tool results to use the `user` role.
- Fix Anthropic tool input normalization.

## v4.11.1

Changes since `v4.11.0`.

### Fix

* Cast OpenTelemetry tool-related values to strings. <br>
  Otherwise they're rejected by opentelemetry-sdk as invalid attributes.

## v4.11.0

Changes since `v4.10.0`.

### Add

- Add `LLM::Stream` for richer streaming callbacks, including `on_content`,
  `on_reasoning_content`, and `on_tool_call` for concurrent tool execution.
- Add `LLM::Stream#wait` as a shortcut for `queue.wait`.
- Add `LLM::Context#wait` as a shortcut for the configured stream's `wait`.
- Add `LLM::Context#call(:functions)` as a shortcut for `functions.call`.
- Add `LLM::Function.registry` and enhanced support for MCP tools in
  `LLM::Tool.registry` for tool resolution during streaming.
- Add normalized `LLM::Response` for OpenAI Responses, providing `content`,
  `content!`, `messages` / `choices`, `usage`, and `reasoning_content`.
- Add `mode: :responses` to `LLM::Context` for routing `talk` through the
  Responses API.
- Add `LLM::Context#returns` for collecting pending tool returns from the context.
- Add persistent HTTP connection pooling for repeated MCP tool calls via
  `LLM.mcp(http: ...).persist!`.
- Add explicit MCP transport constructors via `LLM::MCP.stdio(...)` and
  `LLM::MCP.http(...)`.

### Fix

- Fix Google tool-call handling by synthesizing stable ids when Gemini does
  not provide a direct tool-call id.

## v4.10.0

Changes since `v4.9.0`.

### Add

- Add HTTP transport for MCP with `LLM::MCP::Transport::HTTP` for remote servers
- Add JSON Schema union types (`any_of`, `all_of`, `one_of`) with parser integration
- Add JSON Schema type array union support (e.g., `"type": ["object", "null"]`)
- Add JSON Schema type inference from `const`, `enum`, or `default` fields

### Change

- Update `LLM::MCP` constructor for exclusive `http:` or `stdio:` transport
- Update `LLM::MCP` documentation for HTTP transport support

## v4.9.0

Changes since `v4.8.0`.

### Add

- Add fiber-based concurrency with `LLM::Function::FiberGroup` and
  `LLM::Function::TaskGroup` classes for lightweight async execution.
- Add `:thread`, `:task`, and `:fiber` strategy parameter to
  `LLM::Function#spawn` for explicit concurrency control.
- Add stdio MCP client support, including remote tool discovery and
  invocation through `LLM.mcp`, `LLM::Context`, and existing function/tool
  APIs.
- Add model registry support via `LLM::Registry`, including model
  metadata lookup, pricing, modalities, limits, and cost estimation.
- Add context access to a model context window via
  `LLM::Context#context_window`.
- Add tracking of defined tools in the tool registry.
- Add `LLM::Schema::Enum`, enabling `Enum[...]` as a schema/tool
  parameter type.
- Add top-level Anthropic system instruction support using Anthropic's
  provider-specific request format.
- Add richer tracing hooks and extra metadata support for
  LangSmith/OpenTelemetry-style traces.
- Add rack/websocket and Relay-related example work, including MCP-focused
  examples.
- Add concurrent tool execution with `LLM::Function#spawn`,
  `LLM::Function::Array` (`call`, `wait`, `spawn`), and
  `LLM::Function::ThreadGroup`.
- Add `LLM::Function::ThreadGroup#alive?` method for non-blocking
  monitoring of concurrent tool execution.
- Add `LLM::Function::ThreadGroup#value` alias for `ThreadGroup#wait` for
  consistency with Ruby's `Thread#value`.

### Change

- Rename `LLM::Session` to `LLM::Context` throughout the codebase to better
  reflect the concept of a stateful interaction environment.
- Rename `LLM::Gemini` to `LLM::Google` to better reflect provider naming.
- Standardize model objects across providers around a smaller common
  interface.
- Switch registry cost internals from `LLM::Estimate` to `LLM::Cost`.
- Update image generation defaults so OpenAI and xAI consistently return
  base64-encoded image data by default.
- Update `LLM::Bot` deprecation warning from v5.0 to v6.0, giving users
  more time to migrate to `LLM::Context`.
- Rework the README and screencast documentation to better cover MCP,
  registry, contexts, prompts, concurrency, providers, and example flow.
- Expand the README with architecture, production, and provider guidance
  while improving readability and example ordering.

### Fix

- Fix local schema `$ref` resolution in `LLM::Schema::Parser`.
- Fix multiple MCP issues around stdio env handling, request IDs, registry
  interaction, tool registration, and filtering of MCP tools from the
  standard tool registry.
- Fix stream parsing issues, including chunk-splitting bugs and safer
  handling of streamed error responses.
- Fix prompt handling across contexts, agents, and provider adapters so
  prompt turns remain consistent in history and completions.
- Fix several tool/context issues, including function return wrapping,
  tool lookup after deserialization, unnamed subclass filtering, and
  thread-safety around tool registry mutations.
- Fix Google tool-call handling to preserve `thoughtSignature`.
- Fix `LLM::Tracer::Logger` argument handling.
- Fix packaging/docs issues such as registry files in the gemspec and
  stale provider docs.
- Fix Google provider handling of `nil` function IDs during context
  deserialization.
- Fix MCP stdio transport by increasing poll timeout for better
  reliability.
- Fix Google provider to properly cast non-Hash tool results into Hash
  format for API compatibility.
- Fix schema parser to support recursive normalization of `Array`,
  `LLM::Object`, and nested structures.
- Fix DeepSeek provider to tolerate malformed tool arguments.
- Fix `LLM::Function::TaskGroup#alive?` to properly delegate to
  `Async::Task#alive?`.
- Fix various RuboCop errors across the codebase.
- Fix DeepSeek provider to handle JSON that might be valid but unexpected.

### Notes

Notable merged work in this range includes:

- `feat(function): add fiber-based concurrency for async environments (#64)`
- `feat(mcp): add stdio MCP support (#134)`
- `Add LLM::Registry + cost support (#133)`
- `Consistent model objects across providers (#131)`
- `Add rack + websocket example (#130)`
- `feat(gemspec): add changelog URI (#136)`
- `feat(function): alias ThreadGroup#wait as ThreadGroup#value (#62)`
- `README and screencast refresh across `#66`, `#68`, `#71`, and
  `#72`
- `chore(bot): update deprecation warning from v5.0 to v6.0`
- `fix(deepseek): tolerate malformed tool arguments`
- `refactor(context): Rename Session as Context (#70)`

Comparison base:
- Latest tag: `v4.8.0` (`6468f2426ee125823b7ae43b4af507b125f96ffc`)
- HEAD used for this changelog: `915c48da6fda9bef1554ff613947a6ce26d382e3`
