RSpec.describe Floe::Workflow::States::Choice do
  let(:ctx)  { Floe::Workflow::Context.new(input: input) }
  let(:workflow) { Floe::Workflow.load(GEM_ROOT.join("examples/workflow.asl"), ctx) }
  let(:state)    { workflow.states_by_name["ChoiceState"] }
  let(:input)    { {} }

  it "#end?" do
    expect(state.end?).to eq(false)
  end

  describe "#run!" do
    let(:subject) { state.run!(input) }

    context "with a missing variable" do
      it "raises an exception" do
        expect { subject }.to raise_error(RuntimeError, "No such variable [$.foo]")
      end
    end

    context "with an input value matching a condition" do
      let(:input) { {"foo" => 1} }

      it "returns the next state" do
        subject
        expect(ctx.next_state).to eq("FirstMatchState")
      end
    end

    context "with an input value not matching any condition" do
      let(:input) { {"foo" => 4} }

      it "returns the default state" do
        subject
        expect(ctx.next_state).to eq("FailState")
      end
    end
  end
end
