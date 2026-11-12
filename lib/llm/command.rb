# frozen_string_literal: true

##
# Originally known as test-cmd.rb
# See https://github.com/altruby/test-cmd.rb
class LLM::Command
  require "rbconfig"

  begin
    require "pty"
    HAS_PTY = true
  rescue LoadError
    HAS_PTY = false
  end

  ##
  # @api private
  class Pipe < Struct.new(:r, :w)
    def self.pair
      new(*HAS_PTY ? PTY.open : IO.pipe)
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
    @status = nil
    @spawned = false
    @stdout = ""
    @stderr = ""
    @enoent = false
    @limit = {stdout: nil, stderr: nil}
  end

  ##
  # @param [Array<String, #to_s>] arguments
  #  Command-line arguments
  # @return [LLM::Command]
  def arguments(*arguments)
    tap { @argv.concat(arguments) }
  end
  alias_method :argv, :arguments

  ##
  # @param [Hash{String => String}] env
  #  Environment variables to set for the spawned command
  # @return [LLM::Command]
  def env(env)
    tap { (@env ||= {}).merge!(env) }
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
  # A stream output beyond the limit is discarded, keeping
  # memory bounded even for a command that streams a lot.
  # @param [Integer, nil] stdout
  #  Max bytes of stdout to read, or nil for unlimited
  # @param [Integer, nil] stderr
  #  Max bytes of stderr to read, or nil for unlimited
  # @return [LLM::Command]
  def limit(stdout: nil, stderr: nil)
    tap { @limit = {stdout:, stderr:} }
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
        @cmd, *@argv.map(&:to_s),
        {in: @in_r, out: @out.w, err: @err.w}
      )
      @in_r.close unless @in_r.equal?(IO::NULL)
      @out.w.close
      @err.w.close
      lock   = Mutex.new
      reader = lambda do |pipe, limit|
        read_limited(pipe, limit) do |chunk|
          blk ? lock.synchronize { blk.call(chunk) } : nil
        end
      end
      @stdout_reader = Thread.new { reader.call(@out.r, @limit[:stdout]) }
      @stderr_reader = Thread.new { reader.call(@err.r, @limit[:stderr]) }
      @producer = Thread.new do
        @stdout = @stdout_reader.value
        @stderr = @stderr_reader.value
        @status = Process.waitpid2(@pid).last
      rescue Errno::ECHILD
        @status = failed_status
      ensure
        @out.r.close
        @err.r.close
      end
    end
  rescue Errno::ENOENT => ex
    @stderr = ex.message
    @enoent = true
    ##
    # Close the read end of any input pipe so a pending
    # writer thread does not block forever.
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
    @producer&.alive?
  end
  alias_method :running?, :alive?

  ##
  # Sends SIGKILL to a running command
  # @return [void]
  def kill!
    return unless alive?
    Process.kill("SIGKILL", @pid)
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

  private

  ##
  # Builds the environment passed to Process.spawn.
  # The spawned process receives only the variables
  # set with #env: every inherited variable is
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
  # Reads up to +max+ bytes from a stream, then drains
  # the remainder so a child writing more than the limit
  # does not block on a full pipe. When +max+ is nil the
  # entire stream is read.
  # @param [IO] io
  # @param [Integer, nil] max
  # @return [String]
  def read_limited(io, max)
    buf, remaining, ex = [+"", max, nil]
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
    rescue EOFError, Errno::EIO
      break
    end
    ex ? raise(ex) : buf
  end

  ##
  # Returns a pipe pair used for the command's
  # standard input. When no input is set, the child
  # reads from IO::NULL. When the input is another
  # command, the source command is spawned first and
  # its stdout feeds the pipe.
  # @return [IO]
  #  A read end (IO::NULL or a pipe read end)
  def input_pipe
    return IO::NULL if @stdin.nil?
    data = self.class === @stdin ? @stdin.stdout : @stdin.to_s
    r, w = IO.pipe
    w.write(data)
    w.close
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
  # Returns a failed status that works across Unix and Windows.
  # @return [Process::Status]
  def failed_status
    ruby = [RbConfig.ruby, "-e", "exit 1"]
    _, status = Process.waitpid2 Process.spawn(*ruby)
    status
  end
end
