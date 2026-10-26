RSpec.describe Floe::Workflow::States::Succeed do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:payload)  { {"SuccessState" => {"Type" => "Succeed"}} }
  let(:workflow) { make_workflow(ctx, payload) }

  it "#end?" do
    expect(state.end?).to be true
  end

  describe "#run_nonblock!" do
    it "has no next" do
      state.run_nonblock!(ctx)
      expect(ctx.next_state).to eq(nil)
    end

    context "with input" do
      let(:input) { {"color" => "red"} }

      it "sets output to input" do
        state.run_nonblock!(ctx)
        expect(ctx.output).to eq(input)
      end

      context "with InputPath" do
        let(:payload) { {"SuccessState" => {"Type" => "Succeed", "InputPath" => "$.color"}} }

        it "sets the output to the selected input path" do
          state.run_nonblock!(ctx)
          expect(ctx.output).to eq(input["color"])
        end
      end

      context "with OutputPath" do
        let(:input)   { {"color" => "red", "garbage" => nil} }
        let(:payload) { {"SuccessState" => {"Type" => "Succeed", "OutputPath" => "$.color"}} }

        it "sets the output to the selected input path" do
          state.run_nonblock!(ctx)
          expect(ctx.output).to eq(input["color"])
        end
      end
    end
  end
end

RSpec.describe Floe::Workflow::States::Succeed, "with QueryLanguage JSONata" do
  let(:input)    { {"color" => "red"} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { {"Type" => "Succeed", "QueryLanguage" => "JSONata"} }
  let(:workflow) { make_workflow(ctx, {"SuccessState" => state}) }

  describe "#initialize" do
    %w[InputPath OutputPath].each do |field|
      context "with #{field}" do
        before { state[field] = "$" }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.SuccessState field \"#{field}\" is not allowed when QueryLanguage is \"JSONata\"") }
      end
    end

    %w[Output Assign].each do |field|
      context "with #{field} in a JSONPath state" do
        let(:state) { {"Type" => "Succeed", field => {}} }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.SuccessState field \"#{field}\" is not allowed when QueryLanguage is \"JSONPath\"") }
      end
    end
  end

  describe "#run_nonblock!" do
    it "defaults the output to the input" do
      workflow.run_nonblock

      expect(ctx.output).to eq(input)
      expect(ctx.next_state).to be_nil
      expect(ctx.status).to eq("success")
    end

    context "with Output" do
      before { state["Output"] = {"c" => "{% $states.input.color %}"} }

      it "evaluates the Output" do
        workflow.run_nonblock

        expect(ctx.output).to eq("c" => "red")
      end
    end

    context "with Assign" do
      before { state["Assign"] = {"c" => "{% $states.input.color %}"} }

      it "sets the variables" do
        workflow.run_nonblock

        expect(ctx.variables).to eq("c" => "red")
        expect(ctx.output).to eq(input)
      end
    end

    context "with an Output which fails" do
      before { state["Output"] = "{% $number('x') %}" }

      it "fails the workflow" do
        workflow.run_nonblock

        expect(ctx.status).to eq("failure")
        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
      end
    end
  end
end
