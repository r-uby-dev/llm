# frozen_string_literal: true

class LLM::Console::Markdown
  ##
  # Renders Kramdown `:table` nodes as aligned columns.
  module Table
    ##
    # @api private
    Node  = LLM::Console::Node
    Color = LLM::Console::Color
    private_constant :Node
    private_constant :Color

    ##
    # Renders a table node by collecting all cells first to
    # compute column widths, then emitting each row with
    # padded text.
    def walk_table(node, attrs)
      rows = collect_rows(node, attrs)
      return if rows.empty?
      widths = column_widths(rows)
      rows.each do |row|
        emit("| ", attrs)
        row.each_with_index do |chunks, i|
          width = widths[i]
          chunks.each do |c|
            text = c[:text].to_s
            emit(text + (" " * (width - Node.width(text))), c[:attrs])
          end
          emit(" | ", attrs) unless i == row.size - 1
        end
        emit(" |", attrs)
        emit("\n", attrs)
      end
      emit("\n", attrs)
    end

    private

    def collect_rows(node, attrs)
      node.children.each_with_object([]) do |section, rows|
        next unless [:thead, :tbody].include?(section.type)
        section.children.each do |tr|
          next unless tr.type == :tr
          cells = tr.children.filter_map do |td|
            next unless [:td, :th].include?(td.type)
            collect_chunks(td, attrs)
          end
          rows << cells
        end
      end
    end

    def collect_chunks(node, attrs)
      [].tap do |chunks|
        walk_collect(node, attrs, chunks)
      end
    end

    def walk_collect(node, attrs, chunks)
      case node.type
      when :text
        chunks << Node.new(node.value.to_s, attrs)
      when :strong
        node.children.each { walk_collect(_1, Curses::A_BOLD, chunks) }
      when :em
        node.children.each { walk_collect(_1, Curses::A_UNDERLINE, chunks) }
      when :codespan
        chunks << Node.new(node.value, Color.green)
      when :a
        node.children.each { walk_collect(_1, Curses::A_UNDERLINE, chunks) }
      when :typographic_sym, :smart_quote
        chunks << Node.new(symbol(node), attrs)
      else
        node.children.each { walk_collect(_1, attrs, chunks) }
      end
    end

    def column_widths(rows)
      return [] if rows.empty?
      cols = rows.first.size
      (0...cols).map do |i|
        rows.map { |r| Node.width(r[i].map { _1[:text] }.join) }.max
      end
    end
  end
end
