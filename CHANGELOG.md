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

### Breaking

#### Migration

| Old | New |
|-----|-----|
| `LLM::Tool::Exec.max_bytes(n)`, which capped every tool that spawns a command | `LLM::Tool::Exec.max_bytes(n)` for `exec` alone, and `max_bytes` on the tool class itself, eg `LLM::Tool::Unix::Man.max_bytes(n)` |

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

### LLM::Tool

* **tools: add `LLM::Tool::BSD`** <br>
  [`LLM::Tool::BSD`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/BSD.html)
  is the abstract superclass of the tools that work only on a BSD: a command
  FreeBSD ships and the other systems do not, or a facility that only exists
  there. `truss` is the first - Linux traces a process with `strace` and
  macOS with `dtruss`, and the three do not share an argument vector - and
  `pkg` is the second, so the tools below it are named after the subcommand,
  `pkg-search` before `pkg-install`. It is abstract, so it has no name and it
  is not in `LLM::Tool.registry`.

* **tools: add `LLM::Tool.freebsd`** <br>
  [`LLM::Tool.freebsd`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool.html#freebsd-class_method)
  returns the BSD tools, which are the subclasses of `LLM::Tool::BSD`. It
  requires `llm/tools/bsd` when it is called, unless the namespace is loaded
  already, so the BSD tools are not required up front.

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

* **tools: each tool that spawns a command has a `max_bytes` of its own** <br>
  A tool that includes `LLM::Tool::Utils::Process` has a `max_bytes` class
  method now, and the streams it captures are capped at that number, 75,000
  bytes by default. It was one knob on `LLM::Tool::Exec`, which capped every
  tool, so the tool that reads more of a command's output than another is
  configured on its own class instead.

* **tools: add a `make` tool** <br>
  [`LLM::Tool::Unix::Make`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Make.html)
  (`make`) runs a build, the loop an agent runs after it edits a file: run
  it, read the failure, fix it, run it again. It spawns `make` without a
  shell and builds the argv itself as
  `[-C dir] [-f makefile] [-j n] [-n] [-k] [-V var] [NAME=value...] [targets...]`,
  so the directory, the targets, the variables and the flags arrive as
  parameters. It takes an optional `directory:`, which must exist,
  `makefile:`, `jobs:`, which must be a positive integer, `dry_run:` (`-n`),
  `keep_going:` (`-k`), `variable:` (`-V`, bmake) and `assignments:` of
  `NAME=value` pairs, and it rejects an assignment that is not a pair and a
  target that begins with `-`. Every flag but `-V` is shared by BSD make and
  GNU make, and `timeout:` is 120 seconds by default.

* **tools: add a `cat` tool** <br>
  [`LLM::Tool::Unix::Cat`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Cat.html)
  (`cat`) concatenates files and returns what they hold, and it prints more
  than one file in a single call where `read-file` reads one and returns its
  lines beside a line number. It builds the argv as
  `[-E] [-n] [-s] [-T] [-v] -- paths...`, so `number:` numbers the lines,
  `squeeze_blank:` collapses a run of empty lines, and `show_ends:`,
  `show_tabs:` and `show_nonprinting:` make trailing whitespace, hard tabs
  and control characters visible. It requires one or more `paths:`, and it
  rejects an empty path and a path of `-`, which would read the standard
  input and block.

* **tools: add a `cc` tool** <br>
  [`LLM::Tool::Unix::Cc`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Cc.html)
  (`cc`) compiles C and C++ sources, and a failed compile reaches the model
  with the stderr and the exit status that explain it. It builds the argv as
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

* **tools: add an `nm` tool** <br>
  [`LLM::Tool::Unix::Nm`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Nm.html)
  (`nm`) lists the symbols of an object file, an archive or an executable,
  the tool that reads the failure a link produced: `undefined:` (`-u`) lists
  the symbols an archive refers to and does not define, and `external:`
  (`-g`) the ones an object exports. It takes one or more `paths:` after
  `--`, and `demangle:` (`-C`), `dynamic:` (`-D`), `file_name:` (`-A`),
  `size:` (`-S`), `numeric_sort:` (`-n`) and `portable:` (`-P`, one symbol
  per line). It rejects a path of `-`, which would read the standard input
  and block.

* **tools: add a `pwd` tool** <br>
  [`LLM::Tool::Unix::Pwd`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Pwd.html)
  (`pwd`) prints the working directory of the command, `-L` by default for
  the logical path and `-P` when `physical: true` for the physical one, with
  every symbolic link resolved. It forwards `$PWD` when it is set, because
  `-L` reads it and a spawned command inherits `$PATH` and nothing else;
  without it `pwd -L` falls back to the physical path. `LLM::Tool::Pwd` is
  untouched and still returns `Dir.getwd`, and both tools are named `pwd`,
  so the registry, which keys on the name, resolves `pwd` to this one where
  both are loaded.

* **tools: add a `truss` tool** <br>
  [`LLM::Tool::BSD::Truss`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/BSD/Truss.html)
  (`truss`) traces the system calls of a process on FreeBSD. It traces a
  `command:` with its `arguments:`, or a running `pid:`, and one of the two
  is required while the two together are rejected. `follow:` (`-f`) traces
  the children the process forks, `count:` (`-c`) swaps the individual calls
  for a summary of the time, count and errors of each, `signals:` (`-S` when
  it is false) shows the signals, `output:` (`-o`) writes the trace to a
  file, and `string_size:` (`-s`) is how many characters a string is shown
  with. The trace arrives through stderr unless `output:` names a file.

* **tools: add a `pkg-install` tool** <br>
  [`LLM::Tool::BSD::PkgInstall`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/BSD/PkgInstall.html)
  (`pkg-install`) installs packages on FreeBSD with `pkg install`. It always
  passes `-y`: the command asks for confirmation before it changes anything,
  and a spawned process has nobody to confirm the prompt, so a run without
  it would sit until the timeout killed it. `dry_run:` (`-n`) prints the
  work-list of the packages to install, upgrade and delete, in dependency
  order, without touching the system. It requires one or more `packages:`,
  and it takes an optional `no_repo_update:` (`-U`), `quiet:` (`-q`),
  `force:` (`-f`), `no_scripts:` (`-I`), `local_only:` (`-l`), `automatic:`
  (`-A`), `autoremove:` (`--autoremove`), `repositories:` (`-r`) and
  `match:` of `exact`, `case-sensitive`, `glob`, `case-insensitive` or
  `regex`, which the schema enumerates. `timeout:` is 300 seconds by
  default.

* **tools: add a `pkg-search` tool** <br>
  [`LLM::Tool::BSD::PkgSearch`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/BSD/PkgSearch.html)
  (`pkg-search`) searches the package repositories of FreeBSD, the question
  that comes before `pkg-install`: a model told to add a program does not
  know which package provides it, and `field:` of `comment-description`
  finds a package by what it does where the default finds one by what it is
  called. It takes a `pattern:` and an optional `field:`, `match:` of
  `regex`, `exact` or `glob`, `case_sensitive:`, `modifiers:` (`-Q`),
  `repositories:` (`-r`), `quiet:` (`-q`) and `no_repo_update:` (`-U`), and
  `raw:` (`-R`) with `raw_format:` of `yaml`, `json`, `json-compact` or
  `ucl` prints the whole manifest of each match. A `raw_format:` that is
  given without `raw:` is rejected.

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

* **tools: `find` walks the working directory of the command** <br>
  [`LLM::Tool::Unix::Find`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Unix/Find.html)
  leaves `path:` out of the argument vector when it is not given, where it
  passed `Dir.getwd`, so the walk starts in the working directory of the
  command.

* **tools: `bundle` forwards `$BUNDLE_GEMFILE` and nothing else** <br>
  [`LLM::Tool::Bundle`](https://r.uby.dev/api-docs/llm.rb/LLM/Tool/Bundle.html)
  sets `BUNDLE_GEMFILE` only when the variable is set, where it set it to
  `<cwd>/Gemfile` when it was not, so bundle looks for a `Gemfile` in the
  directory the command runs in.

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
