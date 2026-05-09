# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Ruborg::Progress do
  let(:output) { StringIO.new }
  subject(:progress) { described_class.new(output: output) }

  # StringIO is never a real TTY; force TTY mode so we can test ANSI behaviour
  let(:tty_progress) do
    allow(output).to receive(:isatty).and_return(true)
    described_class.new(output: output)
  end

  describe "#stage" do
    it "prints a numbered stage line" do
      progress.stage(1, 3, "Verifying repository")
      expect(output.string).to include("[1/3] Verifying repository")
    end

    it "includes all three components: index, total, label" do
      progress.stage(2, 4, "Backing up files")
      expect(output.string).to match(/\[2\/4\].*Backing up files/)
    end

    it "stops any active spinner before printing" do
      expect(progress).to receive(:stop_spin)
      progress.stage(1, 2, "Starting")
    end
  end

  describe "#done" do
    it "prints a checkmark completion line" do
      progress.done("Archive created")
      expect(output.string).to include("✓ Archive created")
    end

    it "prints nothing when label is nil" do
      progress.done
      expect(output.string.strip).to eq("")
    end

    it "stops the spinner" do
      expect(progress).to receive(:stop_spin)
      progress.done("finished")
    end
  end

  describe "#bar" do
    context "when not a TTY" do
      it "outputs nothing (non-TTY degrades silently)" do
        allow(output).to receive(:isatty).and_return(false)
        plain = described_class.new(output: output)
        plain.bar(5, 10, "file.txt")
        expect(output.string).to eq("")
      end
    end

    context "when TTY" do
      it "writes a progress bar with current/total" do
        tty_progress.bar(3, 10, "photo.jpg")
        expect(output.string).to include("3/10")
      end

      it "includes the file label" do
        tty_progress.bar(1, 5, "document.pdf")
        expect(output.string).to include("document.pdf")
      end

      it "starts the line with a carriage return to overwrite in place" do
        tty_progress.bar(1, 5, "x")
        expect(output.string).to start_with("\r")
      end

      it "shows a filled bar at 100%" do
        tty_progress.bar(10, 10, "done")
        expect(output.string).to include("=")
      end

      it "shows an empty bar at 0/N" do
        tty_progress.bar(0, 10, "starting")
        expect(output.string).not_to match(/=+>/)
      end

      it "truncates long labels to fit" do
        long_label = "a" * 100
        tty_progress.bar(1, 5, long_label)
        # Output line should not be excessively wide
        line = output.string.gsub(/\r/, "")
        expect(line.length).to be < 120
      end
    end
  end

  describe "#spin and #stop_spin" do
    context "when not a TTY" do
      it "does not start a spinner thread" do
        allow(output).to receive(:isatty).and_return(false)
        plain = described_class.new(output: output)
        plain.spin("Loading...")
        expect(plain.instance_variable_get(:@spinner_thread)).to be_nil
        plain.stop_spin
      end
    end

    context "when TTY" do
      it "starts a background thread" do
        tty_progress.spin("Working...")
        thread = tty_progress.instance_variable_get(:@spinner_thread)
        expect(thread).to be_a(Thread)
        expect(thread).to be_alive
        tty_progress.stop_spin
      end

      it "kills the thread on stop_spin" do
        tty_progress.spin("Working...")
        thread = tty_progress.instance_variable_get(:@spinner_thread)
        tty_progress.stop_spin
        sleep 0.1
        expect(thread).not_to be_alive
      end

      it "clears the spinner thread reference after stop" do
        tty_progress.spin("Working...")
        tty_progress.stop_spin
        expect(tty_progress.instance_variable_get(:@spinner_thread)).to be_nil
      end

      it "is safe to call stop_spin when no spinner is running" do
        expect { tty_progress.stop_spin }.not_to raise_error
      end

      it "replaces an existing spinner when spin is called again" do
        tty_progress.spin("First")
        first_thread = tty_progress.instance_variable_get(:@spinner_thread)
        tty_progress.spin("Second")
        second_thread = tty_progress.instance_variable_get(:@spinner_thread)
        expect(second_thread).not_to eq(first_thread)
        tty_progress.stop_spin
      end
    end
  end

  describe "non-TTY plain text degradation" do
    it "stage still prints output when not a TTY" do
      progress.stage(1, 2, "Verifying")
      expect(output.string).to include("[1/2] Verifying")
    end

    it "done still prints output when not a TTY" do
      progress.done("Completed")
      expect(output.string).to include("✓ Completed")
    end
  end
end
