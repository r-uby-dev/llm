## Console

### Introduction

#### Overview

The console drops you into a curses-based TUI for talking to an agent
interactively. It has a scrollable buffer that renders markdown,
a multi-line input area, and a status bar showing context usage and
cost. The UI thread stays responsive while a second thread communicates
with the model. Think of it as `binding.irb` but for agents.

#### How it works

The console runs on two threads: one for the curses UI (input handling,
buffer rendering, status bar) and one for model communication.

The `name:` option labels the agent in the prompt. The `path:`
option persists state across sessions. The `tools:` option attaches
extra tools for the session.

Commands start with `/` and are dispatched to registered
[`LLM::Command`](https://r.uby.dev/api-docs/llm.rb/LLM/Console/Command.html)
subclasses. Type `/keep` to free context
window space, `/exit` to leave.

The top chrome row shows the current working directory on the left
and the active model on the right. Switch models mid-session with
`/model <name>`; the model name updates there immediately.

When characters arrive faster than a threshold, the console detects
paste mode. In paste mode, pressing Enter inserts a newline instead
of submitting.

Start a session with:

```ruby
require "llm"
require "llm/tools"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, name: "my-agent", path: "session.json")
agent.console(tools: LLM::Tool.subclasses)
```

#### Why would I use it?

The console gives you an interactive environment to test agents, debug
tool calls, and inspect conversation state without writing a
separate UI. Drop in after running an agent to confirm it did what
you expected. Inspect what went wrong when it did not. Keep talking
to the same agent while its state is still intact. It is
`binding.irb` but for agents.

#### Notes

The console requires the `curses` and `kramdown` gems. By default the
tracer is disabled during the session. Set `tracer: true` to keep
it active.

The loop was previously named the REPL. `LLM::Repl` and
`LLM::Agent#repl` still resolve to `LLM::Console` and
`LLM::Agent#console`, so existing code keeps working, but new code
should use the `console` names.

When `bin/llm.rb` starts, it looks for an `AGENTS.md` file in the
current working directory. If one exists, its contents become the
agent's instructions for the session, so a project can describe how it
wants the agent to work without passing flags. The agent brings its
instructions up to date before each request, so a resumed session runs
on the current file rather than the one it was saved with.

The user-message label is exposed through
[`LLM::Console#sender`](https://r.uby.dev/api-docs/llm.rb/LLM/Console.html#sender-instance_method),
which defaults to `"You"`. The
[`LLM::Console#write_message`](https://r.uby.dev/api-docs/llm.rb/LLM/Console.html#write_message-instance_method)
and
[`LLM::Console::Buffer#write_message`](https://r.uby.dev/api-docs/llm.rb/LLM/Console/Buffer.html#write_message-instance_method)
helpers write a formatted `user:` message with a trailing newline,
and `LLM::Command#write_message` matches the same interface.

### The `llm.rb` executable

#### Overview

The console also starts from a shell. After the gem is installed,
`llm.rb` puts a console on your PATH and opens a session in the current
directory, so there is no Ruby file to write.

#### How it works

Run `llm.rb` with no arguments to auto-detect a provider from the usual
environment variables, or name one with `-p`. The session for the
current directory is kept under `~/.llm.rb/` and restored on the next
visit, unless `-t` asks for a temporary one:

```bash
llm.rb                         # auto-detect from $PROVIDER_API_KEY
llm.rb -p openai               # use OpenAI explicitly
llm.rb -m gpt-5.6              # use a model other than the provider default
llm.rb -c thread               # run tool calls on a separate thread
llm.rb -n net-http-persistent  # pool HTTP connections
llm.rb -x 900                  # read timeout of 15 minutes
llm.rb -t                      # temporary session, no persistence
llm.rb -v                      # print the version
llm.rb -h                      # print usage
```

#### Why would I use it?

It is the shortest path to a working session: no script, no `require`,
and a conversation that is still there tomorrow. Reach for
`agent.console` instead when the agent needs a provider, tools, or a
tracer that only your application can supply.

#### Notes

The switches are the console's own, so `-c`, `-m`, and `-p` set the
same things `agent.console` takes from its agent. `-v` and `-h` print
and exit.

### Switch the model

The active model is exposed through
[`LLM::Console#model`](https://r.uby.dev/api-docs/llm.rb/LLM/Console.html#model-instance_method)
and
[`LLM::Console#model=`](https://r.uby.dev/api-docs/llm.rb/LLM/Console.html#model=-instance_method),
seeded from the agent at startup. The `/model` command switches it
mid-session, and its argument auto-completes through the provider's
text-capable models (those where
[`LLM::Registry::Model#text?`](https://r.uby.dev/api-docs/llm.rb/LLM/Registry/Model.html#text%3F-instance_method)
is true), so you can cycle through the available model names with
Tab. The top chrome row reflects the change immediately.

### Commands

Commands use the same vocabulary as tools: declare a name,
description, and parameters with `parameter` and `required`.
Subclassing an existing command inherits its name, description,
and parameters. This is how `/quit` is an alias of `/exit`.

```ruby
class Greeter < LLM::Command
  name "greet"
  description "Greets the given name"
  parameter :name, String, "The person's name"
  required %i[name]

  def call(name:)
    write "Welcome #{name}!\n"
  end
end
```

To add argument completion to a custom command, override the
`complete` method. It receives the command's parameters as keyword
arguments, where the non-nil one is the fragment being typed, and
returns the candidate completions. Pressing Tab cycles through them:

```ruby
class SwitchEnv < LLM::Command
  name "env"
  description "switch the working environment"
  parameter :env, String, "The environment name"
  required %i[env]

  def call(env:)
    write "Switched to #{env}"
  end

  private

  def complete(env: nil)
    %w[staging production].select { _1.start_with?(env.to_s) }
  end
end
```

The input area supports several keyboard shortcuts:

| Key | Action |
|---|---|
| `Ctrl+A` | Jump to the start of the line |
| `Ctrl+E` | Jump to the end of the line |
| `Ctrl+F` | Move cursor forward by one column |
| `Ctrl+K` | Erase from cursor to end of line |
| `Ctrl+P` / `Ctrl+N` | Recall previous / next user message |
| `Ctrl+Y` | Paste previously killed text |
| `Enter` | Submit the current prompt |
| `Tab` | Complete `/command` names and arguments |
| `Esc` | Cancel the current request |
| `Up` / `Down` | Scroll the buffer one line |
| `PgUp` / `PgDn` | Scroll the buffer by one page |
