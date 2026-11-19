# frozen_string_literal: true

##
# Originally known as test-cmd.rb See
# https://github.com/altruby/test-cmd.rb
class LLM::Command
  require "rbconfig"

  ##
  # @api private
  GRACE = 0.5

  ##
  # @api private
  class Pipe < Struct.new(:r, :w)
    def self.pair
      new(*IO.pipe)
    end

    def close
      [r, w].each(&:close)
    end
  end

  ##
  # @param [String] cmd
  #  A command to spawn
  # @param [Array<String>] argv
  #  Zero or more command-line arguments
  # @return [LLM::Command]
  def initialize(cmd, *argv)
    @cmd = cmd
    @argv = argv.dup
    @env = nil
    @cwd = nil
    @status = nil
    @spawned = false
    @stdout = ""
    @stderr = ""
    @enoent = false
    @limit = {stdout: nil, stderr: nil}
    @tail = {stdout: nil, stderr: nil}
  end

  ##
  # @param [Array<String, LLM::Command>] arguments
  #  Command-line arguments. A {LLM::Command} in the
  #  list is spliced into the arguments, so one command
  #  can carry another.
  # @example
  #   jexec = LLM::Command.new("jexec")
  #   ls = LLM::Command.new("ls").arguments("-l", "/")
  #   jexec.arguments(*ls)
  # @return [LLM::Command]
  def arguments(*arguments)
    tap do
      @argv.concat(arguments.flat_map { |arg| LLM::Command === arg ? arg.to_argv : [arg] })
    end
  end
  alias_method :argv, :arguments

  ##
  # Returns the command and its arguments, so that
  # another command can carry them.
  # @example
  #   LLM::Command.new("jexec", "-u", "root", "jail-1")
  #     .arguments(*inner.to_argv)
  # @return [Array<String>]
  def to_argv
    [@cmd, *@argv].map(&:to_s)
  end
  alias_method :to_a, :to_argv

  ##
  # @example
  #   jexec = LLM::Command.new("jexec", "-u", "root", "jail-1")
  #   ls = LLM::Command.new("ls").arguments("-l", "/").chdir("/tmp")
  #   jexec.chain(ls).stdout { print it, "\n" }
  # @param [LLM::Command] command
  # @return [LLM::Command]
  def chain(command)
    tap do
      arguments(*command)
      env(command.env) if command.env
      chdir(command.cwd) if command.cwd
      stdin(command.input) if command.input
      limit(**command.limits)
    end
  end

  ##
  # @param [Hash{String => String}, nil] env
  #  Environment variables to set for the spawned
  #  command
  # @return [Hash{String => String}, nil, LLM::Command]
  def env(env = nil)
    return @env if env.nil?
    tap { (@env ||= {}).merge!(env) }
  end

  ##
  # Sets the working directory of the spawned command.
  # @param [String] dir
  #  The directory to run the command in
  # @return [LLM::Command]
  def chdir(dir)
    tap { @cwd = dir }
  end

  ##
  # Presets the standard input that will be sent to the
  # spawned process. Pass a String, or another
  # {LLM::Command LLM::Command} whose standard output
  # will be used as the standard input.
  # @param [String, LLM::Command] data
  #  The standard input of the spawned process
  # @example
  #   cmd = LLM::Command.new("cat").stdin("hello world")
  #   puts cmd.stdout
  # @return [LLM::Command]
  def stdin(data)
    tap { @stdin = data }
  end

  ##
  # Limits how many bytes of each stream are captured.
  # A stream output beyond the limit is discarded,
  # keeping memory bounded even for a command that
  # streams a lot.
  # @param [Integer, nil] stdout
  #  Max bytes of stdout to read, or nil for unlimited
  # @param [Integer, nil] stderr
  #  Max bytes of stderr to read, or nil for unlimited
  # @return [LLM::Command]
  def limit(stdout: nil, stderr: nil)
    tap { @limit = {stdout:, stderr:} }
  end

  ##
  # Keeps the last n bytes of each stream, rather than the
  # first n that {#limit} keeps.
  # @param [Integer, nil] stdout
  #  Max bytes of stdout to keep, or nil for everything
  # @param [Integer, nil] stderr
  #  Max bytes of stderr to keep, or nil for everything
  # @return [LLM::Command]
  def tail(stdout: nil, stderr: nil)
    tap do
      @tail = {stdout:, stderr:}
      @limit = {stdout: nil, stderr: nil}
    end
  end

  ##
  # Spawns a command
  # @return [LLM::Command]
  def spawn(&blk)
    return self if @spawned
    @in_r = input_pipe
    tap do
      @spawned = true
      @out, @err = Pipe.pair, Pipe.pair
      @pid = Process.spawn(
        envp,
        @cmd,
        *@argv.map(&:to_s),
        options
      )
      @in_r.close unless @in_r.equal?(IO::NULL)
      @out.w.close
      @err.w.close
      lock   = Mutex.new
      @stdout_buf, @stderr_buf = +"", +""
      reader = lambda do |pipe, limit, tail, buf|
        read_limited(pipe, limit, tail, buf) do |chunk|
          blk ? lock.synchronize { blk.call(chunk) } : nil
        end
      end
      @stdout_reader = Thread.new do
        reader.call(@out.r, @limit[:stdout], @tail[:stdout], @stdout_buf)
      end
      @stderr_reader = Thread.new do
        reader.call(@err.r, @limit[:stderr], @tail[:stderr], @stderr_buf)
      end
      @producer = Thread.new do
        begin
          @status = Process.waitpid2(@pid).last
        rescue Errno::ECHILD
          @status = failed_status
        end
        @stdout = settle(@stdout_reader, @out.r, @stdout_buf, @tail[:stdout])
        @stderr = settle(@stderr_reader, @err.r, @stderr_buf, @tail[:stderr])
      end
    end
  rescue Errno::ENOENT => ex
    @stderr = ex.message
    @enoent = true
    ##
    # Close the read end of any input pipe
    # so a pending writer thread does not
    # block forever.
    @in_r.close unless @in_r.equal?(IO::NULL)
    @status = failed_status
    self
  end

  ##
  # @return [Process::Status]
  #  Returns the status of a process
  def status
    spawn
    consume
    @status
  end

  ##
  # @return [Integer]
  #  Returns the process ID of a spawned command
  def pid
    status.pid
  end

  ##
  # @return [Integer]
  #  Returns the exit status of a process
  def exit_status
    status.exitstatus
  end
  alias_method :exitstatus, :exit_status

  ##
  # @group IO

  ##
  # @return [String]
  #  Returns the contents of stdout
  def stdout(&)
    spawn(&)
    consume
    @stdout
  end

  ##
  # @return [String]
  #  Returns the contents of stderr
  def stderr(&)
    spawn(&)
    consume
    @stderr
  end
  # @endgroup

  ##
  # @group Predicates

  ##
  # @return [Boolean]
  #  Returns true when a command exited successfully
  def success?
    status.success?
  end

  ##
  # @return [Boolean]
  #  Returns true when a command has been spawned
  def spawned?
    @spawned
  end

  ##
  # @return [Boolean]
  #  Returns true when a command is running
  def alive?
    @spawned and @status.nil?
  end
  alias_method :running?, :alive?

  ##
  # Waits, up to +seconds+, for the command to
  # be reaped.
  # @return [Boolean]
  #  Returns true when the command has been reaped
  def wait(seconds)
    deadline = LLM.now + seconds
    while alive?
      action = (LLM.now > deadline ? :break : :continue)
      case action
      when :continue then sleep(0.01)
      when :break then return false
      end
    end
    true
  end

  ##
  # Sends SIGKILL to a running command
  # @raise [SystemCallError]
  # @return [void]
  def hard_exit!
    alive? ? signal("SIGKILL") : nil
  end

  ##
  # Sends SIGTERM to a running command
  # @raise [SystemCallError]
  # @return [void]
  def graceful_exit
    alive? ? signal("SIGTERM") : nil
  end

  ##
  # @param [Integer, String] sig
  # @raise [SystemCallError]
  # @return [void]
  def signal(sig)
    noterm = Gem.win_platform?
    (noterm and sig.to_s == "SIGTERM") ? Process.kill("SIGKILL", signal_pid) :
                                         Process.kill(sig, signal_pid)
  rescue Errno::ESRCH
    ##
    # The process is already gone, which is what the
    # signal was for. It is a race a caller cannot
    # avoid: the command exits between the decision to
    # stop it and the signal itself, and "stop it" is
    # not an error when it has already stopped.
    nil
  end

  ##
  # @return [Integer].
  def signal_pid
    Gem.win_platform? ? @pid : -@pid
  end

  ##
  # @return [Boolean]
  #  Returns true when a command can't be found
  def command_not_found?
    spawn
    consume
    @enoent
  end
  alias_method :not_found?, :command_not_found?
  # @endgroup

  ##
  # @group Callbacks

  ##
  # @yieldparam [LLM::Command] cmd
  #  Yields an instance of {LLM::Command LLM::Command}
  # @example
  #   LLM::Command.new("ruby", "-e", "exit 0").success do
  #     print "ok pid #{_1.pid}", "\n"
  #   end
  # @return [LLM::Command]
  def success
    tap do
      spawn
      consume
      status.success? ? yield(self) : nil
    end
  end

  ##
  # @yieldparam [LLM::Command] cmd
  #  Yields an instance of {LLM::Command LLM::Command}
  # @example
  #   LLM::Command.new("ruby", "-e", "exit 1").failure do
  #     print "fail pid #{_1.pid}", "\n"
  #   end
  # @return [LLM::Command]
  def failure
    tap do
      spawn
      consume
      status.success? ? nil : yield(self)
    end
  end
  # @endgroup

  protected

  ##
  # @return [String, nil]
  attr_reader :cwd

  ##
  # @return [String, LLM::Command, nil]
  def input
    @stdin
  end

  ##
  # @return [Hash]
  def limits
    @limit
  end

  private

  ##
  # Builds the environment passed to Process.spawn. The
  # spawned process receives only the variables set
  # with #env: every inherited variable is
  # cleared, so an empty @env spawns with an empty
  # environment.
  # @return [Hash{String => String}]
  def envp
    if @env.nil?
      ##
      # Inherit the parent's environment
      ENV.to_h
    else
      ##
      # Clear all environment variables except those
      # that are set by `@env`. Always inherit ${PATH}.
      envp = ENV.except("PATH")
                .each_key
                .to_h { |key| [key, nil] }
      envp.merge!(@env)
    end
  end

  ##
  # The options the command is spawned with.
  # @return [Hash]
  def options
    opts = {in: @in_r, out: @out.w, err: @err.w, chdir: @cwd}.compact
    Gem.win_platform? ? opts : opts.merge(pgroup: true)
  end

  ##
  # Waits for a reader to finish, and
  # stops waiting once the command it
  # belongs to is over.
  # @param [Thread] reader
  # @param [IO] io
  # @return [String]
  def settle(reader, io, buf, tail = nil)
    if reader.join(GRACE).nil?
      io.closed? ? nil : io.close
      reader.kill
    end
    tail ? text(buf) : buf
  end

  ##
  # Reads up to +max+ bytes from a stream, then drains
  # the remainder so a child writing more than the
  # limit does not block on a full pipe. When +max+ is
  # nil the entire stream is read.
  #
  # With +tail+ the last that many bytes are kept
  # instead of the first +max+: the stream is still
  # read to the end, and the buffer is cut back after
  # every chunk, so a command that prints for an hour
  # is held in the memory of its tail rather than in
  # the memory of its output.
  #
  # @param [IO] io
  # @param [Integer, nil] max
  # @param [Integer, nil] tail
  # @return [String]
  def read_limited(io, max, tail = nil, buf = +"")
    remaining, ex = [max, nil]
    loop do
      chunk = io.readpartial(16_384)
      begin
        block_given? ? yield(chunk) : nil
      rescue
        ex = $!
      end
      if remaining.nil?
        buf << chunk
      elsif remaining > 0
        captured = chunk.byteslice(0, remaining)
        buf << captured
        remaining -= captured.bytesize
      end
      buf.replace(buf.byteslice(-tail, tail)) if tail and buf.bytesize > tail
    rescue EOFError, Errno::EIO, IOError
      break
    end
    ex ? raise(ex) : (tail ? text(buf) : buf)
  end

  ##
  # @param [String] buf
  # @return [String]
  def text(buf)
    buf.dup.force_encoding(Encoding::UTF_8).scrub
  end

  ##
  # Returns a pipe pair used for the command's standard
  # input. When no input is set, the child reads from
  # IO::NULL. When the input is another command, the
  # source command is spawned first and its stdout
  # feeds the pipe.
  # @return [IO]
  #  A read end (IO::NULL or a pipe read end)
  def input_pipe
    return IO::NULL if @stdin.nil?
    data = self.class === @stdin ? @stdin.stdout : @stdin.to_s
    r, w = IO.pipe
    Thread.new do
      w.write(data)
    rescue Errno::EPIPE, IOError
      nil
    ensure
      w.close unless w.closed?
    end
    r
  end
  ##
  # Blocks until the spawned command has finished, its
  # output has been read, and its exit status captured.
  # Safe to call more than once.
  # @return [void]
  def consume
    return unless @producer&.alive?
    @producer.join
  end

  ##
  # Returns a failed status that works across Unix and
  # Windows.
  # @return [Process::Status]
  def failed_status
    ruby = [RbConfig.ruby, "-e", "exit 1"]
    _, status = Process.waitpid2 Process.spawn(*ruby)
    status
  end
end
