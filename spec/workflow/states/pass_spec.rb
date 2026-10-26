RSpec.describe Floe::Workflow::States::Pass do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:workflow) { make_workflow(ctx, payload) }
  let(:payload) do
    {
      "PassState"    => {
        "Type"       => "Pass",
        "Result"     => {
          "foo" => "bar",
          "bar" => "baz"
        },
        "ResultPath" => "$.result",
        "Next"       => "SuccessState"
      },
      "SuccessState" => {"Type" => "Succeed"}
    }
  end

  describe "#initialize" do
    context "without no Next nor End" do
      let(:payload)  do
        {
          "PassState" => {
            "Type" => "Pass"
          }
        }
      end

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.PassState does not have required field \"Next\"") }
    end

    context "With a valid Next" do
      let(:payload) do
        {
          "PassState"    => {
            "Type" => "Pass",
            "Next" => "SuccessState"
          },
          "SuccessState" => {"Type" => "Succeed"}
        }
      end

      it { expect(workflow.states.first).not_to be_end }
    end

    context "With an unknown Next" do
      let(:payload) do
        {
          "PassState" => {
            "Type" => "Pass",
            "Next" => "MissingState"
          }
        }
      end

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.PassState field \"Next\" value \"MissingState\" is not found in \"States\"") }
    end

    context "With an End" do
      let(:payload) do
        {
          "PassState" => {
            "Type" => "Pass",
            "End"  => true
          }
        }
      end

      it { expect(workflow.states.first).to be_end }
    end

    # TODO: implement check for Next and End
    # context "With both Next and End" do
    #   let(:payload) do
    #     {
    #       "PassState"    => {
    #         "Type" => "Pass",
    #         "Next" => "SuccessState",
    #         "End"  => true
    #       },
    #       "SuccessState" => {"Type" => "Succeed"}
    #     }
    #   end

    #   it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.PassState error") }
    # end

    context "With an invalid InputPath" do
      let(:payload) do
        {
          "PassState" => {
            "Type"      => "Pass",
            "InputPath" => "bad",
            "End"       => true
          }
        }
      end

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "Path [bad] must start with \"$\"") }
    end

    context "With an invalid OutputPath" do
      let(:payload) do
        {
          "PassState" => {
            "Type"       => "Pass",
            "OutputPath" => "bad",
            "End"        => true
          }
        }
      end

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "Path [bad] must start with \"$\"") }
    end
  end

  describe "#end?" do
    it "is non-terminal" do
      expect(state.end?).to eq(false)
    end
  end

  describe "#run_nonblock!" do
    it "sets the result to the result path" do
      state.run_nonblock!(ctx)
      expect(ctx.output["result"]).to include({"foo" => "bar", "bar" => "baz"})
      expect(ctx.next_state).to eq("SuccessState")
    end

    context "with a ResultPath setting a Credential" do
      let(:payload) do
        {
          "PassState"    => {
            "Type"       => "Pass",
            "Result"     => {
              "user"     => "luggage",
              "password" => "1234"
            },
            "ResultPath" => "$$.Credentials",
            "Next"       => "SuccessState"
          },
          "SuccessState" => {"Type" => "Succeed"}
        }
      end

      it "sets the result in Credentials" do
        state.run_nonblock!(ctx)
        expect(ctx.credentials).to include({"user" => "luggage", "password" => "1234"})
        expect(ctx.next_state).to eq("SuccessState")
      end
    end

    context "With a missing InputPath" do
      let(:payload) do
        {
          "PassState" => {
            "Type"      => "Pass",
            "End"       => true,
            "InputPath" => "$.missing"
          }
        }
      end

      it "completes with an error" do
        workflow.run_nonblock
        expect(ctx.state_finished?).to eq(true)
        expect(ctx.output).to eq(
          {
            "Cause" => "Path [$.missing] references an invalid value",
            "Error" => "States.Runtime"
          }
        )
      end
    end

    context "With a missing OutputPath" do
      let(:payload) do
        {
          "PassState" => {
            "Type"       => "Pass",
            "End"        => true,
            "OutputPath" => "$.missing.spot"
          }
        }
      end

      it "completes with an error" do
        workflow.run_nonblock
        expect(ctx.state_finished?).to eq(true)
        expect(ctx.output).to eq(
          {
            "Cause" => "Path [$.missing.spot] references an invalid value",
            "Error" => "States.Runtime"
          }
        )
      end
    end

    # https://states-language.net/#inputoutput-processing-examples
    context "with 2 blocks" do
      let(:payload) do
        {
          "First"   => {
            "Type"       => "Pass",
            "Result"     => {
              "title"   => "Numbers to add",
              "numbers" => {"val1" => 3, "val2" => 4}
            },
            "ResultPath" => "$",
            "Next"       => "Second"
          },
          "Second"  => {
            "Type"       => "Pass",
            "Result"     => 7,
            "InputPath"  => "$.numbers",
            "ResultPath" => "$.sum",
            "Next"       => "Success"
          },
          "Success" => {
            "Type" => "Succeed"
          }
        }
      end

      it "Uses raw input" do
        workflow.run_nonblock
        expect(ctx.output).to eq(
          "title"   => "Numbers to add",
          "numbers" => {"val1" => 3, "val2" => 4},
          "sum"     => 7
        )
      end
    end

    context "Without Results" do
      let(:input) { {"color" => "red"} }
      let(:payload) do
        {"Pass" => {"Type" => "Pass", "End" => true}}
      end

      it "passes output through to input" do
        workflow.run_nonblock
        expect(ctx.output).to eq(input)
      end

      context "with InputPath" do
        let(:payload) do
          {"Pass" => {"Type" => "Pass", "End" => true, "InputPath" => "$.color"}}
        end

        it "Uses InputPath to select color" do
          workflow.run_nonblock
          expect(ctx.output).to eq("red")
        end
      end

      context "with Invalid InputPath" do
        let(:input) { {} }
        let(:payload) do
          {"Pass" => {"Type" => "Pass", "End" => true, "InputPath" => "$.color"}}
        end

        it "detects missing value" do
          workflow.run_nonblock
          expect(ctx.output).to eq({"Cause" => "Path [$.color] references an invalid value", "Error" => "States.Runtime"})
        end
      end

      context "with OutputPath" do
        let(:input)   { {"color" => "red", "garbage" => nil} }
        let(:payload) { {"Pass" => {"Type" => "Pass", "End" => true, "OutputPath" => "$.color"}} }

        it "Uses OutputPath to drop other keys" do
          workflow.run_nonblock
          expect(ctx.output).to eq("red")
        end
      end

      context "with InputPath, ResultPath, and OutputPath" do
        let(:input)   { {"color" => "red", "garbage" => nil} }
        let(:payload) { {"Pass" => {"Type" => "Pass", "End" => true, "InputPath" => "$.color", "ResultPath" => "$.results", "OutputPath" => "$.results"}} }

        it "Uses OutputPath to drop other keys" do
          workflow.run_nonblock
          expect(ctx.output).to eq("red")
        end
      end
    end
  end
