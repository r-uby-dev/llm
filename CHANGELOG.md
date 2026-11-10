> Changelog <br>
> [r.uby.dev](https://r.uby.dev) project

This file covers the unreleased v19 series. <br> Older releases can be seen in
[changelog/v18.md](changelog/v18.md),
[changelog/v17.md](changelog/v17.md),
[changelog/v16.md](changelog/v16.md),
[changelog/v15.md](changelog/v15.md),
[changelog/v14.md](changelog/v14.md),
[changelog/v13.md](changelog/v13.md),
and [changelog/v12.md](changelog/v12.md).

## What's next

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
