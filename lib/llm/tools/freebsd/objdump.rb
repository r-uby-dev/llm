# frozen_string_literal: true

require_relative "../freebsd"

class LLM::Tool::FreeBSD
  ##
  # The {LLM::Tool::FreeBSD::ObjDump LLM::Tool::FreeBSD::ObjDump}
  # class implements a tool that dumps what an object file, an
  # archive or an executable holds.
  #
  # It is the tool that reads a binary from the outside, one
  # question per call: `section_headers:` (`-h`) lists the
  # sections and where each one sits, `syms:` (`-t`) the symbol
  # table, `dynamic_syms:` (`-T`) the one the dynamic loader
  # reads, `reloc:` (`-r`) and `dynamic_reloc:` (`-R`) the
  # relocations, `full_contents:` (`-s`) the bytes of each
  # section, `file_headers:` (`-f`) and `private_headers:`
  # (`-p`) the headers a loader reads, and `disassemble:` (`-d`)
  # the code, one instruction per line with the address beside
  # it. The commands combine, so `-h -t` is one call, and
  # `all_headers:` (`-x`) is the six of `-a`, `-f`, `-p`, `-r`,
  # `-h` and `-t` together.
  #
  # `symbols:` (`--disassemble-symbols`) narrows a disassembly to
  # the functions it names and `disassemble_all:` (`-D`)
  # disassembles the sections `-d` leaves alone. `sections:`
  # (`-j`) narrows every command to the sections it names,
  # `demangle:` (`-C`) turns a mangled name into the one the
  # source used, and `dwarf_frames:` (`--dwarf=frames`) prints
  # the debug frame table.
  #
  # The rest shapes a disassembly: `line_numbers:` (`-l`) and
  # `source:` (`-S`) add the file and the line an instruction came
  # from and imply `-d` by themselves, while `no_show_raw_insn:`,
  # `no_leading_addr:`, `disassemble_zeroes:` (`-z`) and
  # `symbolize_operands:` change what a line looks like, `syntax:`
  # picks AT&T or Intel, and `triple:` and `cpu:` disassemble a
  # file that was built for another machine. One of the five, or
  # a `-d`, `-D` or `symbols:`, is required before the others are
  # accepted. `start_address:` and `stop_address:` bound the
  # range, and they are the one pair that also narrows `-r` and
  # `-t`.
  #
  # It is a FreeBSD tool for the reason `truss` is one: the
  # `objdump` FreeBSD ships is LLVM's, the `objdump` on a Linux box
  # is GNU's, and the two do not take the same arguments.
  # `--disassemble-symbols`, `--no-leading-addr`,
  # `--symbolize-operands`, `--dwarf` and `--triple` are LLVM's
  # spellings, and GNU spells a disassembly of one symbol
  # `--disassemble=`. A few commands and options are left out on
  # purpose: `-u` prints unwind info for COFF and Mach-O files
  # only, `--show-lma`, `--adjust-vma`, `--print-imm-hex`,
  # `--debug-vars`, `--prefix`, `--build-id`, `--debuginfod`,
  # `--offloading`, `--raw-clang-ast` and `--fault-map-section`
  # answer a narrower question than the ones above, `-w` does
  # nothing, and `-v` and `--help` print the version and the usage
  # rather than a dump.
  #
  # A path of `-` is rejected because objdump reads the standard
  # input for it and would block, and a path that begins with `-`
  # is rejected because it would be read as a flag. The result of
  # {LLM::Tool::Utils::Process#exec} is returned as it is.
  class ObjDump < self
    ##
    # The commands objdump takes, keyed by the name a model asks
    # for. At least one of them is required.
    # @return [Array<String>]
    COMMANDS = %w[
      all_headers archive_headers disassemble disassemble_all dwarf_frames
      dynamic_reloc dynamic_syms file_headers full_contents private_headers
      reloc section_headers syms
    ].freeze

    ##
    # The commands `--all-headers` is equivalent to.
    # @return [Array<Symbol>]
    ALL_HEADERS = %i[
      archive_headers file_headers private_headers reloc section_headers syms
    ].freeze

    ##
    # The disassembler syntax `-M` picks on x86, keyed by the
    # name a model asks for.
    # @return [Array<String>]
    SYNTAX = %w[att intel].freeze

    ##
    # An address, as `--start-address` and `--stop-address`
    # take one.
    # @return [Regexp]
    ADDRESS = /\A(0x)?[0-9a-fA-F]+\z/

    name "freebsd-objdump"
    description "Dump the headers, the symbols, the relocations or the disassembly of an object file with objdump (FreeBSD)\n" \
                "This command (objdump) is spawned without a shell"
    parameter :paths, Array[String], "the object files, archives or executables to read"
    parameter :disassemble, Boolean, "disassemble the executable sections (-d)"
    parameter :disassemble_all, Boolean, "disassemble every section, not only the executable ones (-D)"
    parameter :symbols, Array[String], "disassemble only these symbols, one --disassemble-symbols each"
    parameter :all_headers, Boolean, "print every header, the six of -a, -f, -p, -r, -h and -t (-x)"
    parameter :archive_headers, Boolean, "print the headers of an archive's members (-a)"
    parameter :file_headers, Boolean, "print the overall file header (-f)"
    parameter :private_headers, Boolean, "print the format-specific file headers (-p)"
    parameter :section_headers, Boolean, "print a summary of the headers of each section (-h)"
    parameter :syms, Boolean, "print the symbol table (-t)"
    parameter :dynamic_syms, Boolean, "print the dynamic symbol table (-T)"
    parameter :reloc, Boolean, "print the relocation entries (-r)"
    parameter :dynamic_reloc, Boolean, "print the dynamic relocation entries (-R)"
    parameter :full_contents, Boolean, "print the contents of each section (-s)"
    parameter :dwarf_frames, Boolean, "print the .debug_frame section (--dwarf=frames)"
    parameter :sections, Array[String], "read only these sections, one -j each (-j)"
    parameter :demangle, Boolean, "demangle the symbol names (-C)"
    parameter :line_numbers, Boolean, "print the source line of each instruction, implies -d (-l)"
    parameter :source, Boolean, "interleave the source with the disassembly, implies -d (-S)"
    parameter :no_show_raw_insn, Boolean, "leave the bytes of an instruction out (--no-show-raw-insn)"
    parameter :no_leading_addr, Boolean, "leave the leading address out (--no-leading-addr)"
    parameter :disassemble_zeroes, Boolean, "disassemble blocks of zeroes instead of skipping them (-z)"
    parameter :symbolize_operands, Boolean, "print a branch target as a label (--symbolize-operands)"
    parameter :syntax, Enum[*SYNTAX], "the syntax to disassemble x86 with, att or intel (-M)"
    parameter :triple, String, "disassemble for this target triple (--triple)"
    parameter :cpu, String, "disassemble for this CPU (--mcpu)"
    parameter :start_address, String, "start the dump at this address, eg 0x401000 (--start-address)"
    parameter :stop_address, String, "stop the dump before this address, eg 0x401100 (--stop-address)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    required %i[paths]
    defaults disassemble: false, disassemble_all: false, symbols: [], all_headers: false,
             archive_headers: false, file_headers: false, private_headers: false,
             section_headers: false, syms: false, dynamic_syms: false, reloc: false,
             dynamic_reloc: false, full_contents: false, dwarf_frames: false,
             sections: [], demangle: false, line_numbers: false, source: false,
             no_show_raw_insn: false, no_leading_addr: false, disassemble_zeroes: false,
             symbolize_operands: false, syntax: nil, triple: nil, cpu: nil,
             start_address: nil, stop_address: nil, timeout: 30,
             max_bytes: -> { max_bytes }

    ##
    # @param [Array<String>] paths
    #  The object files, archives or executables to read
    # @param [Boolean] disassemble
    #  Disassemble the executable sections
    # @param [Boolean] disassemble_all
    #  Disassemble every section
    # @param [Array<String>] symbols
    #  Disassemble only these symbols
    # @param [Boolean] all_headers
    #  Print every header that `-a`, `-f`, `-p`, `-r`, `-h`
    #  and `-t` print
    # @param [Boolean] archive_headers
    #  Print the headers of an archive's members
    # @param [Boolean] file_headers
    #  Print the overall file header
    # @param [Boolean] private_headers
    #  Print the format-specific file headers
    # @param [Boolean] section_headers
    #  Print a summary of the headers of each section
    # @param [Boolean] syms
    #  Print the symbol table
    # @param [Boolean] dynamic_syms
    #  Print the dynamic symbol table
    # @param [Boolean] reloc
    #  Print the relocation entries
    # @param [Boolean] dynamic_reloc
    #  Print the dynamic relocation entries
    # @param [Boolean] full_contents
    #  Print the contents of each section
    # @param [Boolean] dwarf_frames
    #  Print the debug frame table
    # @param [Array<String>] sections
    #  Read only these sections
    # @param [Boolean] demangle
    #  Demangle the symbol names
    # @param [Boolean] line_numbers
    #  Print the source line of each instruction
    # @param [Boolean] source
    #  Interleave the source with the disassembly
    # @param [Boolean] no_show_raw_insn
    #  Leave the bytes of an instruction out
    # @param [Boolean] no_leading_addr
    #  Leave the leading address out
    # @param [Boolean] disassemble_zeroes
    #  Disassemble blocks of zeroes instead of skipping
    #  them
    # @param [Boolean] symbolize_operands
    #  Print a branch target as a label
    # @param [String, nil] syntax
    #  The syntax to disassemble x86 with, one of {SYNTAX}
    # @param [String, nil] triple
    #  Disassemble for this target triple
    # @param [String, nil] cpu
    #  Disassemble for this CPU
    # @param [String, nil] start_address
    #  Start the dump at this address
    # @param [String, nil] stop_address
    #  Stop the dump before this address
    # @param [Integer] timeout
    #  The maximum allowed time for objdump to run, in seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(paths:, disassemble: false, disassemble_all: false, symbols: [], all_headers: false,
             archive_headers: false, file_headers: false, private_headers: false,
             section_headers: false, syms: false, dynamic_syms: false, reloc: false,
             dynamic_reloc: false, full_contents: false, dwarf_frames: false,
             sections: [], demangle: false, line_numbers: false, source: false,
             no_show_raw_insn: false, no_leading_addr: false, disassemble_zeroes: false,
             symbolize_operands: false, syntax: nil, triple: nil, cpu: nil,
             start_address: nil, stop_address: nil, timeout: 30,
             max_bytes: self.class.max_bytes)
      validate!(
        paths:, disassemble:, disassemble_all:, symbols:, all_headers:, archive_headers:,
        file_headers:, private_headers:, section_headers:, syms:, dynamic_syms:, reloc:,
        dynamic_reloc:, full_contents:, dwarf_frames:, sections:, line_numbers:, source:,
        no_show_raw_insn:, no_leading_addr:, disassemble_zeroes:, symbolize_operands:,
        syntax:, triple:, cpu:, start_address:, stop_address:
      )
      exec(
        command: "objdump",
        arguments: arguments(
          paths:, disassemble:, disassemble_all:, symbols:, all_headers:, archive_headers:,
          file_headers:, private_headers:, section_headers:, syms:, dynamic_syms:, reloc:,
          dynamic_reloc:, full_contents:, dwarf_frames:, sections:, demangle:, line_numbers:,
          source:, no_show_raw_insn:, no_leading_addr:, disassemble_zeroes:,
          symbolize_operands:, syntax:, triple:, cpu:, start_address:, stop_address:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector objdump is given: the flags in
    # the order the page lists them, then the long options, then
    # the paths. A symbol and a section each get a flag of their
    # own, because a demangled symbol and a Mach-O section name
    # may both hold the comma that separates the values of one.
    # @return [Array<String>]
    def arguments(paths:, disassemble:, disassemble_all:, symbols:, all_headers:,
                  archive_headers:, file_headers:, private_headers:, section_headers:,
                  syms:, dynamic_syms:, reloc:, dynamic_reloc:, full_contents:,
                  dwarf_frames:, sections:, demangle:, line_numbers:, source:,
                  no_show_raw_insn:, no_leading_addr:, disassemble_zeroes:,
                  symbolize_operands:, syntax:, triple:, cpu:, start_address:,
                  stop_address:)
      [
        *(archive_headers ? ["-a"] : []),
        *(demangle ? ["-C"] : []),
        *(disassemble ? ["-d"] : []),
        *(disassemble_all ? ["-D"] : []),
        *Array(symbols).map { "--disassemble-symbols=#{_1}" },
        *(file_headers ? ["-f"] : []),
        *(section_headers ? ["-h"] : []),
        *Array(sections).flat_map { ["-j", _1.to_s] },
        *(line_numbers ? ["-l"] : []),
        *(syntax ? ["-M", syntax.to_s] : []),
        *(private_headers ? ["-p"] : []),
        *(reloc ? ["-r"] : []),
        *(dynamic_reloc ? ["-R"] : []),
        *(full_contents ? ["-s"] : []),
        *(source ? ["-S"] : []),
        *(syms ? ["-t"] : []),
        *(dynamic_syms ? ["-T"] : []),
        *(all_headers ? ["-x"] : []),
        *(disassemble_zeroes ? ["-z"] : []),
        *(dwarf_frames ? ["--dwarf=frames"] : []),
        *(cpu ? ["--mcpu=#{cpu}"] : []),
        *(no_leading_addr ? ["--no-leading-addr"] : []),
        *(no_show_raw_insn ? ["--no-show-raw-insn"] : []),
        *(start_address ? ["--start-address=#{start_address}"] : []),
        *(stop_address ? ["--stop-address=#{stop_address}"] : []),
        *(symbolize_operands ? ["--symbolize-operands"] : []),
        *(triple ? ["--triple=#{triple}"] : []),
        *Array(paths).map(&:to_s)
      ]
    end

    ##
    # @api private
    def validate!(paths:, disassemble:, disassemble_all:, symbols:, all_headers:,
                  archive_headers:, file_headers:, private_headers:, section_headers:,
                  syms:, dynamic_syms:, reloc:, dynamic_reloc:, full_contents:,
                  dwarf_frames:, sections:, line_numbers:, source:, no_show_raw_insn:,
                  no_leading_addr:, disassemble_zeroes:, symbolize_operands:, syntax:,
                  triple:, cpu:, start_address:, stop_address:)
      commands = {
        all_headers:, archive_headers:, disassemble:, disassemble_all:, dwarf_frames:,
        dynamic_reloc:, dynamic_syms:, file_headers:, full_contents:, private_headers:,
        reloc:, section_headers:, syms:
      }
      ##
      # A disassembly is what -d, -D and symbols: ask for, and -l
      # and -S ask for one of their own. The options below are the
      # ones that answer nothing without one.
      disassembling = disassemble || disassemble_all || !Array(symbols).empty? ||
                      line_numbers || source
      shaped = {
        no_show_raw_insn:, no_leading_addr:, disassemble_zeroes:,
        symbolize_operands:, syntax:, triple:, cpu:
      }.find { |_, given| given }
      if Array(paths).empty?
        raise RuntimeError, "paths must be one or more files"
      elsif Array(paths).any? { _1.to_s.empty? }
        raise RuntimeError, "a path can't be empty"
      elsif Array(paths).any? { _1.to_s == "-" }
        raise RuntimeError, "a path of '-' reads the standard input and is not supported"
      elsif Array(paths).any? { _1.to_s.start_with?("-") }
        raise RuntimeError, "a path can't begin with '-'"
      elsif commands.none? { |_, given| given } && !disassembling
        raise RuntimeError, "a command is required, one of: #{COMMANDS.join(', ')}"
      elsif all_headers && ALL_HEADERS.any? { |name| commands[name] }
        raise RuntimeError, "all_headers is -a, -f, -p, -r, -h and -t together, " \
                            "so it can't be combined with one of them"
      elsif !Array(symbols).empty? && disassemble_all
        raise RuntimeError, "symbols and disassemble_all are mutually exclusive"
      elsif Array(symbols).any? { _1.to_s.empty? }
        raise RuntimeError, "a symbol can't be empty"
      elsif Array(sections).any? { _1.to_s.empty? }
        raise RuntimeError, "a section can't be empty"
      elsif Array(sections).any? { _1.to_s.start_with?("-") }
        raise RuntimeError, "a section can't begin with '-'"
      elsif syntax && !SYNTAX.include?(syntax.to_s)
        raise RuntimeError, "syntax must be one of: #{SYNTAX.join(', ')}"
      elsif start_address && !ADDRESS.match?(start_address.to_s)
        raise RuntimeError, "start_address must be an address, eg 0x401000"
      elsif stop_address && !ADDRESS.match?(stop_address.to_s)
        raise RuntimeError, "stop_address must be an address, eg 0x401100"
      elsif !disassembling && shaped
        raise RuntimeError, "#{shaped.first} needs a disassembly, eg disassemble, disassemble_all or symbols"
      end
    end
  end
end