end

RSpec.describe Floe::Workflow::States::Pass, "with QueryLanguage JSONata" do
  let(:input)    { {"foo" => "bar", "num" => 2} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:workflow) { make_workflow(ctx, payload) }
  let(:state)    { {"Type" => "Pass", "QueryLanguage" => "JSONata", "Next" => "SuccessState"} }
  let(:payload)  { {"PassState" => state, "SuccessState" => {"Type" => "Succeed"}} }

  describe "#initialize" do
    %w[Result Parameters InputPath OutputPath ResultPath].each do |field|
      context "with #{field}" do
        let(:state) { {"Type" => "Pass", "QueryLanguage" => "JSONata", "Next" => "SuccessState", field => "$"} }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.PassState field \"#{field}\" is not allowed when QueryLanguage is \"JSONata\"") }
      end
    end

    %w[Arguments Output Assign].each do |field|
      context "with #{field} in a JSONPath state" do
        let(:state) { {"Type" => "Pass", "Next" => "SuccessState", field => {}} }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.PassState field \"#{field}\" is not allowed when QueryLanguage is \"JSONPath\"") }
      end
    end

    context "with an invalid Output expression" do
      let(:state) { {"Type" => "Pass", "QueryLanguage" => "JSONata", "Next" => "SuccessState", "Output" => "{% 1 + %}"} }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /Invalid JSONata expression/) }
    end

    context "with an Assign that is not an object" do
      let(:state) { {"Type" => "Pass", "QueryLanguage" => "JSONata", "Next" => "SuccessState", "Assign" => "{% 1 %}"} }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "Assign".*must be an object/) }
    end

    context "with a workflow level QueryLanguage" do
      let(:workflow) { Floe::Workflow.new({"QueryLanguage" => "JSONata", "StartAt" => "PassState", "States" => {"PassState" => {"Type" => "Pass", "End" => true, "Output" => "{% 1 %}"}}}, ctx) }

      it { expect(workflow.states.first).to be_jsonata }
    end
  end

  describe "#finish" do
    it "defaults the output to the input" do
      workflow.run_nonblock

      expect(ctx.output).to eq(input)
    end

    context "with Output" do
      let(:state) { {"Type" => "Pass", "QueryLanguage" => "JSONata", "Next" => "SuccessState", "Output" => {"x" => "{% $states.input.num * 10 %}", "y" => "static"}} }

      it "evaluates the Output" do
        workflow.run_nonblock

        expect(ctx.output).to eq("x" => 20, "y" => "static")
      end
    end

    context "with an Output expression that is not an object" do
      let(:state) { {"Type" => "Pass", "QueryLanguage" => "JSONata", "End" => true, "Output" => "{% $states.input.foo %}"} }

      it "outputs the value" do
        workflow.run_nonblock

        expect(ctx.output).to eq("bar")
      end
    end

    context "with Assign" do
      let(:state) { {"Type" => "Pass", "QueryLanguage" => "JSONata", "Next" => "SuccessState", "Assign" => {"a" => "{% $states.input.foo %}", "b" => 1}} }

      it "sets the variables and keeps the input as the output" do
        workflow.run_nonblock

        expect(ctx.variables).to eq("a" => "bar", "b" => 1)
        expect(ctx.output).to eq(input)
      end
    end

    context "with Assign and Output" do
      let(:state) do
        {
          "Type"          => "Pass",
          "QueryLanguage" => "JSONata",
          "Next"          => "SuccessState",
          "Assign"        => {"a" => "{% $states.input.num %}", "b" => "{% $a %}"},
          "Output"        => {"seen" => "{% $a %}"}
        }
      end

      before { ctx.variables["a"] = "old" }

      it "evaluates both using the variables from before the state" do
        workflow.run_nonblock

        expect(ctx.variables).to eq("a" => 2, "b" => "old")
        expect(ctx.output).to eq("seen" => "old")
      end
    end

    context "with a failing expression" do
      let(:state) { {"Type" => "Pass", "QueryLanguage" => "JSONata", "End" => true, "Output" => "{% $number('abc') %}"} }

      it "fails the workflow with States.QueryEvaluationError" do
        workflow.run_nonblock

        expect(ctx.status).to eq("failure")
        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
      end

      it "does not change the variables" do
        state["Assign"] = {"a" => 1}
        workflow.run_nonblock

        expect(ctx.variables).to eq({})
      end
    end

    context "with a variable from a previous state" do
      let(:payload) do
        {
          "First"  => {"Type" => "Pass", "QueryLanguage" => "JSONata", "Next" => "Second", "Assign" => {"count" => "{% $states.input.num %}"}},
          "Second" => {"Type" => "Pass", "QueryLanguage" => "JSONata", "End" => true, "Output" => {"count" => "{% $count + 1 %}"}}
        }
      end

      it "can use the variable" do
        workflow.run_nonblock

        expect(ctx.output).to eq("count" => 3)
        expect(ctx.status).to eq("success")
      end
    end

    context "mixed with JSONPath states" do
      let(:payload) do
        {
          "First"  => {"Type" => "Pass", "QueryLanguage" => "JSONata", "Next" => "Second", "Output" => {"value" => "{% $states.input.foo %}"}},
          "Second" => {"Type" => "Pass", "QueryLanguage" => "JSONPath", "End" => true, "Parameters" => {"copy.$" => "$.value"}}
        }
      end

      it "passes the output of one language to the other" do
        workflow.run_nonblock

        expect(ctx.output).to eq("copy" => "bar")
      end
    end
  end
end
