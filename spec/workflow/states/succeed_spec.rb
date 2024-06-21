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
