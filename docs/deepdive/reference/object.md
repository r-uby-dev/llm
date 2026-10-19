
## LLM::Object

### Introduction

#### Overview

[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
is the hash-like object that llm.rb uses everywhere structured data
flows through the runtime. Response bodies, tool arguments, schema
results, usage and cost data, and function parameters all come back
as [`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
instances. It is similar in spirit to OpenStruct,
and it was introduced after OpenStruct became a bundled gem rather
than a default gem in Ruby 3.5.

#### How it works

When you want to read a value from an
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html),
use either method-style or bracket access. Keys are indifferent, so
strings and symbols work interchangeably:

```ruby
obj = LLM::Object.from(city: "Paris", temperature: 15.0)

obj.city          # => "Paris"
obj["city"]       # => "Paris"
obj[:city]        # => "Paris"
obj[:temperature] # => 15.0
```

Nested hashes and arrays are converted recursively, so deep chains
read naturally:

```ruby
obj = LLM::Object.from(person: {name: "John"})
obj.person.name   # => "John"
obj.person.class  # => LLM::Object
```

#### Why would I use it?

Most of the time you do not construct
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
instances yourself. They come back from `talk`, `ask`, `embed`, and
every other call that returns structured data. Knowing how they
behave lets you read response fields, pass tool arguments, and
inspect usage without reaching for `to_h` on every line.

#### Notes

An
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
is enumerable and supports the usual Hash operations: `keys`,
`values`, `key?`, `fetch`, `dig`, `slice`, `merge`, `merge!`,
`delete`, `size`, and `empty?`. Use `to_h` for a plain Hash and
`to_hash` for one with symbol keys. A missing key returns `nil`
rather than raising. Because it subclasses `BasicObject`, `to_json`
is defined explicitly and serializes through the configured JSON
adapter via
[`LLM.json.dump`](https://r.uby.dev/api-docs/llm.rb/LLM.html#json-class_method).

The adapter is `LLM::JSONAdapter::JSON`, the standard library, by
default. Set `LLM.json = :oj` to use a faster backend when the matching
gem is present; every adapter normalizes strings to valid UTF-8 before
it serializes, so the choice affects speed rather than behavior.

### Reading and writing

#### Overview

Beyond simple reads,
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
supports assignment, mutation, and iteration, so you can treat it
like a Hash in place.

#### How it works

Assign values with method or bracket syntax, mutate in place, and
iterate like a Hash:

```ruby
obj = LLM::Object.from({})

obj.city = "Paris"       # method-style write
obj["country"] = "France"

obj.key?(:city)          # => true
obj.keys                 # => ["city", "country"]
obj.merge!(population: 2_100_000)

obj.each { |key, value| puts "#{key}: #{value}" }
obj.transform_values!(&:upcase) if obj.any?
```

#### Why would I use it?

Tool implementations receive their arguments as an
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html)
and often build a result Hash from them. Merging defaults, deleting
optional keys, and transforming values in place keeps that code
concise without converting back and forth between Hash and
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html).

#### Notes

`merge` returns a new
[`LLM::Object`](https://r.uby.dev/api-docs/llm.rb/LLM/Object.html);
`merge!` mutates in place.
Assignment always stores the key as a string internally, which is
why string and symbol lookups both work. Equality compares against
anything that responds to `to_h`.
