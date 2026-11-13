# frozen_string_literal: true

require_relative "../bsd"

class LLM::Tool::BSD
  ##
  # The {LLM::Tool::BSD::SockStat LLM::Tool::BSD::SockStat}
  # class implements a tool that lists the open sockets.
  #
  # It is the question behind a port that is already in
  # use, a server that listens where it should not, and a
  # process that holds a socket nobody expected it to
  # hold: `sockstat` prints the user, the command and the
  # pid behind every socket, with the local and the
  # foreign address beside them. `-l` narrows the list to
  # the sockets that listen and `-c` to the ones that are
  # connected, which is the difference between a service
  # that waits for a client and one that has a client.
  #
  # A socket is Internet - IPv4 or IPv6 - or local, and
  # `-4`, `-6` and `-u` pick one of the three; with no
  # flag it lists all of them. The list is narrowed by
  # port too, where `-p` takes a comma separated list of
  # ports and ranges, by protocol through `-P`, and by
  # jail through `-j`, which asks a jail what it holds
  # rather than what the host holds on its behalf.
  #
  # `-n` leaves a uid as a number, where the default
  # resolves it to a name, `-w` sizes the columns to the
  # widest value instead of a fixed width, `-q` drops the
  # header line, and `-v` prints more.
  #
  # It is a FreeBSD tool. Linux lists its sockets with
  # `ss` and macOS with `lsof -i`, and neither of them
  # takes these arguments.
  class SockStat < self
    ##
    # The address families a socket is listed by, keyed by
    # the name a model asks for.
    # @return [Hash{String => Array<String>}]
    FAMILIES = {
      "inet" => ["-4"],
      "inet6" => ["-6"],
      "local" => ["-u"]
    }.freeze

    ##
    # The states a socket is listed by, keyed by the name a
    # model asks for. A socket that neither listens nor is
    # connected is listed by neither.
    # @return [Hash{String => String}]
    STATES = {
      "listening" => "-l",
      "connected" => "-c"
    }.freeze

    ##
    # A port, or a range of ports, as `-p` takes one.
    # @return [Regexp]
    PORT = /\A\d+(-\d+)?\z/

    ##
    # A protocol name, as protocols(5) defines one.
    # @return [Regexp]
    PROTOCOL = /\A[a-zA-Z0-9]+\z/

    name "sockstat"
    description "List the open sockets with sockstat (FreeBSD)\n" \
                "This command (sockstat) is spawned without a shell"
    parameter :family, Enum[*FAMILIES.keys], "list only sockets of this address family (-4, -6, -u)"
    parameter :state, Enum[*STATES.keys], "list only the sockets that are listening or connected (-l, -c)"
    parameter :ports, Array[String], "list only sockets on these ports or ranges, eg 22 or 8000-8100 (-p)"
    parameter :protocols, Array[String], "list only sockets of these protocols, eg tcp or udp (-P)"
    parameter :jail, String, "list only sockets of this jail, by id or name (-j)"
    parameter :numeric, Boolean, "leave a uid as a number instead of a user name (-n)"
    parameter :wide, Boolean, "size the columns automatically (-w)"
    parameter :quiet, Boolean, "do not print the header line (-q)"
    parameter :verbose, Boolean, "print more (-v)"
    parameter :timeout, Integer, "the maximum allowed time for the command to run (in seconds)"
    parameter :max_bytes, Integer, "max number of bytes to emit"
    defaults family: nil, state: nil, ports: [], protocols: [], jail: nil,
             numeric: false, wide: false, quiet: false, verbose: false,
             timeout: 10, max_bytes: -> { max_bytes }

    ##
    # @param [String, nil] family
    #  List only sockets of this address family, one of
    #  {FAMILIES}
    # @param [String, nil] state
    #  List only the sockets that are listening or
    #  connected, one of {STATES}
    # @param [Array<String>] ports
    #  One or more ports, or ranges of ports, eg `22` or
    #  `8000-8100`
    # @param [Array<String>] protocols
    #  One or more protocol names, eg `tcp` or `udp`
    # @param [String, nil] jail
    #  List only the sockets of this jail, by id or name
    # @param [Boolean] numeric
    #  Leave a uid as a number instead of a user name
    # @param [Boolean] wide
    #  Size the columns automatically
    # @param [Boolean] quiet
    #  Do not print the header line
    # @param [Boolean] verbose
    #  Print more
    # @param [Integer] timeout
    #  The maximum allowed time for sockstat to run, in
    #  seconds
    # @param [Integer] max_bytes
    #  The max number of bytes to emit
    # @return [Hash]
    def call(family: nil, state: nil, ports: [], protocols: [], jail: nil,
             numeric: false, wide: false, quiet: false, verbose: false,
             timeout: 10, max_bytes: self.class.max_bytes)
      validate!(family:, state:, ports:, protocols:, jail:)
      exec(
        command: "sockstat",
        arguments: arguments(
          family:, state:, ports:, protocols:, jail:, numeric:, wide:, quiet:, verbose:
        ),
        timeout:,
        max_bytes:
      )
    end

    private

    ##
    # Builds the argument vector sockstat is given: the
    # family, the state, the jail, the ports, the
    # protocols, then the flags that shape the output.
    # @return [Array<String>]
    def arguments(family:, state:, ports:, protocols:, jail:, numeric:, wide:, quiet:, verbose:)
      [
        *FAMILIES.fetch(family.to_s, []),
        *(state ? [STATES.fetch(state.to_s)] : []),
        *(jail ? ["-j", jail] : []),
        *(Array(ports).empty? ? [] : ["-p", Array(ports).join(",")]),
        *(Array(protocols).empty? ? [] : ["-P", Array(protocols).join(",")]),
        *(numeric ? ["-n"] : []),
        *(wide ? ["-w"] : []),
        *(quiet ? ["-q"] : []),
        *(verbose ? ["-v"] : [])
      ]
    end

    ##
    # @api private
    def validate!(family:, state:, ports:, protocols:, jail:)
      if family && !FAMILIES.key?(family.to_s)
        raise RuntimeError, "family must be one of: #{FAMILIES.keys.join(', ')}"
      elsif state && !STATES.key?(state.to_s)
        raise RuntimeError, "state must be one of: #{STATES.keys.join(', ')}"
      elsif Array(ports).any? { |port| !PORT.match?(port.to_s) }
        raise RuntimeError, "a port must be a number or a range, eg 22 or 8000-8100"
      elsif Array(protocols).any? { |protocol| !PROTOCOL.match?(protocol.to_s) }
        raise RuntimeError, "a protocol must be a name, eg tcp or udp"
      elsif jail && jail.to_s.empty?
        raise RuntimeError, "jail can't be empty"
      elsif jail && jail.to_s.start_with?("-")
        raise RuntimeError, "a jail can't begin with '-'"
      end
    end
  end
end
