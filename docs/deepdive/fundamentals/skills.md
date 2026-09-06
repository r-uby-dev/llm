
## Skills

### Introduction

#### Overview

A skill turns a markdown file into a callable tool. Write the
instructions in markdown, declare what tools the subagent needs
in the frontmatter, and register the file with the parent agent.
When the model calls the skill, the runtime spawns a fresh subagent
with those instructions as its system prompt and only the tools
you gave it. The subagent runs one turn and returns. Then it is
discarded.

#### How it works

A parent agent works with zero or more skill files. Each skill
is registered as a tool the model can call.

When the model calls a skill, a subagent is created with:

- Its own system prompt: the body of the SKILL.md file
- Limited tools: only what you declare in the frontmatter
- Context awareness: the last 8 user/assistant messages from the
  parent (tool calls stripped)

The subagent runs one turn and returns. The parent sees the result
like any other tool return.

```ruby
require "llm"

llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm, skills: ["./skills/git-log", "./skills/deploy"])
agent.talk "Review the recent commits, then deploy if everything looks clean"
```

#### Why would I use it?

Because each skill spawns a fresh subagent with constrained tools,
you can build a clear hierarchy. The parent supervises, decides
which skill to call, inspects the result, and can iterate or
compose multiple skills.

Each skill is focused. A changelog skill gets `git-log` and
`write-file`, not the shell. A deploy skill gets deployment tools,
not file readers.

Skills are stateless. Every call is independent. No carryover, no
cross-contamination.

#### Notes

Skills can also be attached to the console session without modifying
the agent:

```ruby
llm = LLM.deepseek(key: ENV["KEY"])
agent = LLM::Agent.new(llm)
agent.console(skills: [__dir__])
```

### Frontmatter

#### Overview

The frontmatter at the top of a skill file controls how the
subagent sees itself and what it can reach. It sets the skill's
name (which becomes the tool name), a description (which the
model reads to decide when to call it), and a tool list (which
limits what the subagent can do). Leave the tools out and the
subagent has none. Set them to `all` and it has everything.

Skills can be loaded from a directory containing a `SKILL.md` file
or from a direct path to a markdown file.
[`LLM::Skill.load`](https://r.uby.dev/api-docs/llm.rb/LLM/Skill.html#load-class_method)
accepts either form.

#### How it works

The frontmatter is parsed from the YAML block at the top of the
file. The markdown body that follows becomes the subagent's system
prompt. The `tools` field resolves at load time: named tools are
looked up in the registry, `inherit` copies from the parent context,
and `all` grabs everything available. The `tools` field accepts four
forms:

| Field | Purpose |
|---|---|
| `name` | A short identifier for the skill. Used as the tool name. |
| `description` | Explains to the model what the skill does. Used as the tool description. |
| `tools` | Controls what the subagent can call. See below. |

| Value | Behavior |
|---|---|
| `inherit` | Copies the parent agent's tools, excluding other skills. |
| `all` or `*` | Every tool in the global registry. |
| `['name1', 'name2']` | Only the named tools. Raises an error if not found. |
| (omitted) | No tools at all. |

#### Why would I use it?

The frontmatter is how you configure what a skill can do and what
tools it has access to. `inherit` copies the parent's capabilities
into the skill. An explicit list restricts the subagent to only
the tools it needs.

#### Notes

The fewer tools a subagent has, the less it can wander.
