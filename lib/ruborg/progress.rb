# frozen_string_literal: true

module Ruborg
  # Terminal progress display: named stages, inline progress bar, and spinner.
  # Writes to $stderr so stdout remains clean for --json or piped output.
  # Degrades to plain text lines when output is not a TTY (piped / redirected).
  class Progress
    SPINNER_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
    BAR_WIDTH = 28
    LINE_WIDTH = 80

    def initialize(output: $stderr)
      @output = output
      @tty = output.respond_to?(:isatty) && output.isatty
      @spinner_thread = nil
    end

    # Print a numbered stage header: "[2/3] Label"
    def stage(index, total, label)
      stop_spin
      clear_line if @tty
      @output.puts "[#{index}/#{total}] #{label}"
    end

    # Start a spinner on the current line for an indeterminate operation.
    # Call stop_spin (or done) to halt it.
    def spin(label)
      stop_spin
      return unless @tty

      frame = 0
      @spinner_thread = Thread.new do
        loop do
          @output.print "\r  #{SPINNER_FRAMES[frame % SPINNER_FRAMES.size]}  #{label}"
          frame += 1
          sleep 0.1
        end
      end
    end

    # Stop the spinner and erase its line.
    def stop_spin
      return unless @spinner_thread

      @spinner_thread.kill
      @spinner_thread.join(0.2)
      @spinner_thread = nil
      clear_line if @tty
    end

    # Redraw an inline progress bar. Call once per item in a loop.
    # label is truncated to fit the terminal line.
    def bar(current, total, label = "")
      return unless @tty

      pct = total.positive? ? (current.to_f / total) : 0
      filled = (BAR_WIDTH * pct).round
      bar_str = filled.positive? ? "#{"=" * (filled - 1)}>" : ""
      bar_str = bar_str.ljust(BAR_WIDTH)
      short_label = truncate_left(label.to_s, 28)
      @output.print "\r  [#{bar_str}]  #{current}/#{total}  #{short_label.ljust(28)}"
    end

    # Halt any in-progress display and print a completion line.
    def done(label = nil)
      stop_spin
      clear_line if @tty
      @output.puts "  ✓ #{label}" if label
    end

    private

    def clear_line
      @output.print "\r#{" " * LINE_WIDTH}\r"
    end

    def truncate_left(str, max)
      str.length > max ? "...#{str[-(max - 3)..]}" : str
    end
  end
end
