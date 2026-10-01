
## Database
### Introduction

#### Overview

Persistence lets an agent outlive a single session. The
conversation history, the context id, the model name, the compaction
status, and a snapshot of token usage are serialized as JSON that can
be stored in a file, a database column, or transmitted over a network.
Four storage options are available:

- **Automatic filesystem persistence**: set `path:` on an agent
  for transparent auto-save after every turn (recommended for
  most file-based use-cases)
- **Filesystem**: save and restore from a JSON file on disk
- **ActiveRecord**: persist state in a database column using
  [`acts_as_agent`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#acts_as_agent-instance_method)
  for an agent, or
  [`acts_as_llm`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#acts_as_llm-instance_method)
  for a context
- **Sequel**: persist state in a database column using `plugin :agent`
  for an agent, or `plugin :llm` for a context

All four use the same serialization mechanism under the hood.

#### How it works

[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
implements
[`LLM::Context#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#to_h)
and
[`LLM::Context#to_json`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#to_json)
for serialization and
[`LLM::Context#restore`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#restore)
for deserialization. Save writes the current state, restore loads
it back and picks up where the conversation left off.

The ORM wrappers write on a different boundary than the file does, and
the two are worth telling apart.
[`LLM::Step`](https://r.uby.dev/api-docs/llm.rb/LLM/Step.html) is
prepended onto the stream, and it saves the conversation through the
record the context is bound to each time
[`LLM::Stream#on_step`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_step-instance_method)
fires - after a response is in the conversation and before the tools it
asked for run. A turn that runs tools before it answers is therefore
saved more than once, and an application that writes it down can
continue an interrupted turn instead of redoing it.

A `path:` has no record behind it to write to, so that one saves once
per turn. The difference is what each is for: the column is a
checkpoint after every completed request, and the file is a session at
the end of one.

#### Why would I use it?

Without persistence, every agent starts with a blank conversation.
Persistence enables long-running agents that survive process
restarts, debugging sessions that resume mid-investigation, and
conversation history that can be queried alongside application
data.

#### Notes

The saved JSON can be stored in a file, a database column, or
transmitted over the network. The ORM integrations use the same
underlying serialization as filesystem persistence.

### Automatic filesystem persistence

#### Overview

The [`LLM::Agent#path`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#path)
attribute provides transparent auto-persistence. Set a file path once
and the agent restores conversation history from that file on startup
and saves it back after every
[`LLM::Agent#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#talk)
or
[`LLM::Agent#ask`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#ask)
turn. No manual
[`LLM::Agent#save`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#save)/
[`LLM::Agent#restore`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#restore)
calls needed.

The feature is available on subclasses via the class DSL and on
direct instances via the `path:` keyword argument.

#### How it works

When a `path` is set, the agent loads existing state from the file
during initialization. After each turn
([`LLM::Agent#talk`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#talk)
or
[`LLM::Agent#ask`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#ask)),
the updated
state is written back automatically. If the file does not exist yet,
the agent starts with a blank conversation and creates the file on
the first save.

The path can be set using any of these approaches:

##### Class DSL

```ruby
class PersistentAgent < LLM::Agent
  set model: "deepseek-v4-pro",
      path: "session.json"
end

# state saved automatically to session.json
llm = LLM.deepseek(key: ENV["KEY"])
agent = PersistentAgent.new(llm)
agent.talk "remember my name is robert"

# restored from session.json; prints "robert"
agent = PersistentAgent.new(llm)
agent.talk "what's my name?"
```

##### Keyword argument

```ruby
# state saved automatically
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, path: "session.json", stream: $stdout)
agent.talk "remember my name is robert"
```

##### Lazy resolution

```ruby
class DynamicAgent < LLM::Agent
  set path: -> { "sessions/#{name}.json" }
end
```

#### Why would I use it?

Auto-persistence eliminates boilerplate. You set the path once and
forget about serialization entirely. The agent picks up where it
left off across process restarts, console sessions, or debugging runs
without a single
[`LLM::Agent#save`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#save)
or
[`LLM::Agent#restore`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#restore)
call in your code.

#### Notes

The auto-path feature is a strict superset of manual filesystem
persistence. If you need fine-grained control over when state is
saved (e.g. batch several turns before persisting), use the manual
[`LLM::Agent#save`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#save)
and
[`LLM::Agent#restore`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#restore)
methods described in the Filesystem section below. The `path`
attribute delegates to the same underlying serialization.

### Filesystem

#### Overview

A conversation that ends when the process exits is not very useful.
Serialization saves the context (message history, model name,
compaction status) as JSON that can be stored in a string, a
file, or a database column. Restore it later, in a different
process or on a different machine, and pick up where you left off.

#### How it works

[`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
implements
[`LLM::Context#to_h`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#to_h)
and
[`LLM::Context#to_json`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#to_json)
for serialization
and
[`LLM::Context#restore`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#restore)
for deserialization. The serialized state includes the context id,
the message history, the model name, the compaction status, and a
snapshot of token usage. Save and
restore work with file paths or in-memory strings. You can also
serialize to a JSON string for database storage or network
transmission:

##### Save to a file

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm)
agent.talk "remember my name is robert"
agent.save(path: "agent.json")
```

##### Restore from a file

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, stream: $stdout)
agent.restore(path: "agent.json")
agent.talk "what's my name?"
```

##### Serialize to a JSON string

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm)
agent.talk "remember my name is robert"
json = agent.to_json
agent = LLM::Agent.new(llm)
agent.restore(string: json)
```

#### Why would I use it?

Filesystem persistence is the foundation for long-running agents
that outlive a single session. Save a debugging session
mid-investigation and resume it tomorrow. Store a completed
conversation as evidence or training data. Pass context between
processes, between machines, or through a job queue.

#### Notes

[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
delegates serialization to its internal context. The
saved JSON can be stored in a file, a database column, or
transmitted over the network.

### ActiveRecord

#### Overview

ActiveRecord models use
[`LLM::ActiveRecord#acts_as_agent`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#acts_as_agent-instance_method)
to install the agent wrapper. The method accepts a block for
configuring agent defaults
and an options hash for storage format. Most defaults such as
`model`, `tools`, `instructions`, `schema`, and `concurrency` can
be set through the block, and the tracer and stream can be set here
too.

#### How it works

When you want to add agent persistence to an ActiveRecord model,
call
[`LLM::ActiveRecord#acts_as_agent`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#acts_as_agent-instance_method)
in the model class. The `data` column stores
the full agent state (the context id, conversation history, model
name, compaction status, and a token usage snapshot) as JSON. On
first call, a fresh agent is created and the conversation starts
from scratch.

On subsequent calls, the stored state is restored and the
conversation continues. The column is written after each completed
request rather than at the end of a turn, so a turn that runs tools
before it answers is saved more than once - and a turn that is
interrupted can be resumed from its last completed request.

The `data_column:` option lets you use a different column name.
The `format:` option controls the storage type. Use `:string` for
a text column (any database) or `:jsonb` for a native PostgreSQL
JSONB column (recommended for PostgreSQL). For `:jsonb`,
ActiveRecord handles JSON typecasting automatically.

The block yields an
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
instance. Set agent defaults in the block using the
[`LLM::Agent.set`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#set-class_method)
method or individual accessors. Anything you can set on an agent
can be
configured here -- model, tools, instructions, schema, concurrency,
tracer, stream, and confirm:

The model implements two callbacks and the wrapper resolves them by
name: `set_provider`, which is required, and `set_context`, which is
optional. A tracer is not one of them - there is no `set_tracer` - so
give it to `acts_as_agent` as `tracer:`, or set it on the agent in the
block as the example below does.

##### Migration with TEXT column

```ruby
class CreateAgents < ActiveRecord::Migration[7.1]
  def change
    create_table :agents do |t|
      t.string :name
      t.text :data   # stores the serialized agent state
      t.timestamps
    end
  end
end
```

##### Migration with JSONB column

```ruby
class CreateAgents < ActiveRecord::Migration[7.1]
  def change
    create_table :agents do |t|
      t.string :name
      t.jsonb :data  # native JSON storage, supports indexing
      t.timestamps
    end
  end
end
```

##### Model setup

```ruby
require "active_record"
require "llm"
require "llm/active_record"

class Agent < ApplicationRecord
  acts_as_agent(format: :jsonb) do |agent|
    agent.model "deepseek-v4-pro"
    agent.instructions "solve the user's query"
    agent.tools [Research, FinalizeResearch, ActOnResearch]
    agent.tracer -> { LLM::Tracer.logger(llm, io: $stdout) }
  end

  private

  def set_provider
    LLM.deepseek(key: ENV["KEY"])
  end
end

agent = Agent.create!(name: "researcher")
agent.talk "perform research"
# state is saved to the data column automatically
```

#### Why would I use it?

The ActiveRecord wrapper integrates with your existing models.
Agent state is automatically persisted after each completed request,
using the same `create!`, `save!`, and query methods you already
use.

#### Notes

The `format` option defaults to `:string`. Use `:json` or `:jsonb`
for PostgreSQL. JSONB is recommended; it supports indexing and
is more efficient for querying. The `data_column` option defaults
to `:data` -- create a migration to add a `TEXT` or `JSONB` column
to your table.

The model requires a `set_provider` private method that returns an
[`LLM::Provider`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html)
instance, and may implement `set_context` to seed the context with
parameters. Those two are the only callbacks `acts_as_llm` and
`acts_as_agent` resolve. A tracer is passed to the wrapper as
`tracer:`, or set on the agent in the block
(`agent.tracer ...`, `agent.stream ...`).

An agent built by `acts_as_agent` is bound to the record it was
loaded from, and
[`LLM::Agent#record`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#record)
returns it. To persist a context instead of an agent, use
`acts_as_llm`: the model gains `#llm` (the provider) and `#ctx` (the
context), and persists the same state without the automatic tool
loop.

### SQL view

#### Overview

[`LLM::ActiveRecord::Message`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/Message.html)
is a virtual ActiveRecord model that never materializes as a table. It
exposes the messages stored inside an agent's `jsonb` column as a SQL
view, so a conversation can be filtered, ordered, and counted in the
database instead of in memory.

#### How it works

Call
[`LLM::ActiveRecord::Message.for`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/Message.html#for-class_method)
with an agent, and it returns an
[`ActiveRecord::Relation`](https://api.rubyonrails.org/classes/ActiveRecord/Relation.html)
scoped to that agent, with one row per message. The relation chains
like any other:

```ruby
agent = Agent.find_by(id: 1)

messages = LLM::ActiveRecord::Message.for(agent:)
messages.where(role: "assistant").order(position: :desc).limit(10)
messages.count
```

Each row carries a message flattened into columns: `id`, `role`,
`content`, `tools`, and `position` (its place in the conversation),
with the whole message kept as `data`.
[`LLM::ActiveRecord::Message#unwrap!`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/Message.html#unwrap!-instance_method)
rebuilds the message as the runtime would hand it back, so fields the
view does not name, such as usage and reasoning, survive the round
trip. `#tool_call?` and `#tool_return?` delegate to it.

#### Why would I use it?

Reading a conversation through the view keeps the work in the
database. "How many assistant messages has this agent produced" and
"show the last ten messages" become ordinary ActiveRecord queries
instead of loading and filtering the whole conversation in Ruby.

#### Notes

The view expects the agent and this class to share a connection, which
holds when both live on the same database. It requires
`format: :jsonb`, since a `:string` column stores the state as text and
cannot be expanded into rows. The queries the view runs are index
scans, because they expand one agent found by primary key, but a query
you write across every agent is not covered by default; index the state
column for those, for example with a GIN index on
`data jsonb_path_ops`.

A record whose `format` is `:jsonb` also returns this view from
`#messages`, so a conversation can be read without building a runtime:
no provider, and no credentials. What it returns differs from the
runtime's own `#messages` in three ways. It reads what is persisted
rather than the state a context holds in memory and has not saved. It
is unordered, and conversation order is `position` rather than `id`, so
order it explicitly. And its rows are
[`LLM::ActiveRecord::Message`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/Message.html)
records rather than
[`LLM::Message`](https://r.uby.dev/api-docs/llm.rb/LLM/Message.html)
objects, until
[`#unwrap!`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/Message.html#unwrap!-instance_method)
turns them back. `#messages!` is the runtime's own list, whatever the
format is, so a jsonb record reaches it in one call.

Every other format answers `#messages` with the runtime's messages, as
it always did, and that is the default. Sequel has no equivalent to any
of this: its plugin persists the same state, and there is no view to
read it back in the database.

### Sequel

#### Overview

Sequel models use `plugin :agent` to install the agent wrapper.
The plugin accepts the same options as
[`acts_as_agent`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord.html#acts_as_agent-instance_method)
and follows the same conventions for provider resolution and state
persistence.
On first call, a fresh agent is created and the conversation starts
from scratch. On subsequent calls, the stored state is restored and
the conversation continues automatically.

#### How it works

When you want to add agent persistence to a Sequel model, register
the plugin in the model class. The `data` column stores
the full agent state as JSON, same structure as ActiveRecord.
On first call, a fresh agent is created. On subsequent calls,
the stored state is restored and the conversation continues.
The state is written after each completed request, as it is under
ActiveRecord.

The `data_column:` and `format:` options work identically to
ActiveRecord. For `:jsonb`, Sequel loads the `pg_json` extension
automatically and handles JSON typecasting. The block yields an
[`LLM::Agent`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html)
instance. Configure agent defaults in the block -- model, tools,
instructions, tracer, stream, and confirm all go here:

As with ActiveRecord, the model implements `set_provider` and
`set_context`, the plugin takes a tracer as `tracer:`, and a tracer
can be set on the agent in the block.

##### Migration with TEXT column

```ruby
DB.create_table :agents do
  primary_key :id
  String :name
  String :data       # stores the serialized agent state
  DateTime :created_at
  DateTime :updated_at
end
```

##### Migration with JSONB column

```ruby
DB.create_table :agents do
  primary_key :id
  String :name
  column :data, :jsonb  # native JSON storage
  DateTime :created_at
  DateTime :updated_at
end
```

##### Model setup

```ruby
require "sequel"
require "llm"
require "llm/sequel/plugin"

class Agent < Sequel::Model
  plugin(:agent, format: :jsonb) do |agent|
    agent.model "deepseek-v4-pro"
    agent.instructions "solve the user's query"
    agent.tools [Research, FinalizeResearch, ActOnResearch]
    agent.tracer -> { LLM::Tracer.logger(llm, io: $stdout) }
  end

  private

  def set_provider
    LLM.deepseek(key: ENV["KEY"])
  end
end

agent = Agent.create(name: "researcher")
agent.talk "perform research"
# state is saved to the data column automatically
```

#### Why would I use it?

The Sequel plugin integrates with your existing models.
It follows the same conventions as ActiveRecord, so
switching between the two requires minimal code changes.

#### Notes

The `format` option defaults to `:string`. Use `:json` or `:jsonb`
for PostgreSQL. Sequel loads the `pg_json` extension automatically
and wraps JSON values for native storage. JSONB is recommended.
The `data_column` option defaults to `:data`.

The model requires a `set_provider` private method that returns an
[`LLM::Provider`](https://r.uby.dev/api-docs/llm.rb/LLM/Provider.html)
instance, and may implement `set_context` to seed the context with
parameters. Those two are the only callbacks `plugin :llm` and
`plugin :agent` resolve. A tracer is passed to the plugin as
`tracer:`, or set on the agent in the block.

To persist a context instead of an agent, use `plugin :llm`. The
model gains `#llm` (the provider) and `#ctx` (the context), and
persists the same state without the automatic tool loop. An agent
built by `plugin :agent` is bound to its record, which
[`LLM::Agent#record`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#record)
returns.

