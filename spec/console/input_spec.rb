# frozen_string_literal: true

require "setup"
require "llm/console"

RSpec.describe LLM::Console::Input do
  let(:llm) { LLM.deepseek(key: ENV["test"]) }
  let(:console) { LLM::Console.new(agent:) }
  let(:agent) { LLM::Agent.new(llm) }
  let(:input) { described_class.new(console) }

  describe "#restore" do
    let(:buffer) { "" }
    let(:copy) { "" }
    let(:cursor) { 0 }

    before do
      set_buffer(buffer)
      input.instance_variable_set(:@copy, copy)
      input.instance_variable_set(:@cursor, [0, cursor])
    end

    context "when we're at the end of the string" do
      let(:buffer) { +"hello" }
      let(:copy) { " world" }
      let(:cursor) { buffer.size }

      it "appends to the end of the string" do
        input.restore
        expect(input.buffer).to eq("hello world")
      end
    end

    context "when we're inside the string " do
      let(:buffer) { +"hello" }
      let(:copy) { " world" }
      let(:cursor) { 3 }

      it "inserts the string in-place" do
        input.restore
        expect(input.buffer).to eq("hel worldlo")
      end
    end
  end

  describe "#set" do
    before { allow(Curses).to receive(:cols).and_return(30) }

    let(:text) { "" }
    let(:rows) { input.instance_variable_get(:@rows) }

    before { input.send(:set, text:) }

    context "when given a long line" do
      let(:text) { "this is a rather long sentence that wraps onto several lines" }

      it "wraps the line into display rows" do
        expect(rows.size).to be > 1
        expect(rows.map(&:to_s).join(" ")).to eq(text)
      end

      it "flattens back to the original text" do
        expect(input.take).to eq(text)
      end
    end

    context "when given real newlines" do
      let(:text) { "line one\nline two\nline three" }

      it "keeps each line as a row" do
        expect(rows.map(&:to_s)).to eq(["line one", "line two", "line three"])
      end
    end

    context "when given a literal backslash-n" do
      let(:text) { 'a\nb' }

      it "treats it as text rather than a break" do
        expect(rows.map(&:to_s)).to eq(['a\nb'])
      end
    end

    context "when given multiple lines" do
      let(:text) { "line one\nline two" }

      it "places the cursor at the end of the last row" do
        expect(input.instance_variable_get(:@cursor)).to eq([1, 8])
      end
    end
  end

  describe "#autocomplete" do
    before { allow(Curses).to receive(:cols).and_return(149) }

    let(:command) do
      Class.new(LLM::Console::Command) do
        name "model"
        parameter :model, String, "The model"

        def complete(model: nil)
          %w[deepseek-v4-flash-0731 qwen3.6-flash qwen-flash].select do |m|
            m.start_with?(model.to_s)
          end
        end
      end
    end

    before { LLM::Command.registry[command] = command }

    context "when completing a command name" do
      before { set_buffer("/mod") }

      it "completes to the command name" do
        input.send(:autocomplete)
        expect(input.buffer).to eq("/model")
      end
    end

    context "when completing a command argument" do
      before { set_buffer("/model deep") }

      it "completes the argument from the command's complete" do
        input.send(:autocomplete)
        expect(input.buffer).to eq("/model deepseek-v4-flash-0731")
      end
    end

    context "when the argument has no match" do
      before { set_buffer("/model zzz") }

      it "leaves the input unchanged" do
        input.send(:autocomplete)
        expect(input.buffer).to eq("/model zzz")
      end
    end
  end

  describe "#delete" do
    before { allow(Curses).to receive(:cols).and_return(149) }

    context "when deleting everything" do
      before { input.send(:set, text: "line one\nline two") }

      it "consumes the break and empties the input" do
        input.instance_variable_set(:@cursor, [0, 0])
        17.times { input.send(:delete) }
        expect(input.take).to eq("")
      end
    end
  end

  describe "history recall" do
    before { allow(Curses).to receive(:cols).and_return(149) }

    let(:history) { %w[hello world] }

    before { history.each { agent.messages << LLM::Message.new("user", _1) } }

    describe "ctrl+p" do
      it "recalls the most recent turn first" do
        ctrl_p
        expect(input.buffer).to eq("world")
      end

      it "recalls older turns as it repeats" do
        2.times { ctrl_p }
        expect(input.buffer).to eq("hello")
      end
    end

    describe "ctrl+n" do
      context "walking forward through the history" do
        it "returns to the next turn" do
          ctrl_p
          ctrl_p
          ctrl_n
          expect(input.buffer).to eq("world")
        end
      end

      context "at the end of the history" do
        before { ctrl_p }

        it "returns to an empty input" do
          ctrl_n
          expect(input.buffer).to eq("")
        end

        it "stays empty when repeated" do
          ctrl_n
          ctrl_n
          expect(input.buffer).to eq("")
        end
      end
    end

    context "with no history" do
      let(:history) { [] }

      it "does not raise on ctrl+p" do
        expect { ctrl_p }.not_to raise_error
      end

      it "does not raise on ctrl+n" do
        expect { ctrl_n }.not_to raise_error
      end
    end

    ##
    # Simulates ctrl+p
    # @return [void]
    def ctrl_p
      input.on_char(nil, Curses::KEY_CTRL_P, 0)
    end

    ##
    # Simulates ctrl+n
    # @return [void]
    def ctrl_n
      input.on_char(nil, Curses::KEY_CTRL_N, 0)
    end
  end

  describe "#insert auto-wrap" do
    before { allow(Curses).to receive(:cols).and_return(149) }

    it "wraps at word boundaries instead of cutting words" do
      message = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, " \
                "sed do eiusmod tempor incididunt ut labore et dolore magna " \
                "aliqua."
      message.each_char { |char| input.on_char(nil, char, 0) }
      text = input.take
      ##
      # The input may only replace spaces with newlines to wrap.
      # Restoring those newlines back to spaces must reproduce the
      # original message, which fails if a word was cut in half.
      expect(text.gsub("\n", " ")).to eq(message)
    end

    it "preserves newlines from pasted text" do
      message = "line one\nline two\nline three"
      message.each_char { |char| input.on_char(nil, char, 0) }
      expect(input.take).to eq(message)
    end

    it "keeps auto-wraps out of the taken message" do
      long = "some words to wrap " * 20
      long.each_char { |char| input.on_char(nil, char, 0) }
      text = input.take
      expect(text).to_not include("\r")
      expect(text).to_not match(/\S\n\S/)
    end
  end

  ##
  # Sets the input rows to a single row containing the given text.
  # @param [String] string
  # @return [void]
  def set_buffer(string)
    row = LLM::Console::Input::Row.new
    string.each_char { |char| row.chars << LLM::Console::Input::Char.new(char) }
    input.instance_variable_set(:@rows, [row])
  end
end
