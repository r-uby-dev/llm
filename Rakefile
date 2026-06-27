# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

cassettes = File.join(__dir__, "spec", "fixtures", "cassettes")
remotes = %w[openai google anthropic deepseek]
locals  = %w[ollama llamacpp]
bundler = ENV["bundler"] || "bundle"

desc "Run linter"
task :rubocop do
  sh "#{bundler} exec rubocop"
end

namespace :spec do
  namespace :remote do
    desc "Clear remote cassette cache"
    task :clear do
      remotes.each { rm_rf File.join(cassettes, _1) }
    end
  end

  desc "Run remote tests"
  task :remote do
    paths = ["spec/readme_spec.rb", "spec/{#{remotes.join(",")}}/**/*.rb"]
    specs = Dir[*paths].shuffle
    sh "#{bundler} exec rspec #{specs.join(' ')}"
  end

  namespace :local do
    desc "Clear local cassette cache"
    task :clear do
      locals.each { rm_rf File.join(cassettes, _1) }
    end
  end
end

desc "Run all tests"
task :spec do
  sh "#{bundler} exec rspec spec"
end

desc "Start a console with all providers loaded"
task :console do
  require "llm"
  require "dotenv"
  Dotenv.load
  openai = LLM.openai(key: ENV["OPENAI_SECRET"])
  google = LLM.google(key: ENV["GOOGLE_SECRET"])
  anthropic = LLM.anthropic(key: ENV["ANTHROPIC_SECRET"])
  deepseek = LLM.deepseek(key: ENV["DEEPSEEK_SECRET"])
  xai = LLM.xai(key: ENV["XAI_SECRET"])
  binding.irb
end

Dir[File.join(__dir__, "tasks", "*.rake")].sort.each do |task|
  load task
end

namespace :'models.dev' do
  desc "Download models.dev metadata"
  task :download do
    require "net/http"
    require "json"
    client = Net::HTTP.new "models.dev", 443
    client.use_ssl = true
    res = client.request Net::HTTP::Get.new("/api.json")
    case res
    when Net::HTTPOK
      models = JSON.parse(res.body)
      providers = %w[openai google anthropic xai zai deepseek deepinfra].to_h { [_1, _1] }
      providers["bedrock"] = "amazon-bedrock"
      providers.each do |target, source|
        File.binwrite "data/#{target}.json", JSON.pretty_generate(models[source])
      end
    else
      warn("error: #{res.class}")
      exit 1
    end
  end
end

namespace :agents do
  desc "Run the release agent"
  task :release do
    sh "bundle exec ruby agents/release-agent/main.rb"
  end
end

task default: %i[spec rubocop]
