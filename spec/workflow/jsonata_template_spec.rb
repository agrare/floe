RSpec.describe Floe::Workflow::JsonataTemplate do
  let(:ctx)      { Floe::Workflow::Context.new(:input => {}.to_json) }
  let(:input)    { {"foo" => "bar", "num" => 2, "list" => [1, 2, 3]} }
  let(:bindings) { ctx.states_bindings(input) }

  def evaluate(payload, name = nil)
    described_class.new(payload, name).value(bindings)
  end

  describe "#value" do
    it "passes through static values" do
      expect(evaluate("foo")).to eq("foo")
      expect(evaluate(1)).to eq(1)
      expect(evaluate(1.5)).to eq(1.5)
      expect(evaluate(true)).to be true
      expect(evaluate(nil)).to be_nil
    end

    it "evaluates a top level expression" do
      expect(evaluate("{% $states.input.foo %}")).to eq("bar")
    end

    it "evaluates expressions in a hash" do
      expect(evaluate("a" => "{% $states.input.num + 1 %}", "b" => "static")).to eq("a" => 3, "b" => "static")
    end

    it "evaluates expressions in an array" do
      expect(evaluate(["{% $sum($states.input.list) %}", 1])).to eq([6, 1])
    end

    it "evaluates expressions in nested structures" do
      payload = {"a" => {"b" => ["{% $states.input.foo %}", {"c" => "{% $states.input.num %}"}]}}

      expect(evaluate(payload)).to eq("a" => {"b" => ["bar", {"c" => 2}]})
    end

    it "does not treat .$ keys specially" do
      expect(evaluate("a.$" => "$.foo")).to eq("a.$" => "$.foo")
    end

    it "can return objects and arrays from an expression" do
      expect(evaluate("{% $states.input.list %}")).to eq([1, 2, 3])
      expect(evaluate("{% {'x': $states.input.num} %}")).to eq("x" => 2)
    end

    it "evaluates undefined as nil" do
      expect(evaluate("a" => "{% $states.input.missing %}")).to eq("a" => nil)
    end

    it "uses variables" do
      ctx.variables["myvar"] = 10

      expect(evaluate("{% $myvar * $states.input.num %}")).to eq(20)
    end

    it "uses $states.result and $states.errorOutput when provided" do
      bindings = ctx.states_bindings(input, :result => {"r" => 1}, :error_output => {"Error" => "boom"})
      template = described_class.new("res" => "{% $states.result.r %}", "err" => "{% $states.errorOutput.Error %}")

      expect(template.value(bindings)).to eq("res" => 1, "err" => "boom")
    end

    it "does not modify the template between evaluations" do
      template = described_class.new("a" => "{% $states.input.num %}")

      expect(template.value(ctx.states_bindings({"num" => 1}))).to eq("a" => 1)
      expect(template.value(ctx.states_bindings({"num" => 2}))).to eq("a" => 2)
    end

    it "raises an ExecutionError for a runtime error" do
      template = described_class.new("a" => '{% $number("abc") %}')

      expect { template.value(bindings) }.to raise_error(Floe::ExecutionError) { |err| expect(err.floe_error).to eq("States.QueryEvaluationError") }
    end
  end

  describe "#initialize" do
    it "raises for an invalid expression" do
      expect { described_class.new("a" => "{% 1 + %}") }.to raise_error(Floe::InvalidWorkflowError, /Invalid JSONata expression/)
    end

    it "raises for a nested invalid expression" do
      expect { described_class.new("a" => [{"b" => "{% ( %}"}]) }.to raise_error(Floe::InvalidWorkflowError, /Invalid JSONata expression/)
    end

    it "raises for a string which only has a start delimiter" do
      expect { described_class.new(["{% 1"], %w[States Foo Output]) }
        .to raise_error(Floe::InvalidWorkflowError, /States.Foo.Output value "\{% 1" is not a valid JSONata expression/)
    end

    it "raises for a string which only has an end delimiter" do
      expect { described_class.new("1 %}") }.to raise_error(Floe::InvalidWorkflowError, /not a valid JSONata expression/)
    end
  end
end
