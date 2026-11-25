# frozen_string_literal: true

require "setup"
require "llm/tools/freebsd"

RSpec.describe LLM::Tool::FreeBSD::ObjDump do
  let(:tool) { described_class.new }
  let(:result) { {ok: true, stdout: "SYMBOL TABLE:\n", stderr: ""} }

  before do
    allow(tool).to receive(:exec).and_return(result)
  end

  describe ".function" do
    let(:params) { described_class.function.params }

    it "defines every param a dump takes" do
      expect(params.properties.keys).to contain_exactly(
        "paths", "disassemble", "disassemble_all", "symbols", "all_headers",
        "archive_headers", "file_headers", "private_headers", "section_headers",
        "syms", "dynamic_syms", "reloc", "dynamic_reloc", "full_contents",
        "dwarf_frames", "sections", "demangle", "line_numbers", "source",
        "no_show_raw_insn", "no_leading_addr", "disassemble_zeroes",
        "symbolize_operands", "syntax", "triple", "cpu", "start_address",
        "stop_address", "timeout", "max_bytes"
      )
    end

    it "defines the commands as booleans" do
      expect(params.properties[:disassemble]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:disassemble_all]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:all_headers]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:syms]).to be_a(LLM::Schema::Boolean)
      expect(params.properties[:dwarf_frames]).to be_a(LLM::Schema::Boolean)
    end

    it "defines the syntax as a string of att or intel" do
      expect(params.properties[:syntax]).to be_a(LLM::Schema::String)
      expect(params.properties[:syntax].enum).to eq(%w[att intel])
    end

    it "defaults the timeout to 30 seconds" do
      expect(params.properties[:timeout].default).to eq(30)
    end
  end

  describe "#call" do
    it "dumps the symbol table with -t" do
      tool.call(paths: ["foo.o"], syms: true)
      expect(tool).to have_received(:exec).with(
        command: "objdump",
        arguments: ["-t", "foo.o"],
        timeout: 30,
        max_bytes: described_class.max_bytes
      )
    end

    it "passes the archive headers as -a" do
      tool.call(paths: ["libfoo.a"], archive_headers: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-a", "libfoo.a"]))
    end

    it "passes the disassembly as -d" do
      tool.call(paths: ["../../bin/ls"], disassemble: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-d", "../../bin/ls"]))
    end

    it "passes the full disassembly as -D" do
      tool.call(paths: ["foo.o"], disassemble_all: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-D", "foo.o"]))
    end

    it "passes the file headers as -f" do
      tool.call(paths: ["foo.o"], file_headers: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-f", "foo.o"]))
    end

    it "passes the section headers as -h" do
      tool.call(paths: ["foo.o"], section_headers: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-h", "foo.o"]))
    end

    it "passes the private headers as -p" do
      tool.call(paths: ["foo.o"], private_headers: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-p", "foo.o"]))
    end

    it "passes the relocations as -r" do
      tool.call(paths: ["foo.o"], reloc: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-r", "foo.o"]))
    end

    it "passes the dynamic relocations as -R" do
      tool.call(paths: ["libfoo.so"], dynamic_reloc: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-R", "libfoo.so"]))
    end

    it "passes the contents of each section as -s" do
      tool.call(paths: ["foo.o"], full_contents: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-s", "foo.o"]))
    end

    it "passes the dynamic symbols as -T" do
      tool.call(paths: ["libfoo.so"], dynamic_syms: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-T", "libfoo.so"]))
    end

    it "passes every header as -x" do
      tool.call(paths: ["foo.o"], all_headers: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-x", "foo.o"]))
    end

    it "passes the debug frame table as --dwarf=frames" do
      tool.call(paths: ["foo.o"], dwarf_frames: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["--dwarf=frames", "foo.o"]))
    end

    it "passes one --disassemble-symbols for each symbol" do
      tool.call(paths: ["foo.o"], symbols: %w[main usage])
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: ["--disassemble-symbols=main", "--disassemble-symbols=usage", "foo.o"])
      )
    end

    it "passes one -j for each section" do
      tool.call(paths: ["foo.o"], sections: %w[.text .data], section_headers: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-h", "-j", ".text", "-j", ".data", "foo.o"]))
    end

    it "passes the demangling as -C" do
      tool.call(paths: ["foo.o"], syms: true, demangle: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-C", "-t", "foo.o"]))
    end

    it "passes the line numbers as -l, which implies a disassembly" do
      tool.call(paths: ["foo.o"], line_numbers: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-l", "foo.o"]))
    end

    it "passes the source as -S, which implies a disassembly" do
      tool.call(paths: ["foo.o"], source: true)
      expect(tool).to have_received(:exec).with(hash_including(arguments: ["-S", "foo.o"]))
    end

    it "passes the syntax as -M" do
      tool.call(paths: ["foo.o"], disassemble: true, syntax: "intel")
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-d", "-M", "intel", "foo.o"]))
    end

    it "passes the zeroes as -z" do
      tool.call(paths: ["foo.o"], disassemble: true, disassemble_zeroes: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-d", "-z", "foo.o"]))
    end

    it "passes the raw instruction flag as --no-show-raw-insn" do
      tool.call(paths: ["foo.o"], disassemble: true, no_show_raw_insn: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-d", "--no-show-raw-insn", "foo.o"]))
    end

    it "passes the leading address flag as --no-leading-addr" do
      tool.call(paths: ["foo.o"], disassemble: true, no_leading_addr: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-d", "--no-leading-addr", "foo.o"]))
    end

    it "passes the symbolized operands as --symbolize-operands" do
      tool.call(paths: ["foo.o"], disassemble: true, symbolize_operands: true)
      expect(tool).to have_received(:exec)
        .with(hash_including(arguments: ["-d", "--symbolize-operands", "foo.o"]))
    end

    it "passes the start and the stop address" do
      tool.call(paths: ["foo.o"], disassemble: true, start_address: "0x401000", stop_address: "0x401100")
      expect(tool).to have_received(:exec).with(
        hash_including(arguments: ["-d", "--start-address=0x401000", "--stop-address=0x401100", "foo.o"])
      )
    end

    it "passes the target triple and the cpu" do
      tool.call(paths: ["foo.o"], disassemble: true, triple: "x86_64-unknown-freebsd14.0", cpu: "znver4")
      expect(tool).to have_received(:exec).with(
        hash_including(
          arguments: ["-d", "--mcpu=znver4", "--triple=x86_64-unknown-freebsd14.0", "foo.o"]
        )
      )
    end

    it "passes every argument in a fixed order" do
      arguments = [
        "-a", "-C", "-d", "-f", "-h", "-j", ".text", "-l", "-M", "intel", "-p",
        "-r", "-R", "-s", "-S", "-t", "-T", "-z", "--dwarf=frames", "--mcpu=znver4",
        "--no-leading-addr", "--no-show-raw-insn", "--start-address=0x401000",
        "--stop-address=0x401100", "--symbolize-operands",
        "--triple=x86_64-unknown-freebsd14.0", "foo.o"
      ]
      tool.call(
        paths: ["foo.o"], archive_headers: true, demangle: true, disassemble: true,
        file_headers: true, section_headers: true, sections: [".text"], line_numbers: true,
        syntax: "intel", private_headers: true, reloc: true, dynamic_reloc: true,
        full_contents: true, source: true, syms: true, dynamic_syms: true,
        disassemble_zeroes: true, dwarf_frames: true, cpu: "znver4", no_leading_addr: true,
        no_show_raw_insn: true, start_address: "0x401000", stop_address: "0x401100",
        symbolize_operands: true, triple: "x86_64-unknown-freebsd14.0"
      )
      expect(tool).to have_received(:exec).with(hash_including(arguments:))
    end

    it "forwards the timeout" do
      tool.call(paths: ["foo.o"], syms: true, timeout: 5)
      expect(tool).to have_received(:exec).with(hash_including(timeout: 5))
    end

    it "passes the max bytes" do
      tool.call(paths: ["foo.o"], syms: true, max_bytes: 100)
      expect(tool).to have_received(:exec).with(hash_including(max_bytes: 100))
    end

    it "returns the result as it is" do
      expect(tool.call(paths: ["foo.o"], syms: true)).to eq(result)
    end
  end

  describe "validation" do
    it "raises when no command is given" do
      expect { tool.call(paths: ["foo.o"]) }
        .to raise_error(/a command is required/)
    end

    it "raises when all_headers is combined with a command it implies" do
      expect { tool.call(paths: ["foo.o"], all_headers: true, syms: true) }
        .to raise_error(/all_headers is -a, -f, -p, -r, -h and -t together/)
    end

    it "raises when symbols is combined with disassemble_all" do
      expect { tool.call(paths: ["foo.o"], symbols: ["main"], disassemble_all: true) }
        .to raise_error("symbols and disassemble_all are mutually exclusive")
    end

    it "raises when a flag that shapes a disassembly has none" do
      expect { tool.call(paths: ["foo.o"], syms: true, no_leading_addr: true) }
        .to raise_error("no_leading_addr needs a disassembly, eg disassemble, disassemble_all or symbols")
    end

    it "raises when the syntax is neither att nor intel" do
      expect { tool.call(paths: ["foo.o"], disassemble: true, syntax: "gas") }
        .to raise_error("syntax must be one of: att, intel")
    end

    it "raises when the start address is not an address" do
      expect { tool.call(paths: ["foo.o"], disassemble: true, start_address: "_start") }
        .to raise_error("start_address must be an address, eg 0x401000")
    end

    it "raises when the stop address is not an address" do
      expect { tool.call(paths: ["foo.o"], disassemble: true, stop_address: "0x40zz") }
        .to raise_error("stop_address must be an address, eg 0x401100")
    end

    it "raises when a symbol is empty" do
      expect { tool.call(paths: ["foo.o"], symbols: [""]) }
        .to raise_error("a symbol can't be empty")
    end

    it "raises when a section is empty" do
      expect { tool.call(paths: ["foo.o"], sections: [""], section_headers: true) }
        .to raise_error("a section can't be empty")
    end

    it "raises when a section begins with a dash" do
      expect { tool.call(paths: ["foo.o"], sections: ["-h"], section_headers: true) }
        .to raise_error("a section can't begin with '-'")
    end

    it "raises when no path is given" do
      expect { tool.call(paths: [], syms: true) }
        .to raise_error("paths must be one or more files")
    end

    it "raises when a path is empty" do
      expect { tool.call(paths: [""], syms: true) }
        .to raise_error("a path can't be empty")
    end

    it "raises when a path is the standard input" do
      expect { tool.call(paths: ["-"], syms: true) }
        .to raise_error("a path of '-' reads the standard input and is not supported")
    end

    it "raises when a path begins with a dash" do
      expect { tool.call(paths: ["-foo.o"], syms: true) }
        .to raise_error("a path can't begin with '-'")
    end
  end
end
