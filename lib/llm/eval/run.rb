# frozen_string_literal: true

class LLM::Eval
  ##
  # Run-level report generation.
  module Run
    ##
    # Writes the run-level report, accumulating every sample.
    # @return [void]
    def run_aggregate
      dir = File.join(Dir.getwd, "runs", name.to_s, llm.name.to_s, model.to_s)
      FileUtils.mkdir_p(dir)
      json = File.join(dir, "run.json")
      data = if File.exist?(json)
        JSON.parse(File.read(json))
      else
        {
          "eval" => name,
          "provider" => llm.name.to_s,
          "model" => model.to_s,
          "samples" => []
        }
      end
      data["samples"] ||= []
      data["samples"].reject! { it["sample"] == sample }
      data["samples"] << run_sample_entry
      data["samples"].sort_by! { it["sample"] }
      data["score"] = data["samples"].sum { it["score"] } / data["samples"].size.to_f
      File.write(json, JSON.pretty_generate(data))
      File.write(File.join(dir, "run.txt"), run_text_report(data))
    end

    private

    ##
    # @return [Hash]
    def run_sample_entry
      base = File.join("runs", name.to_s, llm.name.to_s, model.to_s, sample.to_s)
      {
        "sample" => sample,
        "score" => result,
        "text" => File.join(base, "sample.txt"),
        "json" => File.join(base, "sample.json")
      }
    end

    ##
    # @param [Hash] data
    # @return [String]
    def run_text_report(data)
      lines = []
      lines << data["eval"].to_s
      lines << [data["provider"], data["model"]].compact.join(" ")
      lines << ""
      lines << format("%-6s %-6s %s", "sample", "score", "report")
      data["samples"].each do |s|
        lines << format("%-6d %-6.2f %s", s["sample"], s["score"], s["text"])
      end
      lines << ""
      lines << format("%-6s %-6.2f", "all", data["score"])
      lines.join("\n") + "\n"
    end
  end
  include Run
end
