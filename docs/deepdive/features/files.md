
## Files

### Introduction

#### Overview

Some providers keep files you upload, and let a later request refer to
one by id instead of resending its bytes. The Files API is how a file
is uploaded, listed, fetched, downloaded, and deleted, and a file id is
then passed to an endpoint that reads it.

#### How it works

Call the file methods on a provider that implements them. `create`
uploads a file and returns its record, `get` reads a record, `download`
returns the bytes, `all` lists the files, and `delete` removes one:

```ruby
require "llm"

llm  = LLM.openai(key: ENV["KEY"])
ctx  = LLM::Context.new(llm)

file = llm.files.create(file: "/books/goodread.pdf")
ctx.talk ["Tell me about this PDF", file]

llm.files.all                         # every uploaded file
llm.files.get(file: file.id)          # one file's record
llm.files.download(file: file.id)     # its bytes, under #file
llm.files.delete(file: file.id)
```

`create` takes a path, an `LLM::File`, or a `File` object, and a
`purpose:` that tells the provider what the file is for. An uploaded
file carries its id, so it can be passed to a turn directly, as above,
and a response from `download` exposes the bytes through `#file`.

#### Why would I use it?

A file that a provider stores can be reused across requests without
being uploaded each time. That keeps a large document or an image out
of the request body, and it is how OpenAI's vector stores, and the
assistants that read them, get their content.

#### Notes

Anthropic, Google, and OpenAI implement the Files API, and so do the
providers built on OpenAI's - Moonshot and Alibaba among them, which
inherit it. DeepSeek implements the Files API too, scoped to images that
a chat request references by `file_id`. A provider that has no Files API
of its own, such as Mistral or xAI, raises `NotImplementedError`.
`download` is OpenAI-only, so the OpenAI-compatible providers inherit
that too. A file id belongs to the provider that minted it: a file id minted by
another provider is passed through as-is, and fails when DeepSeek's API
tries to resolve it.
