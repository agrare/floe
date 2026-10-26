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

RSpec.describe Floe::Workflow::States::Parallel, "with QueryLanguage JSONata" do
  let(:input)    { {"a" => 3, "b" => 2} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:workflow) { make_workflow(ctx, payload) }
  let(:branches) do
    [
      {"StartAt" => "Add", "States" => {"Add" => {"Type" => "Pass", "End" => true, "Output" => "{% $states.input.a + $states.input.b %}"}}},
      {"StartAt" => "Mul", "States" => {"Mul" => {"Type" => "Pass", "End" => true, "Output" => "{% $states.input.a * $states.input.b %}"}}}
    ]
  end
  let(:parallel) { {"Type" => "Parallel", "QueryLanguage" => "JSONata", "Branches" => branches, "End" => true} }
  let(:payload)  { {"ParallelState" => parallel} }

  def run_workflow
    workflow.run_nonblock
    workflow
  end

  describe "#initialize" do
    %w[Parameters InputPath OutputPath ResultPath ResultSelector].each do |field|
      context "with #{field}" do
        before { parallel[field] = "$" }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.ParallelState field \"#{field}\" is not allowed when QueryLanguage is \"JSONata\"") }
      end
    end

    context "with Arguments in a JSONPath state" do
      let(:parallel) { {"Type" => "Parallel", "Branches" => [], "End" => true, "Arguments" => {}} }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.ParallelState field \"Arguments\" is not allowed when QueryLanguage is \"JSONPath\"") }
    end

    it "gives the branches the QueryLanguage of the state" do
      expect(workflow.states.first.branches.map(&:query_language)).to eq(%w[JSONata JSONata])
    end

    context "when the state overrides the workflow QueryLanguage" do
      let(:workflow) { Floe::Workflow.new({"QueryLanguage" => "JSONPath", "StartAt" => "ParallelState", "States" => payload}, ctx) }

      it "gives the branches the QueryLanguage of the state" do
        expect(workflow.states.first.branches.map(&:query_language)).to eq(%w[JSONata JSONata])
        expect(workflow.states.first.branches.first.states.first).to be_jsonata
      end
    end
  end

  describe "#run_nonblock" do
    it "defaults the output to the results of the branches" do
      expect(run_workflow.output).to eq("[5,6]")
    end

    context "with Arguments" do
      before { parallel["Arguments"] = {"a" => "{% $states.input.a + 10 %}", "b" => "{% $states.input.b %}"} }

      it "is the input of the branches" do
        expect(run_workflow.output).to eq("[15,26]")
      end
    end

    context "with Output" do
      before { parallel["Output"] = {"sum" => "{% $states.result[0] %}", "product" => "{% $states.result[1] %}", "orig" => "{% $states.input.a %}"} }

      it "can use $states.result and $states.input" do
        expect(JSON.parse(run_workflow.output)).to eq("sum" => 5, "product" => 6, "orig" => 3)
      end
    end

    context "with Assign" do
      before { parallel["Assign"] = {"results" => "{% $states.result %}"} }

      it "sets the variables" do
        run_workflow

        expect(ctx.variables).to eq("results" => [5, 6])
      end
    end

    context "with variables in the parent" do
      let(:branches) do
        [{"StartAt" => "Read", "States" => {"Read" => {"Type" => "Pass", "End" => true, "Output" => "{% $myvar %}", "Assign" => {"myvar" => "changed"}}}}]
      end

      before { ctx.variables["myvar"] = "parent" }

      it "can read them in the branches but not change them" do
        expect(run_workflow.output).to eq(["parent"].to_json)
        expect(ctx.variables).to eq("myvar" => "parent")
      end
    end

    context "with a failing branch" do
      let(:branches) { [{"StartAt" => "Boom", "States" => {"Boom" => {"Type" => "Fail", "Error" => "Boom"}}}] }

      it "fails with the error of the branch" do
        run_workflow

        expect(ctx.status).to eq("failure")
        expect(ctx.output).to eq("Error" => "Boom")
      end

      context "with a Catch" do
        let(:payload) do
          {
            "ParallelState" => parallel.merge("End" => nil, "Next" => "Recover", "Catch" => [{"ErrorEquals" => ["Boom"], "Next" => "Recover", "Assign" => {"caught" => "{% $states.errorOutput.Error %}"}}]),
            "Recover"       => {"Type" => "Pass", "QueryLanguage" => "JSONata", "End" => true}
          }
        end

        it "defaults the Output to $states.errorOutput" do
          run_workflow

          expect(ctx.state_history.first["NextState"]).to eq("Recover")
          expect(ctx.state_history.first["Output"]).to eq("Error" => "Boom")
          expect(ctx.variables).to eq("caught" => "Boom")
        end
      end
    end

    context "with an Output expression which fails" do
      before { parallel["Output"] = "{% $number('abc') %}" }

      it "fails with States.QueryEvaluationError" do
        run_workflow

        expect(ctx.status).to eq("failure")
        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
      end

      it "can be caught" do
        parallel["Catch"] = [{"ErrorEquals" => ["States.QueryEvaluationError"], "Next" => "Recover", "Output" => "recovered"}]
        parallel["Next"]  = "Recover"
        parallel.delete("End")
        payload["Recover"] = {"Type" => "Pass", "QueryLanguage" => "JSONata", "End" => true}
        run_workflow

        expect(ctx.status).to eq("success")
        expect(workflow.output).to eq("\"recovered\"")
      end
    end
  end
end
