# frozen_string_literal: true

##
# A simulated FreeBSD environment
# for the purposes of an eval.
class FreeBSD
  ##
  # @return [String]
  attr_reader :installed_kernel

  ##
  # @return [String]
  attr_reader :running_kernel

  ##
  # @return [String]
  attr_reader :userland

  def initialize
    @installed_kernel = "14.1-RELEASE-p1"
    @running_kernel   = "14.0-RELEASE-p5"
    @userland         = "14.0-RELEASE-p5"
    @seen = []
  end

  def call(args)
    command, *flags = Array(args)
    case command
    when "uname" then uname(flags)
    when "freebsd-version" then freebsd_version(flags)
    when "freebsd-update" then freebsd_update(flags)
    when "reboot" then reboot
    when "shutdown" then shutdown(flags)
    when "sysctl" then sysctl(flags)
    when "dmesg" then dmesg
    when "cat" then cat(flags)
    else {ok: false, error: "command '#{command}' was not found"}
    end
  end

  ##
  # @return [Boolean]
  def diagnosed?
    [:kernel, :running, :userland].all? { |key| @seen.include?(key) }
  end

  ##
  # @return [Boolean]
  def solved?
    running_kernel == installed_kernel and
    userland       == installed_kernel
  end

  private

  include Module.new {
    def uname(flags)
      if flags.include?("-K")
        see(:kernel)
        ok(installed_kernel)
      elsif flags.include?("-U")
        see(:userland)
        ok(userland)
      elsif flags.include?("-a")
        see(:running)
        ok("FreeBSD builder #{running_kernel} FreeBSD #{running_kernel} GENERIC amd64")
      elsif flags.include?("-r")
        see(:running)
        ok(running_kernel)
      else
        ok("FreeBSD")
      end
    end

    def cat(flags)
      if flags.last == "/etc/os-release"
        see(:userland)
        ok("NAME=FreeBSD\nVERSION=\"#{userland}\"")
      else
        {ok: false, error: "cat: #{flags.last}: No such file or directory"}
      end
    end
  }

  include Module.new {
    def freebsd_version(flags)
      letters = flags.flat_map { |flag| flag.start_with?("-") ? flag[1..].chars : [] }
      return ok(userland) if letters.empty?
      see(:kernel) if letters.include?("k")
      see(:running) if letters.include?("r")
      see(:userland) if letters.include?("u")
      lines = []
      lines << installed_kernel if letters.include?("k")
      lines << running_kernel if letters.include?("r")
      lines << userland if letters.include?("u")
      ok(lines.join("\n"))
    end

    def freebsd_update(flags)
      if flags.include?("install")
        if running_kernel != installed_kernel
          ok("Installing updates...\n"                               \
             "Kernel updates have been installed. "                  \
             "Please reboot and run 'freebsd-update install' again " \
             "to finish installing updates.")
        elsif userland != installed_kernel
          @userland = installed_kernel
          ok("Installing updates... done.")
        else
          ok("No updates are available to install.")
        end
      elsif flags.include?("fetch")
        ok("No updates available.")
      else
        ok("usage: freebsd-update fetch|install|...")
      end
    end
  }

  include Module.new {
    def reboot
      @running_kernel = installed_kernel
      ok("The system is going down for reboot NOW!")
    end

    def shutdown(flags)
      if flags.include?("-r")
        reboot
      else
        {ok: false, error: "shutdown: only -r is supported here"}
      end
    end

    def sysctl(flags)
      if flags.include?("kern.osrelease")
        see(:running)
        flags.include?("-n") ? ok(running_kernel) : ok("kern.osrelease: #{running_kernel}")
      else
        {ok: false, error: "sysctl: unknown oid"}
      end
    end

    def dmesg
      see(:running)
      ok("FreeBSD #{running_kernel} GENERIC amd64")
    end
  }

  def see(key)
    @seen << key unless @seen.include?(key)
  end

  def ok(stdout)
    {ok: true, stdout: "#{stdout}\n", stderr: "", duration: "0.0 seconds"}
  end
end
