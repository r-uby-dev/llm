#!/usr/bin/env ruby

require "llm"
require "json"
require "fileutils"
require "securerandom"

##
# utils

def providers
  @providers ||= Dir[File.join(__dir__, "..", "lib", "llm", "providers", "*")]
    .select { File.file?(_1) }
    .map { File.basename(_1, ".rb") }
    .sort_by { |provider|
      # <3 DeepSeek
      case provider
      when "deepseek" then -1
      when "ollama", "llamacpp" then 1
      else 0
      end
    }
end

def warn_title(text)
  wrap(text, 51).each_with_index { |chunk, i| warn(i.zero? ? "  ✖  #{chunk}" : "     #{chunk}") }
end

def wrapped(text, prefix)
  line = "#{prefix}#{text}"
  line.length <= 58 ? warn(line) : wrap(text, 51).each { |chunk| warn "#{prefix}#{chunk}" }
end

def wrap(text, width)
  text.split.each_with_object([+""]) do |word, lines|
    line_length = lines.last.length
    word_length = word.length
    if line_length.positive? and line_length + word_length + 1 > width
      lines << +""
    end
    lines.last << (line_length.zero? ? word : " #{word}")
  end
end

def version
  warn "llm.rb v#{LLM::VERSION}"
end

def help
  prog = File.basename($PROGRAM_NAME)
  warn ""
  warn "Usage: #{prog} [options]"
  warn ""
  warn "Options:"
  warn "  -p PROVIDER    Choose a provider"
  warn "  -m MODEL       Choose a model"
  warn "  -c STRATEGY    Concurrency strategy for tool calls (eg thread, async, fork)"
  warn "  -n TRANSPORT   HTTP transports - net-http (default), net-http-persistent, and curb"
  warn "  -x TIMEOUT     The default read timeout (in seconds)"
  warn "  -t             Temporary session that doesn't persist to disk"
  warn "  -v             Print version information"
  warn "  -h             Show this help"
  warn ""
  warn "Examples:"
  warn "  #{prog}                     # auto-detect provider from $PROVIDER_API_KEY"
  warn "  #{prog} -p openai           # use OpenAI"
  warn "  #{prog} -m gpt-5.6          # use a model other than the provider default"
  warn "  #{prog} -n curb             # use libcurl"
  warn "  #{prog} -c thread           # run tool calls on a separate thread"
  warn "  #{prog} -x 900              # read timeout of 15mins"
  warn "  #{prog} -h                  # this help"
  warn ""
end

def loaderror(ex)
  gem, = ex.message.split(" is an optional runtime dependency")
  warn ""
  warn "  ── llm.rb ──────────────────────────────────────────────"
  warn ""
  warn_title "Missing dependency: #{gem}"
  warn ""
  warn "     The console needs this gem, but it's not installed."
  warn ""
  wrapped "Fix:  gem install #{gem}", "     "
  wrapped "Or:   bundle add #{gem}", "     "
  warn ""
  warn "     Tip:  If you don't need the console, you can use the"
  wrapped "library directly with:  require \"llm\"", "           "
  warn ""
  warn "  ───────────────────────────────────────────────────────"
  warn ""
end

def fatal(ex)
  title  = ex.message.lines.first.to_s.strip
  detail = ex.message.lines.drop(1).map(&:strip).reject(&:empty?).first
  warn ""
  warn "  ── llm.rb ──────────────────────────────────────────────"
  warn ""
  warn_title "#{ex.class}: #{title}"
  if detail
    warn ""
    wrapped detail, "     "
  end
  warn ""
  warn "     Backtrace:"
  ex.backtrace.drop(1).first(3).each do |line|
    wrapped line, "       "
  end
  warn ""
  warn "     This is an unexpected error. If it keeps happening,"
  warn "     consider opening an issue at"
  warn "     https://github.com/r-uby-dev/llm/issues"
  warn ""
  warn "  ───────────────────────────────────────────────────────"
  warn ""
  exit 1
end

##
# main

def main(argv)
  ##
  # Make sure the dependencies are satisified first
  begin
    require "llm/tools"
    require "llm/console"
  rescue LLM::LoadError => ex
    loaderror(ex)
    exit 1
  end

  begin
    ##
    # C-Style option parser
    # No external dep
    while option = argv.shift
      case option
      when '-h'
        help
        exit 0
      when '-v'
        version
        exit 0
      when '-t'
        temp = true
      when '-c'
        concurrency = argv.shift
        if concurrency.nil?
          warn "llm.rb: -c switch requires an argument"
          help
          exit 1
        else
          concurrency = concurrency.to_sym
        end
      when '-n'
        transport = argv.shift
        if transport.nil?
          warn "llm.rb: -n switch requires an argument"
          help
          exit 1
        else
          transport = transport.gsub("-", "_").to_sym
        end
      when '-p'
        provider = argv.shift
        if provider.nil?
          warn "llm.rb: -p switch requires an argument"
          help
          exit 1
        end
      when '-m'
        model = argv.shift
        if model.nil?
          warn "llm.rb: -m switch requires an argument"
          help
          exit 1
        end
      when '-x'
        timeout = argv.shift
        if timeout.nil?
          warn "llm.rb: -x switch requires an argument"
          help
          exit 1
        else
          timeout = Integer(timeout)
        end
      else
        warn "llm.rb: unknown option #{option}"
        help
        exit 1
      end
    end

    ##
    # No provider has been given.
    # Try to infer one.
    transport ||= :net_http
    options = timeout ? {timeout:, transport:} : {transport:}
    if provider.nil?
      llm = providers.filter_map do
        LLM.method(_1).call(**options)
      rescue ArgumentError
      end.first
      if llm.nil?
        warn "llm.rb: provide a provider with the -p switch"
        exit 1
      end
    else
      begin
        llm = LLM.method(provider).call(**options)
      rescue ArgumentError
        warn "llm.rb: set credentials for #{provider}"
        exit 1
      rescue NameError
        warn "llm.rb: unknown provider (#{provider})"
        exit 1
      end
    end

    ##
    # Setup the filesystem where <provider>.json maps
    # the current working directory to a session file,
    # and where the session file is stored in
    # `~/.llm.rb/<provider>/<uuid>.json`.
    # This can be skipped with the `-t` option.
    if temp.nil?
      home   = File.join(Dir.home, ".llm.rb")
      file   = File.join(home, "#{llm.name}.json")
      parent = File.join(home, llm.name.to_s)

      FileUtils.mkdir_p(parent)
      FileUtils.touch(file)

      if File.size(file).zero?
        data = LLM::Object.from({})
        File.binwrite file, JSON.pretty_generate(data)
      else
        data = LLM::Object.from JSON.parse(File.read(file))
      end
      data[Dir.getwd] ||= File.join(parent, "#{SecureRandom.uuid}.json")
      File.binwrite file, JSON.pretty_generate(data)
    end

    if model
      if not llm.registry.keys.include?(model)
        warn "llm.rb: #{model} is not a valid #{llm.name} model"
        exit 1
      end
    else
      model = llm.default_model
    end

    ##
    # Let's go!
    concurrency ||= :sequential
    path  = temp ? nil : data[Dir.getwd]
    agent = LLM::Agent.new(llm, model:, path:, concurrency:, tools: LLM::Tool.subclasses)
    agent.console
  rescue Interrupt
    warn "llm.rb: Bye!"
  rescue => ex
    fatal(ex)
  end
end
main(ARGV)
