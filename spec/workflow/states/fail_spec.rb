RSpec.describe Floe::Workflow::States::Fail do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:workflow) do
    make_workflow(
      ctx, {
        "FailState" => {
          "Type"  => "Fail",
          "Error" => "FailStateError",
          "Cause" => "No Matches!"
        }
      }
    )
  end

  it "#end?" do
    expect(state.end?).to be true
  end

  describe "#run_nonblock!" do
    it "populates static values" do
      state.run_nonblock!(ctx)
      expect(ctx.next_state).to eq(nil)
      expect(ctx.output).to eq("Error" => "FailStateError", "Cause" => "No Matches!")
    end

    context "with dynamic error text" do
      let(:input) { {"output" => "xyz", "error_message" => "DynamicError", "cause_message" => "DynamicCause"} }
      let(:workflow) do
        make_workflow(
          ctx, {
            "FailState" => {
              "Type"      => "Fail",
              "ErrorPath" => "$.error_message",
              "CausePath" => "$.cause_message"
            }
          }
        )
      end

      it "populates dynamic values" do
        state.run_nonblock!(ctx)
        expect(ctx.next_state).to eq(nil)
        expect(ctx.output).to eq("Error" => "DynamicError", "Cause" => "DynamicCause")
      end
    end
  end
end

RSpec.describe Floe::Workflow::States::Fail, "with QueryLanguage JSONata" do
  let(:input)    { {"error_message" => "DynamicError", "cause_message" => "DynamicCause"} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { {"Type" => "Fail", "QueryLanguage" => "JSONata", "Error" => "StaticError", "Cause" => "StaticCause"} }
  let(:workflow) { make_workflow(ctx, {"FailState" => state}) }

  describe "#initialize" do
    %w[ErrorPath CausePath].each do |field|
      context "with #{field}" do
        before { state[field] = "$.foo" }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.FailState field \"#{field}\" is not allowed when QueryLanguage is \"JSONata\"") }
      end
    end

    context "with an invalid expression" do
      before { state["Error"] = "{% ( %}" }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /Invalid JSONata expression/) }
    end
  end

  describe "#run_nonblock!" do
    it "populates static values" do
      workflow.run_nonblock

      expect(ctx.next_state).to be_nil
      expect(ctx.status).to eq("failure")
      expect(ctx.output).to eq("Error" => "StaticError", "Cause" => "StaticCause")
    end

    context "with expressions" do
      before do
        state["Error"] = "{% $states.input.error_message %}"
        state["Cause"] = "{% 'Cause: ' & $states.input.cause_message & ' ' & $suffix %}"
        ctx.variables["suffix"] = "!"
      end

      it "evaluates them" do
        workflow.run_nonblock

        expect(ctx.output).to eq("Error" => "DynamicError", "Cause" => "Cause: DynamicCause !")
      end
    end

    context "without a Cause" do
      before { state.delete("Cause") }

      it "omits it" do
        workflow.run_nonblock

        expect(ctx.output).to eq("Error" => "StaticError")
      end
    end

    context "with an expression which is undefined" do
      before { state["Cause"] = "{% $states.input.missing %}" }

      it "omits it" do
        workflow.run_nonblock

        expect(ctx.output).to eq("Error" => "StaticError")
      end
    end

    context "with an expression which fails" do
      before { state["Error"] = "{% $number('x') %}" }

      it "fails with States.QueryEvaluationError" do
        workflow.run_nonblock

        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
      end
    end
  end
end
