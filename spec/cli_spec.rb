require "floe/cli"

RSpec.describe Floe::CLI do
  describe "#run" do
    let(:workflow) { File.expand_path("data/workflow.asl", __dir__) }

    it "displays help" do
      output, _error, result = run_cli("--help")
      expect(result).to be true

      lines = output.lines(:chomp => true)
      expect(lines).to start_with("Usage: #{File.basename($PROGRAM_NAME)} [options] workflow input [workflow2 input2]")
      expect(lines).to include("v#{Floe::VERSION}")

      # it should also include options from runners
      expect(lines).to include("Container runner options:")
    end

    it "with no parameters" do
      _output, error, result = run_cli
      expect(result).to be false

      lines = error.lines(:chomp => true)
      expect(lines.first).to eq("Error: workflow/input pairs must be specified.")
    end

    it "with a bare workflow and no input" do
      output, _error, result = run_cli(workflow)
      expect(result).to be true

      lines = output.lines(:chomp => true)
      expect(lines.first).to include("Checking 1 workflows...")
      expect(lines.last).to include("{}")
    end

    it "with a bare workflow and input" do
      output, _error, result = run_cli(workflow, '{"foo":1}')
      expect(result).to be true

      lines = output.lines(:chomp => true)
      expect(lines.first).to include("Checking 1 workflows...")
      expect(lines.last).to include('{"foo":1}')
    end

    it "with a bare workflow and --input" do
      output, _error, result = run_cli(workflow, "--input", '{"foo":1}')
      expect(result).to be true

      lines = output.lines(:chomp => true)
      expect(lines.first).to include("Checking 1 workflows...")
      expect(lines.last).to include('{"foo":1}')
    end

    it "with --workflow and no input" do
      output, _error, result = run_cli("--workflow", workflow)
      expect(result).to be true

      lines = output.lines(:chomp => true)
      expect(lines.first).to include("Checking 1 workflows...")
      expect(lines.last).to include("{}")
    end

    it "with --workflow and --input" do
      output, _error, result = run_cli("--workflow", workflow, "--input", '{"foo":1}')
      expect(result).to be true

      lines = output.lines(:chomp => true)
      expect(lines.first).to include("Checking 1 workflows...")
      expect(lines.last).to include('{"foo":1}')
    end

    it "with a bare workflow and --workflow" do
      _output, error, result = run_cli(workflow, "--workflow", workflow)
      expect(result).to be false

      lines = error.lines(:chomp => true)
      expect(lines.first).to include("Error: cannot specify both --workflow and bare workflows.")
    end

    it "with --input but no workflows" do
      _output, error, result = run_cli("--input", '{"foo":1}')
      expect(result).to be false

      lines = error.lines(:chomp => true)
      expect(lines.first).to include("Error: workflow(s) must be specified.")
    end

    it "with multiple bare workflow/input pairs" do
      output, _error, result = run_cli(workflow, '{"foo":1}', workflow, '{"foo":2}')
      expect(result).to be true

      lines = output.lines(:chomp => true)
      expect(lines.first).to include("Checking 2 workflows...")
      expect(lines.last(7).map { |line| line.gsub(/^.* INFO -- : /, "") }.join("\n")).to eq(<<~OUTPUT.chomp)
        workflow
        ===
        {"foo":1}

        workflow
        ===
        {"foo":2}
      OUTPUT
    end

    it "with multiple bare workflows and --input" do
      output, _error, result = run_cli(workflow, workflow, "--input", '{"foo":1}')
      expect(result).to be true

      lines = output.lines(:chomp => true)
      expect(lines.first).to include("Checking 2 workflows...")
      expect(lines.last(7).map { |line| line.gsub(/^.* INFO -- : /, "") }.join("\n")).to eq(<<~OUTPUT.chomp)
        workflow
        ===
        {"foo":1}

        workflow
        ===
        {"foo":1}
      OUTPUT
    end

    it "with mismatched workflow/input pairs" do
      _output, error, result = run_cli(workflow, workflow, '{"foo":2}')
      expect(result).to be false

      lines = error.lines(:chomp => true)
      expect(lines.first).to include("Error: workflow/input pairs must be specified.")
    end

    def run_cli(*args)
      capture_io { described_class.new.run(args) }
    end

    def capture_io
      output, error = StringIO.new, StringIO.new
      stdout, stderr = $stdout, $stderr
      $stdout, $stderr = output, error
      result = yield
      return output.string, error.string, result
    rescue SystemExit => err
      return output.string, error.string, err.success?
    ensure
      $stdout, $stderr = stdout, stderr
    end
  end
end
