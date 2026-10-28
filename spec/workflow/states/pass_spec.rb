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

    context "With a Parameters Path that references a missing value" do
      let(:payload) { {"PassState" => {"Type" => "Pass", "End" => true, "Parameters" => {"foo.$" => "$.missing"}}} }

      it "completes with a States.ParameterPathFailure error" do
        workflow.run_nonblock
        expect(ctx.state_finished?).to eq(true)
        expect(ctx.output).to eq({"Cause" => "Path [$.missing] references an invalid value", "Error" => "States.ParameterPathFailure"})
      end
    end

    context "With a Parameters Intrinsic Function that fails" do
      let(:payload) { {"PassState" => {"Type" => "Pass", "End" => true, "Parameters" => {"foo.$" => "States.MathAdd('a', 1)"}}} }

      it "completes with a States.IntrinsicFailure error" do
        workflow.run_nonblock
        expect(ctx.state_finished?).to eq(true)
        expect(ctx.output).to eq({"Cause" => "wrong type for argument 1 to States.MathAdd (given String, expected Integer)", "Error" => "States.IntrinsicFailure"})
      end
    end

    context "With a ResultPath that cannot be applied to the input" do
      let(:input)   { "foo" }
      let(:payload) { {"PassState" => {"Type" => "Pass", "End" => true, "Result" => 1, "ResultPath" => "$.x"}} }

      it "completes with a States.ResultPathMatchFailure error" do
        workflow.run_nonblock
        expect(ctx.state_finished?).to eq(true)
        expect(ctx.output).to eq({"Cause" => "Path [$.x] cannot be applied to the input", "Error" => "States.ResultPathMatchFailure"})
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
