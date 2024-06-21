RSpec.describe Floe::Workflow::States::Choice do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:workflow) do
    make_workflow(
      ctx, {
        "ChoiceState"      => {
          "Type"    => "Choice",
          "Choices" => [
            {
              "Variable"      => "$.foo",
              "NumericEquals" => 1,
              "Next"          => "FirstMatchState"
            },
            {
              "Variable"      => "$.foo",
              "NumericEquals" => 2,
              "Next"          => "SecondMatchState"
            },
          ],
          "Default" => "DefaultState"
        },
        "FirstMatchState"  => {"Type" => "Succeed"},
        "SecondMatchState" => {"Type" => "Succeed"},
        "DefaultState"     => {"Type" => "Succeed"}
      }
    )
  end

  it "raises an exception if Choices is missing" do
    payload = {"Choice1" => {"Type" => "Choice", "Default" => "DefaultState"}, "DefaultState" => {"type" => "Succeed"}}
    expect { make_workflow(ctx, payload) }.to raise_error(Floe::InvalidWorkflowError, "Choice state must have \"Choices\"")
  end

  it "raises an exception if Choices is not an array" do
    payload = {"Choice1" => {"Type" => "Choice", "Choices" => {}, "Default" => "DefaultState"}, "DefaultState" => {"type" => "Succeed"}}
    expect { make_workflow(ctx, payload) }.to raise_error(Floe::InvalidWorkflowError, "\"Choices\" must be a non-empty array")
  end

  it "raises an exception if Choices is an empty array" do
    payload = {"Choice1" => {"Type" => "Choice", "Choices" => [], "Default" => "DefaultState"}, "DefaultState" => {"type" => "Succeed"}}
    expect { make_workflow(ctx, payload) }.to raise_error(Floe::InvalidWorkflowError, "\"Choices\" must be a non-empty array")
  end

  it "raises an exception if Default isn't a valid state" do
    payload = {"Choice1" => {"Type" => "Choice", "Choices" => [{"Variable" => "$.foo", "NumericEquals" => 1, "Next" => "FirstMatchState"}], "Default" => "MissingState"}, "FirstMatchState" => {"Type" => "Success"}}
    expect { make_workflow(ctx, payload) }.to raise_error(Floe::InvalidWorkflowError, "\"Default\" not in \"States\"")
  end

  it "#end?" do
    expect(state.end?).to eq(false)
  end

  describe "#run_nonblock!" do
    context "with a missing variable" do
      it "raises an exception" do
        expect { state.run_nonblock!(ctx) }.to raise_error(RuntimeError, "No such variable [$.foo]")
      end
    end

    context "with an input value matching a condition" do
      let(:input) { {"foo" => 1} }

      it "returns the next state" do
        state.run_nonblock!(ctx)
        expect(ctx.next_state).to eq("FirstMatchState")
      end
    end

    context "with an input value not matching any condition" do
      let(:input) { {"foo" => 4} }

      it "returns the default state" do
        state.run_nonblock!(ctx)
        expect(ctx.next_state).to eq("DefaultState")
      end
    end
  end
end
