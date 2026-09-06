<p align="center">
  <a href="https://r.uby.dev/llm/">
    <img
      src="https://github.com/r-uby-dev/llm.rb/raw/main/rubydev.svg"
      width="400"
      height="200"
      border="0"
      alt="a r.uby.dev project"
    >
  </a>
</p>

> A [r.uby.dev](https://r.uby.dev) project.

## Welcome

### Introduction

#### Overview

Welcome to the llm.rb deepdive. This document provides a series
of guides that explains how to use the llm.rb runtime so you can
build advanced AI applications on CRuby. This page provides a guide
index and explains the pattern that all guides follow.

An optimized version exists
at [https://r.uby.dev/llm/deepdive](https://r.uby.dev/llm/deepdive)
that is both easier to read and navigate.

#### How it works

Each topic file follows a consistent four-part pattern:
`#### Overview` introduces the concept, `#### How it works` shows
code, `#### Why would I use it?` explains the use case, and
`#### Notes` covers caveats and edge cases.

#### Why would I use it?

The deepdive documents everything there is to know about llm.rb.
It includes the fundamnetals, advanced patterns, configuration
options, ORM support, protocol support, and edge cases. It is
useful when you need to go beyond the basics.

#### Notes

The deepdive is a living document. Sections are added as new
features land. The [README.md](https://github.com/r-uby-dev/llm#readme)
is the best place to start if you are new to llm.rb.

---

## Fundamentals

- [Providers](deepdive/fundamentals/providers.md)
- [Agents](deepdive/fundamentals/agents.md)
- [Tools](deepdive/fundamentals/tools.md)
- [Stream](deepdive/fundamentals/stream.md)
- [Schema](deepdive/fundamentals/schema.md)
- [Skills](deepdive/fundamentals/skills.md)

## Protocols

- [MCP](deepdive/protocols/mcp.md)
- [A2A](deepdive/protocols/a2a.md)

## Features

- [Built-in tools](deepdive/features/builtin_tools.md)
- [Concurrency](deepdive/features/concurrency.md)
- [Embeddings](deepdive/features/embeddings.md)
- [Database](deepdive/features/database.md)
- [Console](deepdive/features/repl.md)

## Advanced

- [Context](deepdive/advanced/context.md)
- [Compaction](deepdive/advanced/compaction.md)
- [Cancellation](deepdive/advanced/cancellation.md)
- [Transports](deepdive/advanced/transports.md)
- [Transformer](deepdive/advanced/transformer.md)
- [Guard](deepdive/advanced/guard.md)

## Media

- [Images](deepdive/media/images.md)
- [Audio](deepdive/media/audio.md)
- [OCR](deepdive/media/ocr.md)

## Reference

- [LLM::Object](deepdive/reference/object.md)
- [LLM::Cost](deepdive/reference/cost.md)
- [Tracer](deepdive/reference/tracer.md)
- [Model registry](deepdive/reference/model_registry.md)