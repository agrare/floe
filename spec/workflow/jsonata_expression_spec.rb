RSpec.describe Floe::Workflow::JsonataExpression do
  describe ".jsonata?" do
    it "is true for wrapped strings" do
      expect(described_class.jsonata?("{% $states.input %}")).to be true
      expect(described_class.jsonata?("{%1%}")).to be true
    end

    it "is false for unwrapped strings" do
      expect(described_class.jsonata?("$.foo")).to be false
      expect(described_class.jsonata?("{% 1")).to be false
      expect(described_class.jsonata?("1 %}")).to be false
    end

    it "is false for non strings" do
      expect(described_class.jsonata?(nil)).to be false
      expect(described_class.jsonata?(1)).to be false
      expect(described_class.jsonata?({})).to be false
    end
  end

  describe ".partial?" do
    it "is true for half wrapped strings" do
      expect(described_class.partial?("{% 1")).to be true
      expect(described_class.partial?("1 %}")).to be true
    end

    it "is false for complete expressions and plain values" do
      expect(described_class.partial?("{% 1 %}")).to be false
      expect(described_class.partial?("foo")).to be false
      expect(described_class.partial?(1)).to be false
    end
  end

  describe "#initialize" do
    it "raises for a string that is not wrapped" do
      expect { described_class.new("1 + 1") }.to raise_error(Floe::InvalidWorkflowError, /must be wrapped/)
    end

    it "raises for a syntax error" do
      expect { described_class.new("{% 1 + %}") }.to raise_error(Floe::InvalidWorkflowError, /Invalid JSONata expression/)
    end
  end

  describe "#value" do
    it "evaluates literals and arithmetic" do
      expect(described_class.new("{% 1 + 2 %}").value).to eq(3)
      expect(described_class.new("{% 'a' & 'b' %}").value).to eq("ab")
    end

    it "evaluates object and array constructors" do
      expect(described_class.new('{% {"a": [1, 2.5], "b": null} %}').value).to eq("a" => [1, 2.5], "b" => nil)
    end

    it "uses bindings" do
      bindings = {"states" => {"input" => {"foo" => 1}}, "bar" => 2}
      expect(described_class.new("{% $states.input.foo + $bar %}").value(bindings)).to eq(3)
    end

    it "returns nil for an undefined result" do
      bindings = {"states" => {"input" => {}}}
      expect(described_class.new("{% $states.input.missing %}").value(bindings)).to be_nil
    end

    it "can be evaluated repeatedly with different bindings" do
      expr = described_class.new("{% $x * 2 %}")
      expect(expr.value("x" => 1)).to eq(2)
      expect(expr.value("x" => 5)).to eq(10)
    end

    it "wraps evaluation errors" do
      expr = described_class.new('{% $number("abc") %}')
      expect { expr.value }.to raise_error(Floe::ExecutionError) do |err|
        expect(err.floe_error).to eq("States.QueryEvaluationError")
        expect(err.message).to include("Unable to cast value to a number")
      end
    end
  end
end
