RSpec.describe Floe::Workflow::States::Parallel do
  let(:input)    { [3, 2] }
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
                "Type"       => "Pass",
                "Parameters" => {"result.$" => "States.MathAdd($.[0], $.[1])"},
                "OutputPath" => "$.result",
                "End"        => true
              }
            }
          },
          {
            "StartAt" => "ArrayLength",
            "States"  => {
              "ArrayLength" => {
                "Type"       => "Pass",
                "Parameters" => {"result.$" => "States.ArrayLength($.)"},
                "OutputPath" => "$.result",
                "End"        => true
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
    it "initializes branch context for each branch" do
      state.start(ctx)
      expect(ctx.state["BranchContext"].length).to eq(2)
    end

    it "copies the execution id into the branch contexts" do
      state.start(ctx)

      expect(ctx.state.dig("BranchContext", 0, "Execution", "Id")).to eq(ctx.dig("Execution", "Id"))
      expect(ctx.state.dig("BranchContext", 1, "Execution", "Id")).to eq(ctx.dig("Execution", "Id"))
    end

    it "copies the state input into the branch contexts" do
      state.start(ctx)

      expect(ctx.state.dig("BranchContext", 0, "Execution", "Input")).to eq(ctx.dig("State", "Input"))
      expect(ctx.state.dig("BranchContext", 1, "Execution", "Input")).to eq(ctx.dig("State", "Input"))
    end

    context "with Execution context containing StartTime, EndTime, and other keys" do
      # Force `state` to be evaluated (triggering start_workflow / prepare_start)
      # before adding extra keys to execution, so that prepare_start does not
      # return early due to StartTime already being present.
      before do
        state # evaluate lazy let
        ctx.execution["EndTime"] = "2024-01-01T01:00:00Z"
        ctx.execution["RoleArn"] = "arn:aws:iam::123456789012:role/MyRole"
      end

      it "does not copy StartTime into the branch execution context" do
        state.start(ctx)

        expect(ctx.state.dig("BranchContext", 0, "Execution")).not_to have_key("StartTime")
        expect(ctx.state.dig("BranchContext", 1, "Execution")).not_to have_key("StartTime")
      end

      it "does not copy EndTime into the branch execution context" do
        state.start(ctx)

        expect(ctx.state.dig("BranchContext", 0, "Execution")).not_to have_key("EndTime")
        expect(ctx.state.dig("BranchContext", 1, "Execution")).not_to have_key("EndTime")
      end

      it "does not copy the parent Execution Input into the branch execution context" do
        ctx.execution["Input"] = {"original" => "workflow-input"}
        state.start(ctx)

        expect(ctx.state.dig("BranchContext", 0, "Execution", "Input")).not_to eq({"original" => "workflow-input"})
        expect(ctx.state.dig("BranchContext", 1, "Execution", "Input")).not_to eq({"original" => "workflow-input"})
      end

      it "copies other execution keys into the branch execution context" do
        state.start(ctx)

        expect(ctx.state.dig("BranchContext", 0, "Execution", "RoleArn")).to eq("arn:aws:iam::123456789012:role/MyRole")
        expect(ctx.state.dig("BranchContext", 1, "Execution", "RoleArn")).to eq("arn:aws:iam::123456789012:role/MyRole")
      end
    end
  end

  describe "#finish" do
    before { state.start(ctx) }

    context "with all successful branches" do
      before do
        ctx.state["BranchContext"][0]["State"] = {"Output" => {"foo" => "bar"}}
        ctx.state["BranchContext"][1]["State"] = {"Output" => 2}
      end

      it "sets the state output to an array of the branch output" do
        state.finish(ctx)

        expect(ctx.failed?).to be_falsey
        expect(ctx.output).to eq([{"foo" => "bar"}, 2])
      end
    end

    context "with one failed branch" do
      before do
        ctx.state["BranchContext"][0]["State"] = {"Output" => {"foo" => "bar"}}
        ctx.state["BranchContext"][1]["State"] = {"Output" => {"Error" => "States.TaskFailed"}}
      end

      it "sets the state as failed" do
        state.finish(ctx)

        expect(ctx.failed?).to be_truthy
        expect(ctx.output).to  eq("Error" => "States.TaskFailed")
      end
    end
  end

  describe "#run_nonblock!" do
    it "sets next to NextState" do
      loop while state.run_nonblock!(ctx) != 0
      expect(ctx.next_state).to eq("NextState")
    end

    it "sets the context output to array of branch outputs" do
      loop while state.run_nonblock!(ctx) != 0
      expect(ctx.output).to eq([5, 2])
    end
  end

  describe "#ready?" do
    context "before the state has started" do
      it "returns truthy" do
        expect(state.ready?(ctx)).to be_truthy
      end
    end

    context "with the state started" do
      before { state.start(ctx) }

      context "before the branches have started" do
        it "returns truthy" do
          expect(state.ready?(ctx)).to be_truthy
        end
      end
    end
  end

  describe "#running?" do
    before { state.start(ctx) }

    context "with one branch not ended" do
      before { ctx.state["BranchContext"][0]["Execution"]["EndTime"] = Time.now.utc }

      it "returns truthy" do
        expect(state.running?(ctx)).to be_truthy
      end
    end

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
    context "with no branches waiting" do
      it "returns falsey" do
        expect(state.waiting?(ctx)).to be_falsey
      end
    end

    context "with one branch waiting" do
      before do
        state.start(ctx)
        ctx.state["BranchContext"][0]["State"]["Name"]      = "Add"
        ctx.state["BranchContext"][0]["State"]["WaitUntil"] = (Time.now + 3_600).iso8601
      end

      it "returns truthy" do
        expect(state.waiting?(ctx)).to be_truthy
      end
    end

    context "with one branch done waiting" do
      before do
        state.start(ctx)
        ctx.state["BranchContext"][0]["State"]["Name"]      = "Add"
        ctx.state["BranchContext"][0]["State"]["WaitUntil"] = (Time.now - 3_600).iso8601
      end

      it "returns falsey" do
        expect(state.waiting?(ctx)).to be_falsey
      end
    end
  end

  describe "#wait_until" do
    context "with no branches waiting" do
      it "returns falsey" do
        expect(state.wait_until(ctx)).to be_falsey
      end
    end

    context "with one branch waiting" do
      let(:wait_until) { (Time.now + 3_600).iso8601 }

      before do
        state.start(ctx)
        ctx.state["BranchContext"][0]["State"]["Name"]      = "Add"
        ctx.state["BranchContext"][0]["State"]["WaitUntil"] = wait_until
      end

      it "returns the time to wait until" do
        expect(state.wait_until(ctx)).to eq(Time.parse(wait_until))
      end
    end
  end

  describe "#success?" do
    before { state.start(ctx) }

    context "with all successful branches" do
      before do
        ctx.state["BranchContext"][0]["State"] = {"Output" => {"foo" => "bar"}}
        ctx.state["BranchContext"][1]["State"] = {"Output" => 2}
      end

      it "returns truthy" do
        expect(state.success?(ctx)).to be_truthy
      end
    end

    context "with one failed branch" do
      before do
        ctx.state["BranchContext"][0]["State"] = {"Output" => {"foo" => "bar"}}
        ctx.state["BranchContext"][1]["State"] = {"Output" => {"Error" => "States.TaskFailed"}}
      end

      it "returns falsey" do
        expect(state.success?(ctx)).to be_falsey
      end
    end
  end
end
