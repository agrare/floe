RSpec.describe Floe::Workflow::Context do
  let(:ctx) { described_class.new(:input => input.to_json) }
  let(:input) { {"x" => "y"}.freeze }

  describe "#new" do
    it "with an empty context, sets input" do
      expect(ctx.execution["Input"]).to eq(input)
      expect(ctx.state).not_to eq(nil)
    end

    it "with a context, sets input and keeps context" do
      ctx = described_class.new({"Execution" => {"api" => "http://localhost/"}}, :input => input.to_json)
      expect(ctx.execution["api"]).to eq("http://localhost/")
      expect(ctx.state).not_to eq(nil)
    end

    it "defaults credentials to {}" do
      expect(ctx.credentials).to eq({})
    end

    context "with a simple string input" do
      let(:input) { "foo" }

      it "sets the input" do
        expect(ctx.execution["Input"]).to eq("foo")
        expect(ctx.state).not_to eq(nil)
      end
    end
  end

  describe "#started?" do
    it "new context" do
      expect(ctx.started?).to eq(false)
    end

    it "started" do
      ctx.execution["StartTime"] ||= Time.now.utc

      expect(ctx.started?).to eq(true)
    end
  end

  describe "#running?" do
    it "new context" do
      expect(ctx.running?).to eq(false)
    end

    it "running" do
      ctx.execution["StartTime"] ||= Time.now.utc

      expect(ctx.running?).to eq(true)
    end

    it "ended" do
      ctx.execution["StartTime"] ||= Time.now.utc
      ctx.execution["EndTime"] ||= Time.now.utc

      expect(ctx.running?).to eq(false)
    end
  end

  describe "#ended?" do
    it "new context" do
      expect(ctx.ended?).to eq(false)
    end

    it "started" do
      ctx.execution["StartTime"] ||= Time.now.utc

      expect(ctx.ended?).to eq(false)
    end

    it "ended" do
      ctx.execution["StartTime"] ||= Time.now.utc
      ctx.execution["EndTime"] ||= Time.now.utc

      expect(ctx.ended?).to eq(true)
    end
  end

  describe "#failed?" do
    it "new context" do
      expect(ctx.failed?).to eq(false)
    end

    it "started" do
      ctx.state["Output"] = {}

      expect(ctx.failed?).to eq(false)
    end

    it "ended" do
      ctx.state["Output"] = input.dup
      ctx.execution["StartTime"] ||= Time.now.utc
      ctx.execution["EndTime"] ||= Time.now.utc

      expect(ctx.failed?).to eq(false)
    end

    it "ended with error" do
      ctx.execution["StartTime"] ||= Time.now.utc
      ctx.execution["EndTime"] ||= Time.now.utc
      ctx.output = {"Cause" => "issue", "Error" => "error"}

      expect(ctx.failed?).to eq(true)
    end
  end

  describe "#success?" do
    it "new context" do
      expect(ctx.success?).to eq(false)
    end

    it "started" do
      ctx.state["Output"] = {}

      expect(ctx.success?).to eq(false)
    end

    it "ended" do
      ctx.state["Output"] = input.dup
      ctx.execution["StartTime"] ||= Time.now.utc
      ctx.execution["EndTime"] ||= Time.now.utc

      expect(ctx.success?).to eq(true)
    end

    it "ended with error" do
      ctx.execution["StartTime"] ||= Time.now.utc
      ctx.execution["EndTime"] ||= Time.now.utc
      ctx.output = {"Cause" => "issue", "Error" => "error"}

      expect(ctx.success?).to eq(false)
    end
  end

  describe "#input" do
    it "started" do
      ctx.state["Input"] = input
      expect(ctx.input).to eq(input)
    end
  end

  describe "#output" do
    it "new context" do
      expect(ctx.output).to eq(nil)
    end

    it "ended" do
      ctx.state["Output"] = input.dup
      expect(ctx.output).to eq(input)
    end
  end

  describe "#state_name" do
    it "first context" do
      ctx.state["Name"] = "FirstState"

      expect(ctx.state_name).to eq("FirstState")
    end
  end

  describe "#next_state" do
    it "first context" do
      ctx.state["Name"] = "FirstState"
      ctx.state["NextState"] = "MiddleState"

      expect(ctx.next_state).to eq("MiddleState")
    end
  end

  describe "#status" do
    it "new context" do
      expect(ctx.status).to eq("pending")
    end

    it "started" do
      ctx.execution["StartTime"] ||= Time.now.utc

      expect(ctx.status).to eq("running")
    end

    it "ended with success" do
      ctx.execution["StartTime"] ||= Time.now.utc
      ctx.execution["EndTime"] ||= Time.now.utc

      expect(ctx.status).to eq("success")
    end

    it "ended with error" do
      ctx.execution["StartTime"] ||= Time.now.utc
      ctx.execution["EndTime"] ||= Time.now.utc
      ctx.output = {"Cause" => "issue", "Error" => "error"}

      expect(ctx.status).to eq("failure")
    end
  end
end
