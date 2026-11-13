# frozen_string_literal: true

require "setup"
require "llm/tools/unix"

RSpec.describe LLM::Tool::Unix::Cc do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a compile takes" do
      expect(params.properties.keys).to contain_exactly(
        "sources", "output", "stage", "standard", "optimize", "debug", "warnings",
        "defines", "include_directories", "library_directories", "libraries",
        "timeout", "max_bytes"
      )
    end

    it "marks the sources param as required" do
      expect(params.properties[:sources]).to be_required
    end

    it "defines debug and warnings as booleans" do
      expect(params.properties[:debug]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:warnings]).to be_a(LLM::Schema::Boolean)
    end

    it "constrains the stage and the optimization level to their values" do
      expect(params.properties[:stage].enum).to eq(described_class::STAGES.keys)
      expect(params.properties[:optimize].enum).to eq(described_class::OPTIMIZATIONS)
    end

    it "defaults the stage to link and the timeout to 120 seconds" do
      expect(params.properties[:stage].default).to eq("link")
      expect(params.properties[:timeout].default).to eq(120)
    end
  end

  describe "#call" do
    it "compiles and links the source with no flags" do
      tool.call(sources: ["foo.c"])
      expect(tool).to have_received(:exec).with(
        command: "cc",
        arguments: ["foo.c"],
        env: an_instance_of(::Hash),
        timeout: 120,
        max_bytes: described_class.max_bytes
      )
    end

    it "passes the sources in the order given" do
      tool.call(sources: %w[foo.c bar.c])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: %w[foo.c bar.c]))
    end

    it "passes the output as -o" do
      tool.call(sources: ["foo.c"], output: "foo")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-o", "foo", "foo.c"]))
    end

    it "passes the object stage as -c" do
      tool.call(sources: ["foo.c"], stage: "object")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-c", "foo.c"]))
    end

    it "passes the assembly stage as -S" do
      tool.call(sources: ["foo.c"], stage: "assembly")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-S", "foo.c"]))
    end

    it "passes the preprocess stage as -E" do
      tool.call(sources: ["foo.c"], stage: "preprocess")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-E", "foo.c"]))
    end

    it "passes the syntax stage as -fsyntax-only" do
      tool.call(sources: ["foo.c"], stage: "syntax")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-fsyntax-only", "foo.c"]))
    end

    it "passes the standard as -std=" do
      tool.call(sources: ["foo.c"], standard: "c17")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-std=c17", "foo.c"]))
    end

    it "passes the optimization level as -O" do
      tool.call(sources: ["foo.c"], optimize: "2")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-O2", "foo.c"]))
    end

    it "passes debug as -g" do
      tool.call(sources: ["foo.c"], debug: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-g", "foo.c"]))
    end

    it "passes warnings as -Wall" do
      tool.call(sources: ["foo.c"], warnings: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-Wall", "foo.c"]))
    end

    it "passes the defines as -D" do
      tool.call(sources: ["foo.c"], defines: ["FOO", "BAR=1"])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-DFOO", "-DBAR=1", "foo.c"]))
    end

    it "passes the include directories as -I" do
      tool.call(sources: ["foo.c"], include_directories: ["include", "src"])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-Iinclude", "-Isrc", "foo.c"]))
    end

    it "passes the libraries after the sources" do
      tool.call(sources: ["foo.c"], libraries: %w[m pthread], library_directories: ["/opt/lib"])
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["foo.c", "-L/opt/lib", "-lm", "-lpthread"]))
    end

    it "passes every argument in a fixed order" do
      arguments = [
        "-c", "-std=c17", "-O2", "-g", "-Wall", "-DFOO=1", "-Iinclude",
        "-o", "foo.o", "foo.c", "-L/opt/lib", "-lm"
      ]
      tool.call(
        sources: ["foo.c"], output: "foo.o", stage: "object", standard: "c17",
        optimize: "2", debug: true, warnings: true, defines: ["FOO=1"],
        include_directories: ["include"], library_directories: ["/opt/lib"],
        libraries: ["m"]
      )
      expect(tool).to have_received(:exec).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(sources: ["foo.c"], timeout: 600)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 600))
    end

    it "passes the max bytes" do
      tool.call(sources: ["foo.c"], max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is when cc succeeded" do
      expect(tool.call(sources: ["foo.c"])).to eq(result)
    end

    it "returns the result as it is when cc failed" do
      stderr = "foo.c:1:1: error: unknown type name 'foo'\n"
      allow(tool).to receive(:exec).and_return({ok: false, stdout: "", stderr:})
      expect(tool.call(sources: ["foo.c"])).to eq({ok: false, stdout: "", stderr:})
    end
  end

  describe "environment" do
    before do
      described_class::ENVIRONMENT.each do |key|
        allow(ENV).to receive(:[]).with(key).and_return(nil)
      end
    end

    it "passes an empty environment when none of the variables are set" do
      tool.call(sources: ["foo.c"])
      expect(tool).to have_received(:exec).with(hash_including(env: {}))
    end

    it "forwards the variables that add to the include and library path" do
      allow(ENV).to receive(:[]).with("CPATH").and_return("/opt/include")
      allow(ENV).to receive(:[]).with("LIBRARY_PATH").and_return("/opt/lib")
      tool.call(sources: ["foo.c"])
      expect(tool).to have_received(:exec)
        .with(hash_including(env: {"CPATH" => "/opt/include", "LIBRARY_PATH" => "/opt/lib"}))
    end
  end

  describe "validation" do
    it "raises when there are no sources" do
      expect { tool.call(sources: []) }
        .to raise_error("sources must be one or more files")
    end

    it "raises when a source is empty" do
      expect { tool.call(sources: [""]) }
        .to raise_error("a source can't be empty")
    end

    it "raises when a source begins with a dash" do
      expect { tool.call(sources: ["-o"]) }
        .to raise_error("a source can't begin with '-'")
    end

    it "raises when the output begins with a dash" do
      expect { tool.call(sources: ["foo.c"], output: "-o") }
        .to raise_error("output must be a path that doesn't begin with '-'")
    end

    it "raises when the stage is unknown" do
      expect { tool.call(sources: ["foo.c"], stage: "linker") }
        .to raise_error("stage must be one of: link, object, assembly, preprocess, syntax")
    end

    it "raises when the standard is not a standard name" do
      expect { tool.call(sources: ["foo.c"], standard: "17") }
        .to raise_error("standard must be a C or C++ standard name (eg c17, gnu11, c++20)")
    end

    it "raises when the optimization level is unknown" do
      expect { tool.call(sources: ["foo.c"], optimize: "9") }
        .to raise_error("optimize must be one of: 0, 1, 2, 3, s, fast, g")
    end

    it "raises when a define is empty" do
      expect { tool.call(sources: ["foo.c"], defines: [""]) }
        .to raise_error("a define, an include directory, a library directory and " \
                        "a library can't be empty")
    end

    it "raises when an include directory is empty" do
      expect { tool.call(sources: ["foo.c"], include_directories: [""]) }
        .to raise_error("a define, an include directory, a library directory and " \
                        "a library can't be empty")
    end

    it "raises when a library is empty" do
      expect { tool.call(sources: ["foo.c"], libraries: [""]) }
        .to raise_error("a define, an include directory, a library directory and " \
                        "a library can't be empty")
    end

    it "raises when a define is not a NAME or a NAME=value pair" do
      expect { tool.call(sources: ["foo.c"], defines: ["FOO BAR=1"]) }
        .to raise_error("a define must be a NAME or a NAME=value pair")
    end
  end
end
