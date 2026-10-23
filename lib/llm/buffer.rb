# frozen_string_literal: true

module LLM
  ##
  # {LLM::Buffer LLM::Buffer} provides an Enumerable object that
  # tracks messages in a conversation thread. Access it through
  # {LLM::Context#messages}.
  #
  # @example Working with message history
  #   ctx.messages.last           # => most recent message
  #   ctx.messages.first          # => oldest message
  #   ctx.messages.select! { |m| m.assistant? }
  #   ctx.messages.reverse        # => reversed copy
  #   ctx.messages.reject! { |m| m.compaction? }
  #
  # @see LLM::Message Individual messages in the buffer
  # @see LLM::Context Where the buffer lives (ctx.messages)
  class Buffer
    include Enumerable

    UNDEFINED = ::Object.new.freeze
    private_constant :UNDEFINED

    ##
    # @param [LLM::Provider] llm
    # @return [LLM::Buffer]
    def initialize(llm)
      @llm = llm
      @messages = []
    end

    ##
    # Append an array
    # @param [Array<LLM::Message>] ary
    #  The array to append
    def concat(ary)
      @messages.concat(ary)
    end

    ##
    # Replace the tracked messages
    # @param [Array<LLM::Message>] messages
    #  The replacement messages
    # @return [LLM::Buffer]
    def replace(messages)
      @messages.replace(messages)
      self
    end

    ##
    # @yield [LLM::Message]
    #  Yields each message in the conversation thread
    # @return [void]
    def each(...)
      if block_given?
        @messages.each { yield(_1) }
      else
        enum_for(:each, ...)
      end
    end

    ##
    # Find a message (in descending order)
    # @return [LLM::Message, nil]
    def find(...)
      reverse_each.find(...)
    end

    ##
    # Returns the index of the last message matching the given block.
    # @yield [LLM::Message]
    # @return [Integer, nil]
    def rindex(...)
      @messages.rindex(...)
    end

    ##
    # Returns the last message(s) in the buffer
    # @param [Integer, nil] n
    #  The number of messages to return
    # @return [LLM::Message, Array<LLM::Message>, nil]
    def last(n = UNDEFINED)
      n.equal?(UNDEFINED) ? @messages.last : @messages.last(n)
    end

    ##
    # Returns the first message(s) in the buffer
    # @param [Integer, nil] n
    #  The number of messages to return
    # @return [LLM::Message, Array<LLM::Message>, nil]
    def first(n = UNDEFINED)
      n.equal?(UNDEFINED) ? @messages.first : @messages.first(n)
    end

    ##
    # Removes messages matching the block in-place.
    # @yield [LLM::Message]
    # @return [LLM::Buffer]
    def reject!(&)
      @messages.reject!(&)
      self
    end
    alias_method :delete_if, :reject!

    ##
    # Keeps messages matching the block in-place.
    # @yield [LLM::Message]
    # @return [LLM::Buffer]
    def select!(&)
      @messages.select!(&)
      self
    end

    ##
    # Removes and returns the first message.
    # @return [LLM::Message, nil]
    def shift
      @messages.shift
    end

    ##
    # Removes all messages.
    # @return [LLM::Buffer]
    def clear
      @messages.clear
      self
    end

    ##
    # Returns all elements after the first n.
    # @param [Integer] n
    #  The number of messages to skip
    # @return [Array<LLM::Message>]
    def drop(n)
      @messages.drop(n)
    end

    ##
    # Returns the first n elements without removing them.
    # @param [Integer] n
    #  The number of messages to return
    # @return [Array<LLM::Message>]
    def take(n)
      @messages.take(n)
    end

    ##
    # Slice a portion of the internal buffer in-place
    # @return [void]
    def slice!(...)
      @messages.slice!(...)
      nil
    end

    ##
    # Pop the last element from the tail of the buffer
    # @return [void]
    def pop
      @messages.pop
    end

    ##
    # @param [[LLM::Message]] item
    #  A message to add to the buffer
    # @return [void]
    def <<(item)
      @messages << item
      self
    end
    alias_method :push, :<<

    ##
    # @param [Integer, Range] index
    #  The message index
    # @return [LLM::Message, nil]
    #  Returns a message, or nil
    def [](index)
      @messages[index]
    end

    ##
    # Returns a reversed copy of the internal array.
    # @return [Array]
    def reverse
      @messages.reverse
    end

    ##
    # @return [String]
    def to_json(...)
      LLM.json.dump(@messages, ...)
    end

    ##
    # @return [String]
    def inspect
      "#<#{LLM::Utils.object_id(self)} message_count=#{@messages.size}>"
    end

    ##
    # @return [Integer]
    #  Returns the number of messages in the buffer
    def size
      @messages.size
    end

    ##
    # Returns true when the buffer is empty
    # @return [Boolean]
    def empty?
      @messages.empty?
    end
  end
end
