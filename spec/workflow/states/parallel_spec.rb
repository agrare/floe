RSpec.describe Floe::Workflow::States::Parallel do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:workflow) do
    payload = {
      "FunWithMath" => {
        "Type"     => "Parallel",
        "Branches" => [
          {
            "StartAt" => "Add",
            "States"  => {
              "Add" => {
                "Type" => "Pass",
                "End"  => true
              }
            }
          },
          {
            "StartAt" => "Subtract",
            "States"  => {
              "Subtract" => {
                "Type" => "Pass",
                "End"  => true
              }
            }
          }
        ],
        "Next"     => "NextState"
      },
      "NextState"   => {
        "Type" => "Succeed"
      }
    }

    make_workflow(ctx, payload)
  end

  describe "#initialize" do
    it "builds the Parallel state object" do
      expect { workflow }.not_to raise_error
    end

    it "raises an InvalidWorkflowError with a missing Branches parameter" do
      payload = {
        "FunWithMath" => {
          "Type" => "Parallel",
          "End"  => true
        }
      }

      expect { make_workflow(ctx, payload) }
        .to raise_error(Floe::InvalidWorkflowError, "States.FunWithMath does not have required field \"Branches\"")
    end

    it "raises an InvalidWorkflowError with a missing Next and End" do
      payload = {
        "FunWithMath" => {
          "Type"     => "Parallel",
          "Branches" => [
            {
              "StartAt" => "Add",
              "States"  => {
                "Add" => {
                  "Type" => "Pass",
                  "End"  => true
                }
              }
            }
          ]
        }
      }

      expect { make_workflow(ctx, payload) }
        .to raise_error(Floe::InvalidWorkflowError, "States.FunWithMath does not have required field \"Next\"")
    end

    it "raises an InvalidWorkflowError if a state in a Branch attempts to transition to a state in the outer workflow" do
      payload = {
        "FunWithMath"  => {
          "Type"     => "Parallel",
          "Branches" => [
            {
              "StartAt" => "Add",
              "States"  => {
                "Add" => {
                  "Type" => "Pass",
                  "Next" => "PassState"
                }
              }
            }
          ],
          "Next"     => "PassState"
        },
        "PassState"    => {
          "Type" => "Pass",
          "Next" => "SucceedState"
        },
        "SucceedState" => {
          "Type" => "Succeed"
        }
      }

      expect { make_workflow(ctx, payload) }
        .to raise_error(Floe::InvalidWorkflowError, "States.Add field \"Next\" value \"PassState\" is not found in \"States\"")
    end

    it "raises an InvalidWorkflowError if a state in a Branch attemps to transition to a state in another branch" do
      payload = {
        "FunWithMath"  => {
          "Type"     => "Parallel",
          "Branches" => [
            {
              "StartAt" => "Add",
              "States"  => {
                "Add" => {
                  "Type" => "Pass",
                  "Next" => "Subtract"
                }
              }
            },
            {
              "StartAt" => "Subtract",
              "States"  => {
                "Add" => {
                  "Type" => "Pass",
                  "End"  => true
                }
              }
            }
          ],
          "Next"     => "PassState"
        },
        "PassState"    => {
          "Type" => "Pass",
          "Next" => "SucceedState"
        },
        "SucceedState" => {
          "Type" => "Succeed"
        }
      }

      expect { make_workflow(ctx, payload) }
        .to raise_error(Floe::InvalidWorkflowError, "States.Add field \"Next\" value \"Subtract\" is not found in \"States\"")
    end
  end

  it "#end?" do
    expect(state.end?).to be false
  end

  describe "#start" do
  end

  describe "#finish" do
  end

  describe "#run_nonblock!" do
  end

  describe "#ready?" do
  end

  describe "#running?" do
    before { state.start(ctx) }

    context "with all branches ended" do
      before { ctx.state["BranchContext"].each { |ctx| ctx["Execution"]["EndTime"] = Time.now.utc } }

      it "returns false" do
        expect(state.running?(ctx)).to be_falsey
      end
    end

    context "with some branches not ended" do
      before { ctx.state["BranchContext"][0]["Execution"]["EndTime"] = Time.now.utc }

      it "returns true" do
        expect(state.running?(ctx)).to be_truthy
      end
    end
  end

  describe "#waiting?" do
  end

  describe "#wait_until" do
  end

  describe "#success?" do
  end
end
