# frozen_string_literal: true

class LLM::Compactor
  ##
  # An {LLM::Compactor::Auto LLM::Compactor::Auto} trims the conversation
  # when the context window fills, and it is the compactor a context runs
  # with when no other compactor is configured.
  #
  # Two options decide everything, and both are shares of the window:
  # `compact_when` is how full the window may get before a trim runs, and
  # `keep` is what the conversation weighs afterwards. The defaults read as
  # "trim at five percent full, come back holding ten percent" - a
  # conversation that stays around ten percent of the window is unlikely to
  # ever be refused by the model - and since a trim is an in-memory erase
  # rather than a request, it costs only what it discards.
  #
  # A trim runs only when the conversation weighs more than `keep`, so a
  # `keep` that is not below `compact_when` is a floor rather than a
  # contradiction: there is nothing to reclaim from a conversation that is
  # already lighter than what `keep` asks for, and a conversation that is
  # heavier is trimmed back to it.
  #
  # What survives is the newest end of the conversation: the recent turns,
  # whole tool exchanges, and the system message.
  # {LLM::Compactor::Truncate} does the slicing, so no model call is made.
  #
  # It returns nil when nothing happened - inside the window, or with no
  # usage or no window to go on - which is the contract callers already
  # handle.
  class Auto < self
    ##
    # How full the window may get before a trim runs.
    COMPACT_WHEN = "5%"

    ##
    # What the conversation is left weighing.
    KEEP = "10%"

    ##
    # Compacts, if there is anything to compact.
    #
    # The newest request reports the size of the whole conversation, so
    # that is the figure the trigger is compared against, and `keep` is
    # turned into a number of tokens from the window it is a share of.
    # @param [String, Numeric, Rational] compact_when
    #  How full the window may get before a trim runs
    # @param [String, Numeric, Rational] keep
    #  What the conversation is left weighing
    # @return [Array<LLM::Message>, nil]
    #  Returns the messages that were kept, or nil when nothing needed
    #  to happen
    def call(compact_when: COMPACT_WHEN, keep: KEEP)
      trigger, target = to_r(compact_when), to_r(keep)
      used = live_usage
      total = ctx.context_window
      return nil if used.nil? || total.nil? || total <= 0
      return nil if Rational(used, total) <= trigger
      count = count_to_keep(target * total)
      return nil if count.zero?
      LLM::Compactor::Truncate.new(ctx).call(keep: count)
    end

    private

    ##
    # The size of the conversation, as the newest request reported it.
    #
    # An older figure describes a conversation that has since grown into
    # this one, so the newest is the one that answers "how full is it now".
    # @return [Integer, nil]
    def live_usage
      messages
        .reverse
        .find(&:assistant?)
        &.token_usage
        &.total_tokens
    end

    ##
    # How many of the newest messages weigh about `target`.
    #
    # The figure a request reports is the size of a whole conversation
    # rather than of a message, so a message cannot be weighed on its own.
    # The growth between one request and the next can: it is what the turns
    # between them added. Walking back and adding that growth reaches the
    # target, and the cut goes after the request it reaches it at.
    #
    # The step across a trim is not growth. A trim leaves later requests
    # reporting less than the ones before it, so that step weighs nothing
    # rather than being subtracted, and the walk carries on into what the
    # trim kept - which it measures by the same rule, on the figures that
    # were recorded before it.
    #
    # What it keeps weighs the target or a little more: the cut can only
    # land on a turn, and the growth between two requests is a coarse
    # measure of the turns between them.
    # @param [Integer, Rational] target
    # @return [Integer]
    #  The number of messages to keep, zero when the conversation is
    #  already lighter than the target and there is nothing to reclaim
    def count_to_keep(target)
      history = messages.to_a
      index = cut_after(history, target)
      return 0 if index.nil?
      next_user = history[(index + 1)..]&.index(&:user?)
      start = next_user ? index + 1 + next_user : history[0..index].rindex(&:user?)
      kept = start ? history.drop(start) : history
      [kept.count { |message| !message.system? }, 1].max
    end

    ##
    # The request to cut after, or nil when the whole conversation is
    # lighter than the target.
    #
    # A message that reports nothing is stepped over rather than treated as
    # a boundary, because the next figure covers everything between the two
    # requests either side of it.
    # @param [Array<LLM::Message>] history
    # @param [Integer, Rational] target
    # @return [Integer, nil]
    def cut_after(history, target)
      weight, figure = 0, nil
      history.each_index.reverse_each do |at|
        message = history[at]
        next unless message.assistant?
        usage = message.token_usage&.total_tokens.to_i
        next unless usage.positive?
        weight += [(figure - usage), 0].max if figure
        figure = usage
        return at if weight >= target
      end
      nil
    end

    ##
    # Reads a share of the window.
    #
    # "50%" and 50 are halves, and so are 0.5 and Rational(1, 2). A number
    # below one is a fraction and anything else is a percentage, which is
    # the reading that makes 50 mean half rather than fifty.
    # @param [String, Numeric, Rational] value
    # @return [Rational]
    def to_r(value)
      return value if Rational === value
      if String === value
        value.end_with?("%") ? Rational(value.delete_suffix("%"), 100) : Rational(value)
      elsif value < 1
        Rational(value)
      else
        Rational(value, 100)
      end
    end
  end
end
