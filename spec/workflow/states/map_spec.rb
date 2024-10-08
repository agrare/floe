RSpec.describe Floe::Workflow::States::Map do
  let(:input)    { {} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:state)    { workflow.start_workflow.current_state }
  let(:input)    do
    {
      "ship-date" => "2016-03-14T01:59:00Z",
      "detail"    => {
        "delivery-partner" => "UQS",
        "shipped"          => [
          {"prod" => "R31", "dest-code" => 9511, "quantity" => 1344},
          {"prod" => "S39", "dest-code" => 9511, "quantity" => 40},
          {"prod" => "R31", "dest-code" => 9833, "quantity" => 12},
          {"prod" => "R40", "dest-code" => 9860, "quantity" => 887},
          {"prod" => "R40", "dest-code" => 9511, "quantity" => 1220}
        ]
      }
    }
  end

  let(:tolerated_failure_count)      { nil }
  let(:tolerated_failure_percentage) { nil }
  let(:workflow) do
    payload = {
      "Validate-All" => {
        "Type"           => "Map",
        "InputPath"      => "$.detail",
        "ItemsPath"      => "$.shipped",
        "MaxConcurrency" => 1,
        "ItemProcessor"  => {
          "StartAt" => "Validate",
          "States"  => {
            "Validate" => {
              "Type"      => "Pass",
              "End"       => true,
              "InputPath" => "$.prod"
            }
          }
        },
        "ResultPath"     => "$.detail.result",
        "End"            => true,
      }
    }

    payload["Validate-All"]["ToleratedFailureCount"]      = tolerated_failure_count if tolerated_failure_count
    payload["Validate-All"]["ToleratedFailurePercentage"] = tolerated_failure_percentage if tolerated_failure_percentage

    make_workflow(ctx, payload)
  end

  describe "#initialize" do
    it "raises an InvalidWorkflowError with a missing ItemProcessor" do
      payload = {
        "Validate-All" => {
          "Type" => "Map",
          "End"  => true
        }
      }

      expect { make_workflow(ctx, payload) }
        .to raise_error(Floe::InvalidWorkflowError, "States.Validate-All does not have required field \"InputProcessor\"")
    end

    it "raises an InvalidWorkflowError with a missing Next and End" do
      payload = {
        "Validate-All" => {
          "Type"          => "Map",
          "ItemProcessor" => {
            "StartAt" => "Validate",
            "States"  => {"Validate" => {"Type" => "Succeed"}}
          }
        }
      }

      expect { make_workflow(ctx, payload) }
        .to raise_error(Floe::InvalidWorkflowError, "States.Validate-All does not have required field \"Next\"")
    end

    it "raises an InvalidWorkflowError if a state in ItemProcessor attempts to transition to a state in the outer workflow" do
      payload = {
        "StartAt" => "MapState",
        "States"  => {
          "MapState"     => {
            "Type"          => "Map",
            "Next"          => "PassState",
            "ItemProcessor" => {
              "StartAt" => "Validate",
              "States"  => {
                "Validate" => {
                  "Type" => "Pass",
                  "Next" => "PassState"
                }
              }
            }
          },
          "PassState"    => {
            "Type" => "Pass",
            "Next" => "SucceedState"
          },
          "SucceedState" => {
            "Type" => "Succeed"
          }
        }
      }

      expect { Floe::Workflow.new(payload, ctx) }
        .to raise_error(Floe::InvalidWorkflowError, "States.Validate field \"Next\" value \"PassState\" is not found in \"States\"")
    end

    it "raises an InvalidWorkflowError if MaxConcurrency is 0" do
      payload = {
        "Validate-All" => {
          "Type"           => "Map",
          "MaxConcurrency" => 0,
          "End"            => true,
          "ItemProcessor"  => {
            "StartAt" => "Validate",
            "States"  => {"Validate" => {"Type" => "Succeed"}}
          }
        }
      }

      expect { make_workflow(ctx, payload) }
        .to raise_error(Floe::InvalidWorkflowError, "States.Validate-All field \"MaxConcurrency\" value \"0\" must be greater than 0")
    end
  end

  it "#end?" do
    expect(state.end?).to be true
  end

  describe "#run_nonblock!" do
    it "has no next" do
      loop while state.run_nonblock!(ctx) != 0
      expect(ctx.next_state).to eq(nil)
    end

    it "sets the context output" do
      loop while state.run_nonblock!(ctx) != 0
      expect(ctx.output.dig("detail", "result")).to eq(%w[R31 S39 R31 R40 R40])
    end

    context "with simple string inputs" do
      let(:input) { {"foo" => "bar", "colors" => ["red", "green", "blue"]} }
      let(:workflow) do
        payload = {
          "Validate-All" => {
            "Type"           => "Map",
            "ItemsPath"      => "$.colors",
            "MaxConcurrency" => 1,
            "ItemProcessor"  => {
              "StartAt" => "Validate",
              "States"  => {
                "Validate" => {
                  "Type" => "Pass",
                  "End"  => true
                }
              }
            },
            "End"            => true,
          }
        }
        make_workflow(ctx, payload)
      end

      it "sets the context output" do
        loop while state.run_nonblock!(ctx) != 0
        expect(ctx.output).to eq(["red", "green", "blue"])
      end
    end
  end

  describe "#finish" do
    before { state.start(ctx) }

    context "with mixed success and failures" do
      before do
        ctx.state["ItemProcessorContext"][0]["State"] = {"Output" => {"Error" => "States.TaskFailed"}}
        ctx.state["ItemProcessorContext"][2]["State"] = {"Output" => {"Error" => "States.TaskFailed"}}
      end

      it "sets the state error to error from the ItemProcessor" do
        state.finish(ctx)

        expect(ctx.failed?).to be_truthy
        expect(ctx.output).to eq("Error" => "States.TaskFailed")
      end

      context "with ToleratedFailureCount" do
        let(:tolerated_failure_count) { 1 }

        it "sets the state error to States.ExceedToleratedFailureThreshold" do
          state.finish(ctx)

          expect(ctx.failed?).to be_truthy
          expect(ctx.output).to eq("Error" => "States.ExceedToleratedFailureThreshold")
        end
      end

      context "with ToleratedFailurePercentage" do
        let(:tolerated_failure_percentage) { 20 }

        it "sets the state error to States.ExceedToleratedFailureThreshold" do
          state.finish(ctx)

          expect(ctx.failed?).to be_truthy
          expect(ctx.output).to eq("Error" => "States.ExceedToleratedFailureThreshold")
        end
      end
    end
  end

  describe "#running?" do
    before { state.start(ctx) }

    context "with all iterations ended" do
      before { ctx.state["ItemProcessorContext"].each { |ctx| ctx["Execution"]["EndTime"] = Time.now.utc } }

      it "returns false" do
        expect(state.running?(ctx)).to be_falsey
      end
    end

    context "with some iterations not ended" do
      before { ctx.state["ItemProcessorContext"][0]["Execution"]["EndTime"] = Time.now.utc }

      it "returns true" do
        expect(state.running?(ctx)).to be_truthy
      end
    end
  end

  describe "#ended?" do
    before { state.start(ctx) }

    context "with all iterations ended" do
      before { ctx.state["ItemProcessorContext"].each { |ctx| ctx["Execution"]["EndTime"] = Time.now.utc } }

      it "returns true" do
        expect(state.ended?(ctx)).to be_truthy
      end
    end

    context "with some iterations not ended" do
      before { ctx.state["ItemProcessorContext"][0]["Execution"]["EndTime"] = Time.now.utc }

      it "returns false" do
        expect(state.ended?(ctx)).to be_falsey
      end
    end
  end

  describe "#success?" do
    before { state.start(ctx) }

    context "with no failed iterations" do
      it "returns true" do
        expect(state.success?(ctx)).to be_truthy
      end
    end

    context "with no iterations" do
      let(:input) { {"detail" => {"shipped" => []}} }

      it "returns true" do
        expect(state.success?(ctx)).to be_truthy
      end
    end

    context "with all iterations failed" do
      before { ctx.state["ItemProcessorContext"].each { |ctx| ctx["State"] = {"Output" => {"Error" => "FAILED!"}} } }

      it "returns false" do
        expect(state.success?(ctx)).to be_falsey
      end
    end

    context "with mixed successful and failed iterations" do
      before do
        ctx.state["ItemProcessorContext"][0]["State"] = {"Output" => {"Error" => "FAILED!"}}
        ctx.state["ItemProcessorContext"][2]["State"] = {"Output" => {"Error" => "FAILED!"}}
      end

      it "returns true" do
        expect(state.success?(ctx)).to be_falsey
      end

      context "with ToleratedFailureCount" do
        context "greater than the number of failures" do
          let(:tolerated_failure_count) { 3 }

          it "returns false" do
            expect(state.success?(ctx)).to be_truthy
          end
        end

        context "less than the number of failures" do
          let(:tolerated_failure_count) { 1 }

          it "returns true" do
            expect(state.success?(ctx)).to be_falsey
          end
        end
      end

      context "with ToleratedFailurePercentage" do
        context "greater than the number of failures" do
          let(:tolerated_failure_percentage) { 50 }

          it "returns false" do
            expect(state.success?(ctx)).to be_truthy
          end
        end

        context "less than the number of failures" do
          let(:tolerated_failure_percentage) { 10 }

          it "returns true" do
            expect(state.success?(ctx)).to be_falsey
          end
        end
      end

      context "with both ToleratedFailureCount and ToleratedFailurePercentage" do
        context "with ToleratedFailureCount being lower than the failed percentge" do
          let(:tolerated_failure_percentage) { 50 }
          let(:tolerated_failure_count)      { 1 }

          it "returns false" do
            expect(state.success?(ctx)).to be_falsey
          end
        end

        context "with ToleratedFailurePercentage being lower than the failed count" do
          let(:tolerated_failure_percentage) { 10 }
          let(:tolerated_failure_count)      { 3 }

          it "returns false" do
            expect(state.success?(ctx)).to be_falsey
          end
        end

        context "with neither being high enough for success" do
          let(:tolerated_failure_percentage) { 10 }
          let(:tolerated_failure_count)      { 1 }

          it "returns false" do
            expect(state.success?(ctx)).to be_falsey
          end
        end

        context "with both being high enough for success" do
          let(:tolerated_failure_percentage) { 50 }
          let(:tolerated_failure_count)      { 3 }

          it "returns true" do
            expect(state.success?(ctx)).to be_truthy
          end
        end
      end
    end
  end
end
