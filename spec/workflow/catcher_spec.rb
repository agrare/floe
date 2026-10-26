RSpec.describe Floe::Workflow::Catcher do
  let(:input)    { {"foo" => "bar"} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:error)    { {"Error" => "States.Timeout", "Cause" => "too slow"} }
  let(:workflow) { make_workflow(ctx, {"Start" => {"Type" => "Succeed"}, "Recover" => {"Type" => "Succeed"}}) }
  let(:payload)  { {"ErrorEquals" => ["States.Timeout"], "Next" => "Recover"} }
  let(:language) { "JSONPath" }
  let(:subject)  { described_class.new(workflow, %w[States Start Catch 0], payload, :query_language => language) }

  before { ctx.state["Input"] = input }

  describe "#initialize" do
    it "requires ErrorEquals" do
      payload.delete("ErrorEquals")

      expect { subject }.to raise_error(Floe::InvalidWorkflowError, /does not have required field "ErrorEquals"/)
    end

    it "requires a Next" do
      payload.delete("Next")

      expect { subject }.to raise_error(Floe::InvalidWorkflowError, /does not have required field "Next"/)
    end

    it "requires Next to be a state" do
      payload["Next"] = "Missing"

      expect { subject }.to raise_error(Floe::InvalidWorkflowError, /field "Next" value "Missing" is not found in "States"/)
    end

    context "with JSONPath" do
      %w[Output Assign].each do |field|
        it "does not allow #{field}" do
          payload[field] = {}

          expect { subject }.to raise_error(Floe::InvalidWorkflowError, "States.Start.Catch.0 field \"#{field}\" is not allowed when QueryLanguage is \"JSONPath\"")
        end
      end
    end

    context "with JSONata" do
      let(:language) { "JSONata" }

      it "does not allow ResultPath" do
        payload["ResultPath"] = "$.error"

        expect { subject }.to raise_error(Floe::InvalidWorkflowError, "States.Start.Catch.0 field \"ResultPath\" value \"$.error\" is not allowed when QueryLanguage is \"JSONata\"")
      end

      it "requires Assign to be an object" do
        payload["Assign"] = "{% 1 %}"

        expect { subject }.to raise_error(Floe::InvalidWorkflowError, /field "Assign".*must be an object/)
      end

      it "validates the expressions" do
        payload["Output"] = "{% ( %}"

        expect { subject }.to raise_error(Floe::InvalidWorkflowError, /Invalid JSONata expression/)
      end
    end
  end

  describe "#process_output" do
    context "with JSONPath" do
      it "sets the error in the input at the default ResultPath" do
        expect(subject.process_output(ctx, error)).to eq(error)
      end

      it "sets the error in the input at ResultPath" do
        payload["ResultPath"] = "$.error"

        expect(subject.process_output(ctx, error)).to eq("foo" => "bar", "error" => error)
      end
    end

    context "with JSONata" do
      let(:language) { "JSONata" }

      it "defaults to the error" do
        expect(subject.process_output(ctx, error)).to eq(error)
        expect(ctx.variables).to eq({})
      end

      it "uses Output with $states.errorOutput and $states.input" do
        payload["Output"] = {"e" => "{% $states.errorOutput.Error %}", "in" => "{% $states.input.foo %}"}

        expect(subject.process_output(ctx, error)).to eq("e" => "States.Timeout", "in" => "bar")
      end

      it "sets the variables with Assign" do
        payload["Assign"] = {"cause" => "{% $states.errorOutput.Cause %}"}

        expect(subject.process_output(ctx, error)).to eq(error)
        expect(ctx.variables).to eq("cause" => "too slow")
      end

      it "does not set variables if Output fails" do
        payload["Assign"] = {"cause" => "{% $states.errorOutput.Cause %}"}
        payload["Output"] = "{% $number('x') %}"

        expect { subject.process_output(ctx, error) }.to raise_error(Floe::ExecutionError)
        expect(ctx.variables).to eq({})
      end
    end
  end
end
