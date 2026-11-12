> Changelog <br>
> [r.uby.dev](https://r.uby.dev) project

This file covers the v19|v20 series. <br> 
Older releases:  
* [changelog/v18.md](changelog/v18.md)
* [changelog/v17.md](changelog/v17.md)
* [changelog/v16.md](changelog/v16.md)
* [changelog/v15.md](changelog/v15.md)
* [changelog/v14.md](changelog/v14.md)
* [changelog/v13.md](changelog/v13.md)
* [changelog/v12.md](changelog/v12.md)

## What's next

Nothing yet.

## v20.0.0

Changes since `v19.1.1`.

This release adds `LLM::Tool::Unix`, the superclass of the tools that
work only on a unix-like system, and it moves `LLM::Tool::Mkdir` below
it. It also adds `LLM::Tool.git`, `LLM::Tool.unix`, and three unix
tools: `man`, `apropos` and `find`.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `LLM::Tool::Mkdir` | `LLM::Tool::Unix::Mkdir` |
| `require "llm/tools/mkdir"` | `require "llm/tools/unix/mkdir"` |

### LLM::Tool

* **tools: add `LLM::Tool::Unix`** <br>
  [`LLM::Tool::Unix`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix.html)
  is the abstract superclass of the tools that work only on a unix-like
  system, because they depend on a command Windows does not ship
  (`apropos`, `find`, `man`, `mkdir`), or on a system facility that only
  exists there. A tool that works anywhere - reading and writing a file,
  changing directory, spawning a command - is not a unix tool even when
  it is named after a unix command, so it stays at the top level, as
  `LLM::Tool::Exec` does. The superclass is abstract, so it has no name
  and it is not in `LLM::Tool.registry`.

* **tools: `LLM::Tool::Mkdir` is `LLM::Tool::Unix::Mkdir`** <br>
  [`LLM::Tool::Unix::Mkdir`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Mkdir.html)
  is the name of the `mkdir` tool now. It lives at
  `lib/llm/tools/unix/mkdir.rb`, so it is required with
  `require "llm/tools/unix"` rather than `require "llm/tools/mkdir"`.

* **tools: add `LLM::Tool.unix`** <br>
  [`LLM::Tool.unix`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#unix-class_method)
  returns the unix tools, which are the subclasses of `LLM::Tool::Unix`.
  It requires `llm/tools/unix` when it is called, unless the namespace is
  loaded already, so the unix tools are not required up front.

* **tools: add `LLM::Tool.git`** <br>
  [`LLM::Tool.git`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#git-class_method)
  returns the git tools, which are the subclasses of
  [`LLM::Tool::Git`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git.html).
  It requires `llm/tools/git` when it is called, unless the namespace is
  loaded already, so the git tools are not required up front.

* **tools: add a `man` tool** <br>
  [`LLM::Tool::Unix::Man`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Man.html)
  (`man`) reads a manual page and returns it as text, so an agent can look up
  a command or a function before it uses it. It spawns `man` with `-P cat`
  through
  [`LLM::Tool::Exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Exec.html),
  so the page is captured as stdout rather than opened in a pager, and the
  overstrike sequences that `man` writes for bold and underline are collapsed,
  so the page is returned as plain text. It takes the `name:` of the page, an
  optional `section:`, an optional `timeout:` (5 seconds by default) and an
  optional `max_bytes:`. A `name:` that looks like a path is rejected, and
  `$MANPATH` is forwarded when it is set.

* **tools: add an `apropos` tool** <br>
  [`LLM::Tool::Unix::Apropos`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Apropos.html)
  (`apropos`) searches the manual page databases for one or more `keywords:`
  and returns the descriptions that match, the step an agent takes before it
  reads a page with `man`. Each keyword is an argument of its own, so two
  keywords are matched with `or`, and `--` separates them from the options so
  a keyword is never read as a flag. It takes an optional `section:`, which
  is passed as `-s`, an optional `timeout:` (5 seconds by default) and an
  optional `max_bytes:`, and it rejects an empty keyword.

* **tools: add a `find` tool** <br>
  [`LLM::Tool::Unix::Find`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Find.html)
  (`find`) walks a file hierarchy and returns the paths that match, where
  `rg` searches the contents of the files it knows about, `dir-tree` shows
  the shape of a tree up to a depth, and `ls` lists one directory. It takes
  the `path:` to walk (the cwd by default), an optional `name:` glob, an
  optional `type:` of `f`, `d` or `l`, an optional `max_depth:`, an optional
  `newer_than:` in minutes, an optional `limit:` (200 paths by default), an
  optional `timeout:` and an optional `max_bytes:`. It returns
  `{ok:, paths:, count:, truncated:}`, where `truncated:` is true when the
  list was cut at `limit:`, and it rejects a `path:` of `/`.

## v19.1.1

Changes since `v19.1.0`.

This release adds `#intercept` and `#intercept_options` to the
ActiveRecord wrappers, so a record that `acts_as_llm` or
`acts_as_agent` responds to them the way it responds to
`#compactor` and `#compactor_options`, reading both from the
record's runtime.

### ORM

* **orm: add `#intercept` and `#intercept_options` to the ActiveRecord wrappers** <br>
  A record that `acts_as_llm` or `acts_as_agent` responds to
  [`#intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/ActsAsLLM/InstanceMethods.html#intercept-instance_method)
  and
  [`#intercept_options`](https://r.uby.dev/api-docs/llm.rb/LLM/ActiveRecord/ActsAsLLM/InstanceMethods.html#intercept_options-instance_method)
  now, as it does to `#compactor` and `#compactor_options`. Both read
  from the record's runtime, as
  [`LLM::Agent#intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#intercept-instance_method)
  and
  [`LLM::Agent#intercept_options`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#intercept_options-instance_method)
  do.

## v19.1.0

Changes since `v19.0.1`.

This is a feature release. It adds `LLM::Eval#filter`,
`LLM::Agent#intercept` and `LLM::Agent#intercept_options`, two
git tools (`git-clone` and `git-authors`), and a streaming rework
of `LLM::Command`, whose `#stdout`, `#stderr` and `#spawn` yield
each chunk as it is written and read stdout and stderr at the
same time. It also defaults the OpenAI chat `model:` to
`gpt-6-luna`, keeps the compactor, filter and intercept options
out of the request body, and names the files under
`lib/llm/tools` after the tools they define, in kebab-case, which
changes the path a tool file is required by.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `require "llm/tools/dir_tree"` | `require "llm/tools/dir-tree"` |
| `require "llm/tools/read_file"` | `require "llm/tools/read-file"` |
| `require "llm/tools/write_file"` | `require "llm/tools/write-file"` |
| `require "llm/tools/not_found"` | `require "llm/tools/not-found"` |

### LLM::Eval

* **eval: add `LLM::Eval#filter`** <br>
  [`LLM::Eval#filter`](https://r.uby.dev/api-docs/llm.rb/LLM/Eval.html#filter-instance_method)
  takes the block that builds a message filter, the way `#intercept` takes
  the block that builds an intercept. The block returns a message filter,
  eg a `Class.new(LLM::MessageFilter)` that implements `#call`, and it is
  evaluated when the eval runs, so an `agent do ... end` block passes it
  as `filter:`.

### LLM::Tool

* **tools: the files under `lib/llm/tools` are kebab-case** <br>
  Each file is named after the class or method it defines, as
  `edit-file.rb` and `git/ls-files.rb` always were, so `dir_tree.rb`,
  `read_file.rb`, `write_file.rb` and `not_found.rb` are `dir-tree.rb`,
  `read-file.rb`, `write-file.rb` and `not-found.rb`. A tool that is
  required on its own takes the new path, eg `require "llm/tools/read-file"`.

* **tools: add a `git-clone` tool** <br>
  [`LLM::Tool::Git::Clone`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git/Clone.html)
  (`git-clone`) clones a repository into a new directory. It takes the
  `repository:` to clone, an optional `directory:` to clone into, which
  defaults to the name of the repository, and an optional `timeout:`.

* **tools: add a `git-authors` tool** <br>
  [`LLM::Tool::Git::Authors`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git/Authors.html)
  (`git-authors`) returns the authors of a repository with the number of
  commits each has made, the most commits first. It takes an optional
  `path:`, which only counts the commits that touch the path, and an
  optional `timeout:`.

### LLM::Agent

* **agent: add `LLM::Agent#intercept` and `LLM::Agent#intercept_options`** <br>
  The `LLM::Agent` class adds two new methods that provide
  access to an agent's intercept (and its options) at the
  instance level, as `#compactor` and `#compactor_options` do
  for its compactor. By default the intercept is a Null
  intercept that lets every tool call through:
  * [`LLM::Agent#intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#intercept-instance_method)
  <br> returns the intercept (an
  [`LLM::Intercept::Null`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept/Null.html)
  by default)
  * [`LLM::Agent#intercept_options`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#intercept_options-instance_method)
  <br> returns a copy of the intercept options (`{}` by default),
  through the new
  [`LLM::Context#intercept_options`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html#intercept_options-instance_method)

### LLM::Context

* **context: the compactor, filter and intercept options stay out of the request body** <br>
  [`LLM::Context`](https://r.uby.dev/api-docs/llm.rb/LLM/Context.html)
  leaves `compactor_options:`, `filter_options:` and `intercept_options:`
  out of the params it sends to a provider now, where it sent them as
  top-level fields of the request body, next to `model`. They configure
  the context's compactor, filter and intercept, as `compactor:`,
  `filter:` and `intercept:` do, and those are not sent either.

### LLM::OpenAI

* **openai: a chat request defaults to `gpt-6-luna`** <br>
  [`LLM::OpenAI#default_model`](https://r.uby.dev/api-docs/llm.rb/LLM/OpenAI.html#default_model-instance_method)
  returns `gpt-6-luna` now, where it returned `gpt-5.6-luna`, so a chat
  request that is sent without a `model:` is sent as `gpt-6-luna`.

### LLM::Command

* **command: `LLM::Command#stdout` and `LLM::Command#stderr` take a block** <br>
  [`LLM::Command#stdout`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#stdout-instance_method)
  and
  [`LLM::Command#stderr`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#stderr-instance_method)
  yield each chunk of a stream to the block they are given as the command
  writes it, and still return the stream once the command has exited.
  [`LLM::Command#spawn`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#spawn-instance_method)
  takes the same block. A chunk is yielded even after the `#limit` is
  reached, and is dropped rather than stored, so a stream can be read
  without being held in memory.

* **command: stdout and stderr are read at the same time** <br>
  A command's stdout and stderr are each read in a thread of their own
  now, where stdout was read to its end before stderr was read, so a
  command that writes more to stderr than a pipe holds, while it still
  writes to stdout, no longer hangs.

## v19.0.1

Changes since `v19.0.0`.

This is a patch release. It fixes the `:ractor` strategy, which
called `#new` on the `LLM::Tool` instance given to
`LLM::Function#task`, and it makes `llm.rb eval` resolve a
relative path from the working directory. It also defaults the
OpenAI images `model:` to `gpt-image-2.6-flare`, ahead of the
`gpt-image-1-mini` retirement.

### LLM::OpenAI

* **openai: images default to `gpt-image-2.6-flare`** <br>
  [`LLM::OpenAI::Images#create`](https://r.uby.dev/api-docs/llm.rb/LLM/OpenAI/Images.html#create-instance_method)
  and
  [`LLM::OpenAI::Images#edit`](https://r.uby.dev/api-docs/llm.rb/LLM/OpenAI/Images.html#edit-instance_method)
  default the `model:` parameter to `gpt-image-2.6-flare` now, where they
  defaulted it to `gpt-image-1-mini`. OpenAI removes `gpt-image-1-mini` from
  its API on December 1st, 2026. A `model:` that is given is sent unchanged.

### LLM::Function

* **function: the `:ractor` strategy runs a `LLM::Tool` instance** <br>
  [`LLM::Function#task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#task-instance_method)
  runs the [`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
  instance it is given under the `:ractor` strategy, where it called `#new`
  on that instance and raised `NoMethodError`. An instance that takes an
  argument in `#initialize` runs with the state it was given.

### Console

* **console: `llm.rb eval` resolves a relative path from the working directory** <br>
  `llm.rb eval` joins a relative path with `Dir.getwd` now, where it joined
  it with the root of the llm.rb checkout, so the path is read relative to
  the directory the command runs in.

## v19.0.0

Changes since `v18.0.0`.

This is a smaller release than v18. It adds the `LLM::Eval`
framework and the `llm.rb eval` command that runs it,
`LLM::Command`, `LLM::Paint`, and a few tools, and it carries
breaking changes to `LLM::Tracer::PrettyLogger`,
`LLM::Tool::Exec#call` and `LLM::Tool::Utils::Process#spawn`.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `LLM::Tool::Exec#call(arguments: ["echo", "hi"])` | `LLM::Tool::Exec#call(command: "echo", arguments: ["hi"])` |
| `LLM::Tool::Utils::Process#spawn(name:)` | `LLM::Tool::Utils::Process#spawn(command:)` |
| `LLM::Tracer::PrettyLogger` | `LLM::Tracer::EnhancedLogger` |
| `LLM::Tracer.pretty_logger`, and `LLM::Tracer.pretty` | `LLM::Tracer.enhanced_logger`, and `LLM::Tracer.enhanced` |
| `LLM::Command`, an alias for `LLM::Console::Command` | `LLM::Command` spawns a command, and `LLM::Console::Command` is spelled out |
| `LLM::Tool::Utils::Process::Command`, and the `test-cmd.rb` gem | `LLM::Command`, which ships with llm.rb |

### LLM

* **core: `LLM.json.dump` takes a `pretty:` option** <br>
  [`LLM.json.dump`](https://r.uby.dev/api-docs/llm.rb/LLM.html#json-class_method)
  dumps an object with `JSON.pretty_generate` when it is given
  `pretty: true`, so the string it returns is indented and read by a
  person. Without the option it dumps with `JSON.dump`, the way it did
  before. The
  [`LLM::JSONAdapter::Oj`](https://r.uby.dev/api-docs/llm.rb/LLM/JSONAdapter/Oj.html)
  adapter takes no such option.

### LLM::Eval

* **eval: add `LLM::Eval`** <br>
  [`LLM::Eval`](https://r.uby.dev/api-docs/llm.rb/LLM/Eval.html) scores a
  model against a task the way a unit test scores code. An eval is a
  directory that holds an `eval.rb` file and one or more step files, and
  the file declares a name and a description with `set`, the prompts the
  agent is given with `step`, the state it runs against with `setup` and
  `teardown`, the agent, tracer and intercept it runs with through
  `configure`, and the score with `score` and `penalize!`.
  [`LLM::Eval#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Eval.html#call-instance_method)
  sends each step to the agent, runs the score block, subtracts each
  penalty, and returns `{name:, score:}`. A score is a float between 0.0
  and 1.0.

* **eval: add `LLM::Eval.from`** <br>
  [`LLM::Eval.from`](https://r.uby.dev/api-docs/llm.rb/LLM/Eval.html#from-class_method)
  reads an `eval.rb` file, evaluates it, and binds the eval it returns to
  a provider, a model, and a sample number, so the same eval can be run
  against each of them.

* **eval: aggregate samples into a run report** <br>
  When an eval is given a tracer, every sample it runs is added to
  `runs/<eval>/<provider>/<model>/run.json`, which holds each sample beside
  the average score of them all, and `run.txt` beside it holds the same as
  a table. A sample that runs a second time replaces the entry it wrote
  before, so a sample number can be repeated without counting twice.

* **eval: add `LLM::Eval::Tracer::Console`** <br>
  [`LLM::Eval::Tracer::Console`](https://r.uby.dev/api-docs/llm.rb/LLM/Eval/Tracer/Console.html)
  draws an eval as it runs: a line for each request, each tool call, each
  error, and each interrupt, and a summary on exit with the number of
  turns, requests, tool calls and tokens, the slowest call, the score and
  each penalty. The summary is written to
  `runs/<eval>/<provider>/<model>/<sample>/sample.txt` without the escape
  sequences it draws with.

* **eval: add `LLM::Eval::Tracer::JSON`** <br>
  [`LLM::Eval::Tracer::JSON`](https://r.uby.dev/api-docs/llm.rb/LLM/Eval/Tracer/JSON.html)
  records an eval as JSON: each chat request with its model, duration,
  tokens, reply and reasoning, each tool call with its arguments and
  duration, every error, and the score and its penalties. The report is
  written to `runs/<eval>/<provider>/<model>/<sample>/sample.json` on
  exit, as indented JSON.

### LLM::Command

* **command: add `LLM::Command`** <br>
  [`LLM::Command`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html)
  spawns a command without a shell and collects its streams. `#env`,
  `#stdin` and `#limit` configure it, `#spawn` starts it, `#stdout` and
  `#stderr` return what it wrote, and `#status`, `#exit_status` and
  `#success?` report how it ended. A command that is not on the system is
  reported by `#not_found?`, and `#kill!` sends a running command
  `SIGKILL`. The class was imported from the `test-cmd.rb` gem, which
  llm.rb depends on no longer.

### LLM::Tool

* **tools: add a `git-ls-files` tool** <br>
  [`LLM::Tool::Git::LsFiles`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git/LsFiles.html)
  (`git-ls-files`) lists the files git tracks, the index beside the
  changes that `git-status` reports. Like the other git tools it takes
  an optional `path:`, which narrows the list, and an optional `timeout:`.

* **tools: add a `git-pull` tool** <br>
  [`LLM::Tool::Git::Pull`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git/Pull.html)
  (`git-pull`) pulls the changes of a remote branch into the current
  branch. It takes an optional `remote:`, an optional `branch:`, which
  requires a remote, and an optional `timeout:`.

* **tools: add `LLM::Tool::DirTree`** <br>
  [`LLM::Tool::DirTree`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/DirTree.html)
  (`dir-tree`) returns the contents of a directory as a nested hash: a
  directory is a hash of its entries and a file is `nil`. It takes the
  `path:` to walk and an optional `depth:`, which is five levels by
  default, and it raises when the path does not exist.

* **tools: the git tools take a `cwd:`** <br>
  Each tool that
  [`LLM::Tool::Git`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git.html)
  provides takes an optional `cwd:`, which names the repository to run
  in. The command is built as `git -C <cwd>` rather than run from the
  process's working directory, so a tool call can reach a repository
  outside the one the process was started in, and two tool calls that run
  at the same time can reach different repositories. It is `Dir.getwd` by
  default, and the superclass declares the parameter, so every git tool
  has it.

* **tools: `LLM::Tool::Exec#call` takes a command and its arguments apart** <br>
  [`LLM::Tool::Exec#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Exec.html#call-instance_method)
  takes the command to run as `command:` and its arguments as
  `arguments:`, where `arguments:` alone took the command and its
  arguments as one array. The parameter the model is given is split the
  same way, so a model passes a `command` and, separately, an `arguments`
  array, and `command` is the required one.

* **tools: `LLM::Tool::Utils::Process#spawn` takes `command:`** <br>
  [`LLM::Tool::Utils::Process#spawn`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils/Process.html#spawn-instance_method)
  takes the command to run as `command:`, where it took it as `name:`, so
  the keyword matches the one `LLM::Tool::Exec#call` takes. A tool of
  your own that spawns a command passes `command:` now.

### LLM::Function

* **function: `LLM::Function#task(:ractor)` accepts a tool instance** <br>
  [`LLM::Function#task`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#task-instance_method)
  accepts an instance of [`LLM::Tool`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html)
  when it is given the `:ractor` strategy, where it took a class alone and
  raised `LLM::RactorError` for an instance. A runner that is neither a
  class nor an instance of `LLM::Tool` still raises
  [`LLM::RactorError`](https://r.uby.dev/api-docs/llm.rb/LLM/RactorError.html).

* **function: an unknown tool returns its error in band under `:ractor`** <br>
  A tool call for a tool the runtime does not know is turned into an
  anonymous subclass of `LLM::Tool` whose `#call` raises
  [`LLM::NoSuchToolError`](https://r.uby.dev/api-docs/llm.rb/LLM/NoSuchToolError.html),
  and the runtime returns that error to the model in band, the way the
  other strategies do. The tool is a class rather than a proc, so the
  `:ractor` strategy runs it, where it raised `LLM::RactorError` before.

* **function: the `LLM::RactorError` names the function and its runner** <br>
  The `LLM::RactorError` that `LLM::Function#task` raises for a runner the
  `:ractor` strategy cannot use names the function and inspects the
  runner, where its message was one generic line.

### Console

* **console: add `llm.rb eval`** <br>
  `llm.rb eval -p <provider> [-m <model>] [-n <samples>] <path...>` runs
  the evals it is given, and it hands off to `libexec/llm-eval`. The
  provider is built from `-p`, which is required, the model is taken from
  `-m` or from the provider's `default_model`, and each eval is run `-n`
  times, where `-n` is 1 by default. A relative path is resolved against
  the root of the llm.rb checkout.

* **console: `models.dev:download` is `update-data`** <br>
  The command that refreshes the `data/` directory from models.dev is
  `llm.rb update-data` now, and `llm.rb models.dev:download` is still
  accepted.

### LLM::Paint

* **paint: add `LLM::Paint`** <br>
  [`LLM::Paint`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint.html) wraps
  a string in the escape sequences a terminal understands, eg
  `LLM::Paint["hello", :blue, :bold]`, and returns the string unchanged
  when color is disabled. It honors `$NO_COLOR`, it is a small stand-in
  for the `paint` gem, and it is what the eval console tracer uses.

* **paint: add `LLM::Paint::IO`** <br>
  [`LLM::Paint::IO`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint/IO.html) wraps
  an IO so that the text written to it is wrapped in the escape sequences a
  terminal understands, and written unchanged when color is disabled.
  [`LLM::Paint::IO#write`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint/IO.html#write-instance_method)
  writes text with the colors and effects it is given,
  [`LLM::Paint::IO#puts`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint/IO.html#puts-instance_method)
  writes it with a newline,
  [`LLM::Paint::IO#color?`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint/IO.html#color?-instance_method)
  returns true when the wrapper writes color,
  [`LLM::Paint::IO#color=`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint/IO.html#color=-instance_method)
  sets it, and
  [`LLM::Paint::IO#io`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint/IO.html#io-instance_method)
  returns the IO that is wrapped.

* **paint: `LLM::Paint.detect` takes an IO** <br>
  [`LLM::Paint.detect`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint.html#detect-class_method)
  takes the IO to inspect as an argument now, where it inspected `$stdout`
  alone. It still returns false when `$NO_COLOR` is set, and it returns
  false for an IO that does not respond to `tty?`.

### LLM::Tracer

* **tracer: rename `LLM::Tracer::PrettyLogger` as `LLM::Tracer::EnhancedLogger`** <br>
  [`LLM::Tracer::EnhancedLogger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/EnhancedLogger.html)
  is the tracer that `LLM::Tracer::PrettyLogger` was.
  [`LLM::Tracer.enhanced_logger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#enhanced_logger-class_method)
  builds it,
  [`LLM::Tracer.enhanced`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer.html#enhanced-class_method)
  is its alias, and both replace `LLM::Tracer.pretty_logger` and
  `LLM::Tracer.pretty`.

* **tracer: the enhanced logger draws a readable log** <br>
  A chat request, a tool call and an interrupt are each a line of their
  own, with a marker that names the event, a duration for a request and a
  tool call, and the tokens a request used. The timestamp, and the comma
  separated fields it prefixed, are gone.

* **tracer: the enhanced logger writes a summary on exit** <br>
  [`LLM::Tracer::EnhancedLogger#on_exit`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/EnhancedLogger.html#on_exit-instance_method)
  writes the provider, the model, the number of requests, the tool calls
  with a breakdown by name, the tokens returned in and out, the cost the
  registry prices them at, the slowest tool call, the errors, and the
  elapsed time. It is written only when the tracer saw a request or a tool
  call, and it closes the file the tracer opened.

* **tracer: the enhanced logger writes color** <br>
  [`LLM::Tracer::EnhancedLogger`](https://r.uby.dev/api-docs/llm.rb/LLM/Tracer/EnhancedLogger.html)
  writes through an
  [`LLM::Paint::IO`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint/IO.html),
  so its log is colored when the IO it writes to is a terminal, and plain
  when it is not, when `$NO_COLOR` is set, or when
  [`LLM::Paint.enabled`](https://r.uby.dev/api-docs/llm.rb/LLM/Paint.html#enabled=-class_method)
  is false.
