RSpec.describe Floe::Workflow::Context do
  let(:ctx)         { described_class.new(:input => input.to_json) }
  let(:credentials) { {"username" => "user", "password" => "password"} }
  let(:ctx_creds)   { described_class.new(:input => input.to_json, :credentials => credentials) }
  let(:input)       { {"x" => "y"}.freeze }

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

  describe "#variables" do
    it "defaults to {}" do
      expect(ctx.variables).to eq({})
    end

    it "keeps variables from a given context" do
      ctx = described_class.new({"Variables" => {"foo" => 1}}, :input => input.to_json)
      expect(ctx.variables).to eq("foo" => 1)
    end

    it "is stored in the context" do
      ctx.variables["foo"] = 1
      expect(ctx["Variables"]).to eq("foo" => 1)
    end
  end

  describe "#states_bindings" do
    it "includes input and a context without credentials, variables and history" do
      ctx = described_class.new({"Variables" => {"foo" => 1}}, :input => input.to_json, :credentials => credentials)
      states = ctx.states_bindings({"a" => 1})["states"]

      expect(states["input"]).to eq("a" => 1)
      expect(states["context"]).to include("Execution", "State", "StateMachine", "Task")
      expect(states["context"]).not_to include("Credentials", "Variables", "StateHistory")
    end

    it "includes the variables at the top level" do
      ctx.variables["foo"] = 1

      expect(ctx.states_bindings(nil)).to include("foo" => 1, "states" => a_kind_of(Hash))
    end

    it "does not define result or errorOutput unless passed" do
      expect(ctx.states_bindings(nil)["states"].keys).to contain_exactly("input", "context")
    end

    it "defines result and errorOutput when passed" do
      states = ctx.states_bindings(nil, :result => {"r" => 1}, :error_output => {"Error" => "e"})["states"]

      expect(states).to include("result" => {"r" => 1}, "errorOutput" => {"Error" => "e"})
    end

    it "defines result when passed as nil" do
      expect(ctx.states_bindings(nil, :result => nil)["states"]).to include("result" => nil)
    end

    it "does not let variables override states" do
      ctx.variables["states"] = "bogus"

      expect(ctx.states_bindings(1)["states"]).to include("input" => 1)
    end
  end

  describe "#child_context" do
    it "copies the variables" do
      ctx.variables["foo"] = {"a" => 1}
      child = ctx.child_context("x")

      expect(child.variables).to eq("foo" => {"a" => 1})
    end

    it "does not share the variables with the parent" do
      ctx.variables["foo"] = {"a" => 1}
      child = ctx.child_context("x")
      child.variables["foo"]["a"] = 2
      child.variables["bar"] = 3

      expect(ctx.variables).to eq("foo" => {"a" => 1})
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

  describe "#inspect" do
    it "has the same value with or without credentials" do
      # removing spaces because Hash#inspect in ruby 3.4 adds spaces that are not present before
      expect(ctx.inspect.delete(" ")).to eq("#<Floe::Workflow::Context: {\"Execution\" => {\"Input\" => {\"x\" => \"y\"}}, \"State\" => {}, \"StateHistory\" => [], \"StateMachine\" => {}, \"Task\" => {}, \"Variables\" => {}}>".delete(" "))
      expect(ctx_creds.inspect.delete(" ")).to eq("#<Floe::Workflow::Context: {\"Execution\" => {\"Input\" => {\"x\" => \"y\"}}, \"State\" => {}, \"StateHistory\" => [], \"StateMachine\" => {}, \"Task\" => {}, \"Variables\" => {}}>".delete(" "))
    end

    it "doesn't expose credentials" do
      expect(ctx_creds.inspect).not_to include("password")
    end
  end

  describe "#to_h" do
    it "doesn't expose credentials" do
      expect(ctx_creds.to_h).not_to include("Credentials")
    end

    describe "#==" do
      it "compares with values" do
        ctx1 = described_class.new(:input => input.to_json)
        ctx2 = described_class.new(:input => input.to_json)

        expect(ctx1 == ctx2).to eq(true)
      end

      it "compares with passwords" do
        ctx1 = described_class.new(:input => input.to_json, :credentials => credentials)
        ctx2 = described_class.new(:input => input.to_json, :credentials => credentials)

        expect(ctx1 == ctx2).to eq(true)
      end

      it "detects different passwords" do
        ctx1 = described_class.new(:input => input.to_json, :credentials => credentials)
        ctx2 = described_class.new(:input => input.to_json)

        expect(ctx1 == ctx2).not_to eq(true)
      end
    end

    describe "#eql?" do
      it "compares with values" do
        ctx1 = described_class.new(:input => input.to_json)
        ctx2 = described_class.new(:input => input.to_json)

        expect(ctx1.eql?(ctx2)).to eq(true)
      end

      it "compares with passwords" do
        ctx1 = described_class.new(:input => input.to_json, :credentials => credentials)
        ctx2 = described_class.new(:input => input.to_json, :credentials => credentials)

        expect(ctx1.eql?(ctx2)).to eq(true)
      end

      it "detects different passwords" do
        ctx1 = described_class.new(:input => input.to_json, :credentials => credentials)
        ctx2 = described_class.new(:input => input.to_json)

        expect(ctx1.eql?(ctx2)).not_to eq(true)
      end
    end

    describe "#hash" do
      it "compares with identical contexts" do
        ctx1 = described_class.new(:input => input.to_json)
        ctx2 = described_class.new(:input => input.to_json)
        expect(ctx1.hash).to eq(ctx2.hash)
      end

      it "compares with different contexts" do
        ctx1 = described_class.new(:input => input.to_json)
        ctx2 = described_class.new(:input => input.to_json, :credentials => credentials)
        expect(ctx1.hash).not_to eq(ctx2.hash)
      end
    end
  end
end
