> Changelog <br>
> [r.uby.dev](https://r.uby.dev) project

This file covers the v19|v20|v21 series. <br> 
Older releases:  
* [changelog/v18.md](changelog/v18.md)
* [changelog/v17.md](changelog/v17.md)
* [changelog/v16.md](changelog/v16.md)
* [changelog/v15.md](changelog/v15.md)
* [changelog/v14.md](changelog/v14.md)
* [changelog/v13.md](changelog/v13.md)
* [changelog/v12.md](changelog/v12.md)

## What's next

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `Model.agent`, on a model that `acts_as_agent` or `plugin :agent` | `Model.__agent__` |

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

## v21.1.0

Changes since `v21.0.0`.

This is a feature release. It adds two unix tools - `unix-valgrind` and
`unix-honggfuzz` - and `LLM::Command` gains `#tail`, `#streams` and
`#wait`, renames `#limit` to `#head`, signals the process group so a
signal reaches the programs the command started, and treats a signal
that lands on a command that has exited as a no-op. Tools keep the tail
of a command's output within `max_bytes` and escalate SIGTERM to
SIGKILL, `LLM.now` measures a duration against a monotonic clock,
`LLM::Schema::Enum` raises when a value is a collection, and
`LLM::Function#call` turns an exception that is not a `StandardError`
into an error return. The async layer gains `LLM::TaskError`, a reactor
that wakes on a pipe rather than a blocking `Queue#pop`, and a task that
no longer stops a reactor it shares, while
`LLM::Function::Task#report!` tells the tracer how a task ended and
`LLM::Stream#on_tool_return` fires as each tool returns.

* **unix: add `LLM::Tool::Unix::Valgrind`** <br>
  [`LLM::Tool::Unix::Valgrind`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Valgrind.html)
  runs a program under `valgrind` and returns the report it wrote to stderr. It
  builds the argument vector itself - `--tool=`, the memcheck options,
  `--error-exitcode=`, `--`, the program, then the arguments of the program - and
  it forwards $VALGRIND_LIB, $VALGRIND_OPTS and $DEBUGINFOD_URLS. It is the tool
  that reads the failure `unix-cc` and `unix-nm` cannot see: an invalid read, an
  invalid write, an uninitialised value or a leak. It defaults to memcheck, to a
  nonzero `--error-exitcode` so a report arrives as a failed tool call, and to a
  300 second timeout because valgrind is slow.

* **unix: add `LLM::Tool::Unix::HonggFuzz`** <br>
  [`LLM::Tool::Unix::HonggFuzz`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/HonggFuzz.html)
  (`unix-honggfuzz`) fuzzes a program with honggfuzz, where `unix-valgrind` runs
  one input and honggfuzz hunts for the input that breaks it: it mutates a
  corpus and runs the program on what it produces. It spawns `honggfuzz`
  without a shell and builds the argument vector itself - the flags, then `--`,
  then the program and the arguments the program is fuzzed with - so a flag of
  the program is never read as a flag of honggfuzz. honggfuzz tells the program
  where the mutated input is by replacing `___FILE___` in its arguments, which
  is why `arguments:` defaults to that placeholder; with `stdin: true` (`-s`)
  the input arrives on stdin instead, and the default is dropped rather than
  left as a path the program would receive. honggfuzz runs until it is killed,
  so every call is bounded by `timeout:`, 120 seconds by default, or by
  `iterations:` (`-N`, unlimited at 0), and a killed run returns the log it
  wrote before it died. `nullify_stdio:` (`-q`) and `plain:` (`-v`) are on by
  default so the log is not buried in the program's own output and is returned
  without the ANSI escape sequences honggfuzz draws with, and the crashes and
  the report are read afterwards from `workspace:` (`-W`) and `report:` (`-R`).

* **command: add `LLM::Command#tail`** <br>
  [`LLM::Command#tail`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#tail-instance_method)
  keeps the last n bytes of each stream rather than the first n, so
  `LLM::Command.new("ls").tail(stdout: 123, stderr: 456)` returns the end of
  the output, which is where a command says what went wrong. The stream is
  still read to its end, because a child that writes into a pipe nobody reads
  blocks on it, and the buffer is cut back after every chunk, so the bound is
  on what is held rather than on what is read. A stream that is tailed is
  returned as text with the invalid bytes scrubbed, so a cut that lands inside
  a character is a string a JSON encoder accepts.

* **command: `LLM::Command#limit` is `LLM::Command#head`** <br>
  [`LLM::Command#head`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#head-instance_method)
  keeps the first n bytes of each stream and is what `#limit` was. `#limit` is
  its alias, so a call that uses either name is capped the same way.

* **command: add `LLM::Command#streams`** <br>
  [`LLM::Command#streams`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#streams-instance_method)
  returns what the command has written so far, as `{stdout:, stderr:}`, without
  waiting for it to finish. It is what a caller reads from a command it killed,
  where `#stdout` and `#stderr` block on a producer that may be waiting for a
  child the signal never reached.

* **command: add `LLM::Command#wait`** <br>
  [`LLM::Command#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#wait-instance_method)
  waits, up to the seconds it is given, for the command to be reaped, and
  returns true when it was, or false when the seconds ran out. It is how a
  caller asks whether a signal it sent was enough without joining a child that
  may never exit.

* **command: a signal reaches the programs the command started** <br>
  [`LLM::Command#signal`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#signal-instance_method)
  sends its signal to the process group of the spawned command on every system
  but Windows, where it signalled the command alone, so a signal reaches the
  programs a command started rather than the command by itself.

* **command: a signal that lands on a command that already exited is not an error** <br>
  [`LLM::Command#signal`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#signal-instance_method)
  returns `nil` when the process is gone, where it raised `Errno::ESRCH`. A
  command exits between the decision to stop it and the signal itself, and
  stopping a command that has stopped already is what the signal was for.

* **tools: a command that ignores SIGTERM is killed anyway** <br>
  [`LLM::Tool::Utils::Process#terminate!`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils/Process.html#terminate!-instance_method)
  sends SIGTERM to a command that outlives its `timeout:`, waits half a second,
  and sends SIGKILL when the command is still running. A debugger, a process
  under a tracer, and a program with a TERM handler of its own ignore the
  request, and a tool that waits on one of them reads a status and an output
  that wait for the child to be reaped - so the escalation is what makes
  `timeout:` a bound rather than a suggestion.

* **tools: a tool keeps the last `max_bytes` of a command's output** <br>
  [`LLM::Tool::Utils::Process#exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils/Process.html#exec-instance_method)
  caps each stream at the tool's `max_bytes` from the end now, where it kept the
  bytes at the front: a command says what went wrong last, so the end of the
  stream is the part a model is handed. The stream is still read to its end, so
  the cap bounds what a tool holds without bounding what it reads, and what the
  tool returns is within the cap already, so the marker that said the output
  was truncated is not added.

* **schema: `LLM::Schema::Enum` raises when a value is a collection** <br>
  [`LLM::Schema::Enum`](https://r.uby.dev/api-docs/llm.rb/LLM/Schema/Enum.html)
  raises when it is given an array or a hash as a value, so `Enum[Fruit.keys]`
  - the splat that was left out - is rejected where it used to build an enum
  whose one value was a collection, and the message names the splat that was
  missing.

* **core: add `LLM.now`** <br>
  [`LLM.now`](https://r.uby.dev/api-docs/llm.rb/LLM.html#now-class_method)
  returns the time from a monotonic clock, so a duration is measured against a
  clock that does not jump when the system clock is adjusted. It is the clock
  [`LLM::Command#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#wait-instance_method)
  measures its deadline with.

* **gem: `Gem.win_platform?` is Ractor-safe** <br>
  [`LLM::Gem#win_platform?`](https://r.uby.dev/api-docs/llm.rb/LLM/Gem.html#win_platform?-instance_method)
  returns a value that is computed when the library loads, where RubyGems' own
  method memoizes into a class variable on first use, which a Ractor can't set.
  It is what `LLM::Command` asks on every call, so a tool that spawns a command
  under the `:ractor` strategy is where it showed.

* **function: a tool that raises what is not a `StandardError` returns the error** <br>
  [`LLM::Function#call`](https://r.uby.dev/api-docs/llm.rb/LLM/Function.html#call-instance_method)
  returns an error to the model when the tool it ran raises an exception that
  does not descend from `StandardError`, where that exception escaped the call
  and took the caller with it. `LLM::Interrupt` is the one exception that is
  raised still, because a call that was cancelled is not a call that failed.

* **async: add `LLM::TaskError`** <br>
  [`LLM::TaskError`](https://r.uby.dev/api-docs/llm.rb/LLM/TaskError.html) is
  the error a task returns when it ends without a response - the tool pushed
  nothing, and the reactor is gone - so
  [`LLM::Function::Async::Task#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Async/Task.html#wait-instance_method)
  returns that error rather than waiting on a queue nothing will push to.

* **async: a task does not stop a reactor it shares** <br>
  [`LLM::Function::Async::Task#wait`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Async/Task.html#wait-instance_method)
  stops the reactor the task ran on when the task owns it, and leaves it
  running when the task is one of a group, where it stopped the reactor its
  siblings were still running on. A group stops the reactor once its last task
  has returned.

* **async: a reactor waits for work without stalling the tasks it runs** <br>
  [`LLM::Function::Async::Reactor`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Async/Reactor.html)
  learns that it has work from a pipe that `#submit` and `#stop`
  write to, and drains the inbox without blocking, where its own
  fiber sat in a blocking `Queue#pop`. A fiber parked on a pipe
  yields to the event loop, so the timers and the IO of the tasks a
  reactor runs still make progress while it waits for the next item -
  and a command that outlives its `timeout:` is killed, where it was
  left running beside a reactor that could not wake to stop it.

* **function: add `LLM::Function::Task#report!`** <br>
  [`LLM::Function::Task#report!`](https://r.uby.dev/api-docs/llm.rb/LLM/Function/Task.html#report!-instance_method)
  tells the tracer how a task ended - `on_tool_interrupt` for an interrupt,
  `on_tool_error` for an error return, `on_tool_finish` for the rest - and
  calls the hook `#on_return=` was given with the same value. It reports once,
  so a second call is a no-op, and the report comes from the task itself, so a
  task that is waited on alone tells the tracer too, where only a group did.

* **stream: `LLM::Stream#on_tool_return` fires as each tool returns** <br>
  [`LLM::Stream#on_tool_return`](https://r.uby.dev/api-docs/llm.rb/LLM/Stream.html#on_tool_return-instance_method)
  is called when the task that ran the tool ends, so a turn's tools are
  reported in the order they returned rather than in the order they were
  queued. A task reports the tool it ran once, so a group that waits on it
  does not report it twice, and a fork or a ractor task reports as its child
  ends - before the caller waits, where every tool was reported after all of
  them had been waited on.

* **intercept: `LLM::Intercept::Multi` takes an intercept instance** <br>
  [`LLM::Intercept::Multi`](https://r.uby.dev/api-docs/llm.rb/LLM/Intercept/Multi.html)
  accepts an instance of an intercept, as well as the subclass it accepted
  before, so `LLM::Intercept.multi(llm, Logging.new(llm), Auditing)` builds a
  group of two. A subclass is still built with `#new`, and an instance is used
  as it is given, where it was sent `#new` and raised `NoMethodError`.

* **agent: a file attachment reaches the first request of a turn** <br>
  [`LLM::Agent#ask`](https://r.uby.dev/api-docs/llm.rb/LLM/Agent.html#ask-instance_method)
  attaches the files it is given when a turn starts, and drops `with:` from the
  requests the tool loop sends after that, so a turn that runs tool calls
  attaches a file once, where the loop carried `with:` on every request.

## v21.0.0

Changes since `v20.0.0`.

This is a major release. The tool registry is namespaced: every tool
below `LLM::Tool::Unix` registers with a `unix-` prefix and every tool
below the new `LLM::Tool::FreeBSD` with a `freebsd-`, which retires the
`pwd`/`ls` collision and renames four existing tools. It adds the
`LLM::Tool::RubyLang` family (`ruby-lang-issues`, `ruby-lang-issue`,
`ruby-lang-projects`, `ruby-lang-search`), the FreeBSD family
(`freebsd-truss`, `freebsd-pkg-search`, `freebsd-pkg-install`,
`freebsd-sockstat`, `freebsd-procstat`, `freebsd-sh`), eight unix
tools and `git-grep`. `LLM::Command` grows `#chain`, `#chdir`,
`#to_argv`, `#graceful_exit`, `#hard_exit!` and `#signal`, every
command-spawning tool routes through `LLM::Tool::Utils::Process#run`
and `#exec` with a per-tool `max_bytes`, and the Sequel plugins gain
the compactor and intercept readers.

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `LLM::Command#kill!` | `LLM::Command#hard_exit!` |
| `LLM::Tool::Exec.max_bytes(n)`, which capped every tool that spawns a command | `LLM::Tool::Exec.max_bytes(n)` for `exec` alone, and `max_bytes` on the tool class itself, eg `LLM::Tool::Unix::Man.max_bytes(n)` |
| `require "llm/tools/freebsd/proc_stat"` | `require "llm/tools/freebsd/proc-stat"` |
| `LLM::Tool::Unix` tool names, eg `man`, `apropos`, `find` and `mkdir` | `unix-man`, `unix-apropos`, `unix-find` and `unix-mkdir` |

### LLM::Command

* **command: add `LLM::Command#chain`** <br>
  [`LLM::Command#chain`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#chain-instance_method)
  runs one command through another: it splices the chained command's argv
  onto its own, and takes its environment, its working directory, its standard
  input and its stream limits, so
  `jexec.chain(ls).stdout { print it }` is `ls` printing the listing that
  `jexec` sees inside the jail.

* **command: add `LLM::Command#chdir`** <br>
  [`LLM::Command#chdir`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#chdir-instance_method)
  sets the directory the command is spawned in, which is passed to
  `Process.spawn` as `chdir:`. A command that is not given one runs in the
  working directory of the process that spawns it.

* **command: add `LLM::Command#to_argv`** <br>
  [`LLM::Command#to_argv`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#to_argv-instance_method)
  returns the command and its arguments as an array of strings, so one command
  can be handed to another, and `#to_a` is its alias.

* **command: `LLM::Command#arguments` splices a command** <br>
  [`LLM::Command#arguments`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#arguments-instance_method)
  splices a command it is given into the argument list, so
  `jexec.arguments(*ls)` and `jexec.arguments(*ls.to_argv)` build the same
  argv.

* **command: `LLM::Command#env` returns the environment when it is given no argument** <br>
  [`LLM::Command#env`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#env-instance_method)
  returns the environment the command was given now, where it required an
  argument. With an argument it still merges the variables into the
  environment, which is how `#chain` takes the environment of the command it
  chains.

* **command: add `LLM::Command#graceful_exit`** <br>
  [`LLM::Command#graceful_exit`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#graceful_exit-instance_method)
  sends SIGTERM to a running command, so it exits the way a command expects to:
  it closes what it opened and writes what it holds, where `#hard_exit!` drops
  it. It returns `nil` when the command is not running, and it raises
  `SystemCallError` when the signal can't be delivered.

* **command: add `LLM::Command#hard_exit!`** <br>
  [`LLM::Command#hard_exit!`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#hard_exit!-instance_method)
  sends SIGKILL to a running command, the signal that can't be caught, and
  returns `nil` when the command is not running. It replaces `#kill!`, which
  sent the same signal.

* **command: add `LLM::Command#signal`** <br>
  [`LLM::Command#signal`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#signal-instance_method)
  sends the signal it is given to the command's process, by name or by number
  (`#signal("SIGHUP")`, `#signal(1)`), which is how `#graceful_exit` and
  `#hard_exit!` send theirs.

* **command: `LLM::Command#signal` sends SIGKILL on Windows instead of SIGTERM** <br>
  [`LLM::Command#signal`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#signal-instance_method)
  sends SIGKILL to the command's process when it is given `"SIGTERM"` on Windows,
  which has no SIGTERM to deliver, so `#graceful_exit` ends a command there
  instead of raising. Every other signal, and `"SIGTERM"` on every other system,
  is sent unchanged.

### LLM::Tool

* **tools: every tool below `LLM::Tool::Unix` is prefixed with `unix-`** <br>
  Each tool that
  [`LLM::Tool::Unix`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix.html)
  provides registers under a name that begins with `unix-` now, so `man` is
  `unix-man` and `mkdir` is `unix-mkdir`. `LLM::Tool.registry` is keyed on the
  name, and `pwd` and `ls` were the two names it could not keep apart:
  `LLM::Tool::Pwd` and `LLM::Tool::Unix::Pwd` both registered as `pwd`, so
  whichever loaded last shadowed the other, and
  `LLM::Tool.find_by_name!("pwd")` returned one of the two at random. The class
  names, the argument vectors and the results are unchanged, and so is
  `LLM::Tool.unix`.

* **tools: add `LLM::Tool::FreeBSD`** <br>
  [`LLM::Tool::FreeBSD`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/FreeBSD.html)
  is the abstract superclass of the tools that work only on FreeBSD: a command
  FreeBSD ships and the other systems do not, or a facility that only exists
  there. `truss` is the first - Linux traces a process with `strace` and macOS
  with `dtruss`, and the three do not share an argument vector - `pkg` is the
  second, so the tools below it are named after the subcommand,
  `freebsd-pkg-search` before `freebsd-pkg-install`, and `freebsd-sockstat`,
  `freebsd-procstat` and `freebsd-sh` are the rest. It is abstract, so it has
  no name and it is not in `LLM::Tool.registry`.

* **tools: add `LLM::Tool.freebsd`** <br>
  [`LLM::Tool.freebsd`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#freebsd-class_method)
  returns the FreeBSD tools, which are the subclasses of `LLM::Tool::FreeBSD`.
  It requires `llm/tools/freebsd` when it is called, unless the namespace is
  loaded already, so the FreeBSD tools are not required up front.

* **tools: every tool below `LLM::Tool::FreeBSD` is prefixed with `freebsd-`** <br>
  Each tool that `LLM::Tool::FreeBSD` provides registers under a name that
  begins with `freebsd-` now, so `truss` is `freebsd-truss` and `sh` is
  `freebsd-sh`. Nothing collides today, but `sh` is the next `pwd`/`ls`: a
  generic top-level shell tool would register under the same name, so the
  prefix keeps the two namespaces apart. The class names, the argument vectors
  and the results are unchanged, and so is `LLM::Tool.freebsd`.

* **tools: add `LLM::Tool::RubyLang`** <br>
  [`LLM::Tool::RubyLang`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/RubyLang.html)
  is the abstract superclass of the tools that read bugs.ruby-lang.org, the
  Redmine that Ruby tracks its bugs, its features and its backports in, over the
  REST API every Redmine has: a path, a `.json` extension, and query parameters
  that Redmine calls filters. It talks to the host with `Net::HTTP` over TLS, one
  client per tool instance, and `#get` returns `{ok:, status:, body:}` when
  Redmine responds with a 2xx, or `{ok: false, status:, error:}` when it does
  not, so a tool hands a failed request to the model rather than raising.
  Only the public endpoints are below it, because the write endpoints want an API
  key, and it is abstract, so it has no name and it is not in
  `LLM::Tool.registry`.

* **tools: add `LLM::Tool.rubylang`** <br>
  [`LLM::Tool.rubylang`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#rubylang-class_method)
  returns the ruby-lang.org tools, which are the subclasses of
  `LLM::Tool::RubyLang`. It requires `llm/tools/ruby-lang` when it is called,
  unless the namespace is loaded already, so the ruby-lang.org tools are not
  required up front.

* **tools: add a `ruby-lang-issues` tool** <br>
  [`LLM::Tool::RubyLang::Issues`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/RubyLang/Issues.html)
  (`ruby-lang-issues`) lists the issues on bugs.ruby-lang.org with
  `GET /issues.json`, the search that comes before the issue a model was given no
  number for. `status:` is `open`, `closed` or `*` for either, and it is `open`
  by default so the live bugs are not buried under the closed ones, `subject:`
  matches a substring of the title, and `project_id:` and `tracker_id:` are the
  ids the projects tool returns, while `author_id:` and `assigned_to_id:` name a
  person by id.
  `sort:` is a field and a direction (`updated_on:desc` by default), `include:`
  names the parts to read beside each issue, `limit:` is 25 by default and at
  most 100, and `offset:` walks the pages. It rejects a status that is not one of
  the three, an empty subject, an id that is not a positive integer, an include
  Redmine does not know, a sort that is not a field followed by a direction, and
  a limit outside 1 to 100.

* **tools: add a `ruby-lang-issue` tool** <br>
  [`LLM::Tool::RubyLang::Issue`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/RubyLang/Issue.html)
  (`ruby-lang-issue`) reads one issue by number with `GET /issues/:id.json`, the
  call that follows a number somebody quoted. It requires the `id:` of the issue,
  and `include:` takes `journals`, where a note and the field changes beside it
  arrive together: what was written, and the status, the assignee and the
  backport that were changed under it. It also takes `attachments`, `relations`,
  `children`, `changesets`, `allowed_statuses` and `watchers`, and it rejects an
  id that is not a positive integer and an include it does not know. The
  description and the notes are returned as Redmine markup, and a private issue
  and an issue that does not exist are both a 404 to an anonymous caller.

* **tools: add a `ruby-lang-projects` tool** <br>
  [`LLM::Tool::RubyLang::Projects`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/RubyLang/Projects.html)
  (`ruby-lang-projects`) lists the projects on bugs.ruby-lang.org with
  `GET /projects.json`, the tree an issue listing is narrowed by: Ruby is the
  root and its subprojects are where the issues sit, so a `project_id:` comes
  from here. `include:` takes `trackers`, which is where the id a `tracker_id:`
  filter wants comes from, and `issue_categories`, `enabled_modules`,
  `time_entry_activities` and `issue_custom_fields` beside it. A project is
  returned with an identifier and an id, and the two are not the same thing: the
  identifier is the slug in a URL and the id is the number a filter takes.
  `limit:` is 100 by default and at most 100, and `offset:` walks the pages. It
  rejects an unknown include, a limit outside 1 to 100 and a negative offset.

* **tools: add a `ruby-lang-search` tool** <br>
  [`LLM::Tool::RubyLang::Search`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/RubyLang/Search.html)
  (`ruby-lang-search`) searches bugs.ruby-lang.org with Redmine's own index,
  `GET /search.json`, which reads the descriptions and the journals as well as
  the titles, where an issue listing filters the fields. It requires the
  `query:`, and `scope:` is one of `issues` (the default), `news`, `documents`,
  `changesets`, `wiki`, `messages` or `all`. `titles_only:` narrows the search to
  what a title says, `limit:` is 25 by default and at most 100, and `offset:`
  walks the pages. It rejects an empty query, an unknown scope, a limit outside
  1 to 100 and a negative offset.

* **tools: every tool that spawns a command reaches the process through `#run`** <br>
  [`LLM::Tool::Utils::Process#run`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils/Process.html#run-instance_method)
  starts a command for every builtin tool that spawns one, where a tool used
  to build an
  [`LLM::Tool::Exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Exec.html)
  and call `#call` on it. The command it is handed is complete - argv,
  environment, byte limits and the directory it runs in - so a tool that
  replaces `#run`, to run a command in a jail, in a container or on the far
  side of an ssh, replaces it for every command the tool runs.

* **tools: add `LLM::Tool::Utils::Process#exec`** <br>
  [`LLM::Tool::Utils::Process#exec`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Utils/Process.html#exec-instance_method)
  spawns a command, waits for it within a timeout, and returns
  `{ok:, stdout:, stderr:, duration:}`, with a `note:` when the timeout
  killed it. The body was `LLM::Tool::Exec#call`, which calls it now, so every
  tool that spawns a command runs the same body and `exec` is what they call.

* **tools: a command that outlives its timeout exits with SIGTERM** <br>
  A command that a tool spawns is asked to exit with SIGTERM when it outlives
  its `timeout:`, and when the run is interrupted, where the timeout sent
  SIGKILL. The request goes through
  [`LLM::Command#graceful_exit`](https://r.uby.dev/api-docs/llm.rb/LLM/Command.html#graceful_exit-instance_method),
  so a command closes what it opened and writes what it holds before it is
  dropped, and the `note:` the timeout adds still says it was killed.

* **tools: each tool that spawns a command has a `max_bytes` of its own** <br>
  A tool that includes `LLM::Tool::Utils::Process` has a `max_bytes` class
  method now, and the streams it captures are capped at that number, 75,000
  bytes by default. It was one knob on `LLM::Tool::Exec`, which capped every
  tool, so the tool that reads more of a command's output than another is
  configured on its own class instead.

* **tools: add a `unix-make` tool** <br>
  [`LLM::Tool::Unix::Make`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Make.html)
  (`unix-make`) runs a build, the loop an agent runs after it edits a file:
  run it, read the failure, fix it, run it again. It spawns `make` without a
  shell and builds the argv itself as
  `[-C dir] [-f makefile] [-j n] [-n] [-k] [-V var] [NAME=value...] [targets...]`,
  so the directory, the targets, the variables and the flags arrive as
  parameters. It takes an optional `directory:`, which must exist,
  `makefile:`, `jobs:`, which must be a positive integer, `dry_run:` (`-n`),
  `keep_going:` (`-k`), `variable:` (`-V`, bmake) and `assignments:` of
  `NAME=value` pairs, and it rejects an assignment that is not a pair and a
  target that begins with `-`. Every flag but `-V` is shared by BSD make and
  GNU make, and `timeout:` is 120 seconds by default.

* **tools: add a `unix-cat` tool** <br>
  [`LLM::Tool::Unix::Cat`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Cat.html)
  (`unix-cat`) concatenates files and returns what they hold, and it prints
  more than one file in a single call where `read-file` reads one and returns
  its lines beside a line number. It builds the argv as
  `[-E] [-n] [-s] [-T] [-v] -- paths...`, so `number:` numbers the lines,
  `squeeze_blank:` collapses a run of empty lines, and `show_ends:`,
  `show_tabs:` and `show_nonprinting:` make trailing whitespace, hard tabs
  and control characters visible. It requires one or more `paths:`, and it
  rejects an empty path and a path of `-`, which would read the standard
  input and block.

* **tools: add a `unix-cc` tool** <br>
  [`LLM::Tool::Unix::Cc`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Cc.html)
  (`unix-cc`) compiles C and C++ sources, and a failed compile reaches the
  model with the stderr and the exit status that explain it. It builds the argv as
  `[stage] [-std=] [-O] [-g] [-Wall] [-D...] [-I...] [-o out] sources... [-L...] [-l...]`,
  with the sources before the libraries, because the linker reads them in
  the order it is given them. `stage:` is one of `link`, `object`,
  `assembly`, `preprocess` or `syntax`, which is `-fsyntax-only` and builds
  nothing, and the schema enumerates the stages and the optimization levels
  (`0` to `3`, `s`, `fast`, `g`). It requires one or more `sources:`, and it
  takes an optional `output:`, `standard:`, `optimize:`, `debug:` (`-g`),
  `warnings:` (`-Wall`), `defines:` (`-D`), `include_directories:` (`-I`),
  `library_directories:` (`-L`) and `libraries:` (`-l`). The variables that
  add to the include path, the library path and the temporary directory are
  forwarded when they are set, and `timeout:` is 120 seconds by default.

* **tools: add a `unix-nm` tool** <br>
  [`LLM::Tool::Unix::Nm`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Nm.html)
  (`unix-nm`) lists the symbols of an object file, an archive or an
  executable, the tool that reads the failure a link produced: `undefined:`
  (`-u`) lists the symbols an archive refers to and does not define, and
  `external:` (`-g`) the ones an object exports. It takes one or more
  `paths:` after `--`, and `demangle:` (`-C`), `dynamic:` (`-D`), `file_name:`
  (`-A`), `size:` (`-S`), `numeric_sort:` (`-n`) and `portable:` (`-P`, one
  symbol per line). It rejects a path of `-`, which would read the standard
  input and block.

* **tools: add a `unix-pwd` tool** <br>
  [`LLM::Tool::Unix::Pwd`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Pwd.html)
  (`unix-pwd`) prints the working directory of the command, `-L` by default
  for the logical path and `-P` when `physical: true` for the physical one,
  with every symbolic link resolved. It forwards `$PWD` when it is set,
  because `-L` reads it and a spawned command inherits `$PATH` and nothing
  else; without it `pwd -L` falls back to the physical path. `LLM::Tool::Pwd`
  is untouched and still returns `Dir.getwd`, and it keeps the name `pwd`,
  where this tool takes `unix-pwd`, so the registry, which keys on the name,
  keeps the two apart.

* **tools: add a `freebsd-truss` tool** <br>
  [`LLM::Tool::FreeBSD::Truss`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/FreeBSD/Truss.html)
  (`freebsd-truss`) traces the system calls of a process on FreeBSD. It
  traces a `command:` with its `arguments:`, or a running `pid:`, and one of
  the two is required while the two together are rejected. `follow:` (`-f`)
  traces the children the process forks, `count:` (`-c`) swaps the individual
  calls for a summary of the time, count and errors of each, `signals:` (`-S`
  when it is false) shows the signals, `output:` (`-o`) writes the trace to a
  file, and `string_size:` (`-s`) is how many characters a string is shown
  with. The trace arrives through stderr unless `output:` names a file.

* **tools: add a `freebsd-procstat` tool** <br>
  [`LLM::Tool::FreeBSD::ProcStat`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/FreeBSD/ProcStat.html)
  (`freebsd-procstat`) displays detailed process information on FreeBSD, the
  question that follows a process nobody can explain: the binary behind a pid,
  the command line it was started with, the environment it inherited, the
  files it holds open, the memory it maps and the threads it runs. `command:`
  picks the subcommand, one of fifteen - `basic` by default, then `args`, `binary`,
  `environment`, `credentials`, `files`, `signals`, `tsignals`, `threads`,
  `vm`, `rlimit`, `rusage`, `auxv`, `cpuset` and `kstack` - and it goes out as
  the flag that stands for it, so `files` is `procstat -f` and `credentials`
  is `procstat -s`. It asks about the processes in `pids:`, or about every
  process with `all:` (`-a`), where the two are mutually exclusive and one of
  them is required. `headers:` keeps the header line of the table, where `-h`
  turns it off, and three flags belong to one subcommand each: `capabilities:`
  (`-C`) needs `files`, `signal_numbers:` (`-n`) needs `signals` or
  `tsignals`, and `per_thread:` (`-H`) needs `rusage`, so one of them is
  rejected on any other subcommand rather than ignored. `timeout:` is 30
  seconds by default.

* **tools: the `freebsd-procstat` tool's file is `proc-stat.rb`** <br>
  The file that defines `LLM::Tool::FreeBSD::ProcStat` is
  `lib/llm/tools/freebsd/proc-stat.rb` now, where it was `proc_stat.rb`, so the
  tool is required with `require "llm/tools/freebsd/proc-stat"`. The class and
  its behavior are unchanged.

* **tools: add a `freebsd-sockstat` tool** <br>
  [`LLM::Tool::FreeBSD::SockStat`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/FreeBSD/SockStat.html)
  (`freebsd-sockstat`) lists the open sockets of FreeBSD, the question behind
  a port that is already in use: the user, the command and the pid behind each
  socket, with the local and the foreign address beside them. `family:` (`-4`,
  `-6`, `-u`) picks Internet, IPv6 or local, and `state:` (`-l`, `-c`) picks the
  sockets that listen or the ones that are connected, so the schema offers one
  of each rather than two flags that contradict. `ports:` and `protocols:` are
  joined into the comma-separated list `-p` and `-P` take, where a port is `22`
  or `8000-8100` and a protocol is a name, and a `jail:` that is empty or
  begins with `-` is rejected. `numeric:` (`-n`) leaves a uid as a number,
  `wide:` (`-w`) sizes the columns to the widest value, `quiet:` (`-q`) drops
  the header line and `verbose:` (`-v`) prints more, and `timeout:` is 10
  seconds by default.

* **tools: add a `freebsd-pkg-install` tool** <br>
  [`LLM::Tool::FreeBSD::PkgInstall`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/FreeBSD/PkgInstall.html)
  (`freebsd-pkg-install`) installs packages on FreeBSD with `pkg install`. It
  always passes `-y`: the command asks for confirmation before it changes
  anything, and a spawned process has nobody to confirm the prompt, so a run
  without it would sit until the timeout killed it. `dry_run:` (`-n`) prints
  the work-list of the packages to install, upgrade and delete, in dependency
  order, without touching the system. It requires one or more `packages:`,
  and it takes an optional `no_repo_update:` (`-U`), `quiet:` (`-q`),
  `force:` (`-f`), `no_scripts:` (`-I`), `local_only:` (`-l`), `automatic:`
  (`-A`), `autoremove:` (`--autoremove`), `repositories:` (`-r`) and
  `match:` of `exact`, `case-sensitive`, `glob`, `case-insensitive` or
  `regex`, which the schema enumerates. `timeout:` is 300 seconds by
  default.

* **tools: add a `freebsd-pkg-search` tool** <br>
  [`LLM::Tool::FreeBSD::PkgSearch`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/FreeBSD/PkgSearch.html)
  (`freebsd-pkg-search`) searches the package repositories of FreeBSD, the
  question that comes before `freebsd-pkg-install`: a model told to add a
  program does not know which package provides it, and `field:` of
  `comment-description` finds a package by what it does where the default
  finds one by what it is called. It takes a `pattern:` and an optional
  `field:`, `match:` of
  `regex`, `exact` or `glob`, `case_sensitive:`, `modifiers:` (`-Q`),
  `repositories:` (`-r`), `quiet:` (`-q`) and `no_repo_update:` (`-U`), and
  `raw:` (`-R`) with `raw_format:` of `yaml`, `json`, `json-compact` or
  `ucl` prints the whole manifest of each match. A `raw_format:` that is
  given without `raw:` is rejected.

* **tools: add an `unix-ls` tool** <br>
  [`LLM::Tool::Unix::Ls`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Ls.html)
  (`unix-ls`) spawns `ls` without a shell and returns the listing as its
  stdout. It builds the argv as
  `[-A] [-F] [-R] [-a] [-d] [-h] [-i] [-l] [sort] [-r] [-- paths...]`, so
  `all:` (`-a`), `almost_all:` (`-A`), `long:` (`-l`), `human:` (`-h`),
  `classify:` (`-F`), `inode:` (`-i`), `recursive:` (`-R`), `directory:`
  (`-d`) and `reverse:` (`-r`) are flags, and `sort:` is one of `name`,
  `time` (`-t`), `size` (`-S`), `natural` (`-v`) or `none` (`-f`). It takes an
  optional `paths:`, which follows `--` so a path that begins with `-` stays a
  path, and it rejects an empty path. There is no `-1` and no color, because
  the output of a spawned command is never a terminal, and `timeout:` is 5
  seconds by default.
  [`LLM::Tool::Ls`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Ls.html)
  is untouched and still returns its listing from `Dir.glob`, and it keeps the
  name `ls`, where this tool takes `unix-ls`, so the registry, which keys on
  the name, keeps the two apart.

* **tools: add a `freebsd-sh` tool** <br>
  [`LLM::Tool::FreeBSD::Sh`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/FreeBSD/Sh.html)
  (`freebsd-sh`) runs a script as one operand of `sh -c`, so the pipes, the
  chaining and the directory changes of `cd /usr/src && make -j8` happen inside
  one process, where the per-command tools need a tool per step. It takes the
  `script:` to run, which is required and is rejected when it is empty, when
  it is only whitespace, and when it holds a NUL character, and it takes the
  flags of sh(1) in front of it: `errexit:` (`-e`), `nounset:` (`-u`),
  `noexec:` (`-n`), `xtrace:` (`-x`), `verbose:` (`-v`), `noclobber:` (`-C`),
  `noglob:` (`-f`), `physical:` (`-P`) and `pipefail:` (`-o pipefail`).
  Nothing is re-parsed on the way in, so the quoting is the script's business,
  and `timeout:` is 30 seconds by default, so a loop that would not end is
  killed instead of hanging the run.

* **tools: add a `unix-uname` tool** <br>
  [`LLM::Tool::Unix::Uname`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Uname.html)
  (`unix-uname`) reports what the system is. It sticks to the POSIX options,
  which mean the same thing on FreeBSD, Linux and macOS: `kernel:` (`-s`),
  `nodename:` (`-n`), `release:` (`-r`), `version:` (`-v`), `machine:` (`-m`)
  and `all:` (`-a`), which is the five of them at once and is passed on its
  own. The FreeBSD extensions are left out on purpose - `-p` and `-i` mean
  something else on Linux, and `-K`, `-U` and `-b` exist on FreeBSD alone - so
  a model that needs them asks a FreeBSD tool. With no flag at all `uname`
  prints the kernel name, and `timeout:` is 5 seconds by default.

* **tools: add a `unix-grep` tool** <br>
  [`LLM::Tool::Unix::Grep`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Grep.html)
  (`unix-grep`) searches files for a pattern, the POSIX fallback for `rg`,
  which needs a port where the base system ships `grep`. It sticks to the
  options POSIX defines, and the extensions are absent: no recursion, no
  context, no `-o`, no `-w` and no `--include`, so a recursive search is
  `unix-find` beside this tool. It requires a `pattern:`, which goes to `-e`
  so a pattern that
  begins with `-` stays a pattern, and one or more `paths:`, which follow
  `--`, and it rejects an empty pattern, which would select every line. The
  flags are `extended:` (`-E`), `fixed:` (`-F`), `ignore_case:` (`-i`),
  `invert:` (`-v`), `line:` (`-x`), `count:` (`-c`), `files_with_matches:`
  (`-l`), `line_number:` (`-n`), `byte_offset:` (`-b`), `quiet:` (`-q`) and
  `no_messages:` (`-s`), and `extended:` with `fixed:` together is rejected.
  A search that matches nothing exits `1`, which comes back as `ok: false`
  with an empty stdout rather than an error. `timeout:` is 30 seconds by
  default.

* **tools: add a `git-grep` tool** <br>
  [`LLM::Tool::Git::Grep`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git/Grep.html)
  (`git-grep`) searches the files git knows about for a `pattern:`, which is
  the required parameter. It builds the argv as
  `git -C <cwd> grep <flags> -e <pattern> [<rev>] [-- pathspec...]`, so
  `rev:` names the tree or commit to search, where the default is the working
  tree, and `paths:` are the pathspecs that narrow the search. `cached:`
  (`--cached`) searches the index instead of the working tree, `untracked:`
  (`--untracked`) searches the files git does not track yet, and the flags are
  `ignore_case:` (`-i`), `word:` (`-w`), `invert:` (`-v`), `extended:`
  (`-E`), `fixed:` (`-F`), `line_number:` (`-n`), `files_with_matches:`
  (`-l`) and `count:` (`-c`). An empty pattern, `extended:` with `fixed:`,
  `cached:` with `untracked:`, and an empty path are rejected.

* **tools: the git tools pass `-C` only when `cwd:` is given** <br>
  Each tool that
  [`LLM::Tool::Git`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Git.html)
  provides builds `git [-C <cwd>] ...` now, where it passed `-C Dir.getwd`
  on every call, so a call that names no `cwd:` runs git in the working
  directory of the command rather than in the working directory of this
  process.

* **tools: `rg` searches the working directory of the command** <br>
  [`LLM::Tool::Rg`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Rg.html)
  leaves `path:` out of the argument vector when it is not given, where it
  passed `Dir.getwd`, so the search runs in the working directory of the
  command.

* **tools: `unix-find` walks the working directory of the command** <br>
  [`LLM::Tool::Unix::Find`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Find.html)
  leaves `path:` out of the argument vector when it is not given, where it
  passed `Dir.getwd`, so the walk starts in the working directory of the
  command.

* **tools: `bundle` forwards `$BUNDLE_GEMFILE` and nothing else** <br>
  [`LLM::Tool::Bundle`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Bundle.html)
  sets `BUNDLE_GEMFILE` only when the variable is set, where it set it to
  `<cwd>/Gemfile` when it was not, so bundle looks for a `Gemfile` in the
  directory the command runs in.

### ORM

* **orm: add `#compactor` and `#compactor_options` to the Sequel plugins** <br>
  A record that uses `plugin :llm` or `plugin :agent` responds to
  [`#compactor`](https://r.uby.dev/api-docs/llm.rb/LLM/Sequel/Plugin/InstanceMethods.html#compactor-instance_method)
  and
  [`#compactor_options`](https://r.uby.dev/api-docs/llm.rb/LLM/Sequel/Plugin/InstanceMethods.html#compactor_options-instance_method)
  now, as a record that `acts_as_llm` or `acts_as_agent` does. Both read the
  compactor and its options from the record's runtime, an `LLM::Context` for
  `plugin :llm` and an `LLM::Agent` for `plugin :agent`.

* **orm: add `#intercept` and `#intercept_options` to the Sequel plugins** <br>
  A record that uses `plugin :llm` or `plugin :agent` responds to
  [`#intercept`](https://r.uby.dev/api-docs/llm.rb/LLM/Sequel/Plugin/InstanceMethods.html#intercept-instance_method)
  and
  [`#intercept_options`](https://r.uby.dev/api-docs/llm.rb/LLM/Sequel/Plugin/InstanceMethods.html#intercept_options-instance_method)
  now, as a record that `acts_as_llm` or `acts_as_agent` does. Both read the
  intercept and its options from the record's runtime, an `LLM::Context` for
  `plugin :llm` and an `LLM::Agent` for `plugin :agent`.

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
