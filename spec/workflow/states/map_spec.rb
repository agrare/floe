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

    context "with an ItemSelector" do
      let(:input) { {"delivery-partner" => "ACME", "colors" => ["red", "green", "blue"]} }
      let(:workflow) do
        payload = {
          "Validate-All" => {
            "Type"           => "Map",
            "ItemsPath"      => "$.colors",
            "ItemSelector"   => {
              "index.$"   => "$$.Map.Item.Index",
              "value.$"   => "$$.Map.Item.Value",
              "courier.$" => "$.delivery-partner"
            },
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
        expect(ctx.output).to eq([{"index" => 0, "value" => "red", "courier" => "ACME"}, {"index" => 1, "value" => "green", "courier" => "ACME"}, {"index" => 2, "value" => "blue", "courier" => "ACME"}])
      end
    end

    context "with an ItemBatcher" do
      let(:input) { {"foo" => "bar", "colors" => ["red", "green", "blue"]} }
      let(:workflow) do
        payload = {
          "Validate-All" => {
            "Type"           => "Map",
            "ItemsPath"      => "$.colors",
            "ItemBatcher"    => {"MaxItemsPerBatch" => 2},
            "MaxConcurrency" => 1,
            "ItemProcessor"  => {
              "StartAt" => "Validate",
              "States"  => {
                "Validate" => {
                  "Type"      => "Pass",
                  "InputPath" => "$.Items",
                  "End"       => true
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
        expect(ctx.output).to eq([["red", "green"], ["blue"]])
      end

      context "with MaxItemsPerBatchPath" do
        let(:input) { {"maxItems" => 2, "colors" => ["red", "green", "blue"]} }
        let(:workflow) do
          payload = {
            "Validate-All" => {
              "Type"           => "Map",
              "ItemsPath"      => "$.colors",
              "ItemBatcher"    => {"MaxItemsPerBatchPath" => "$.maxItems"},
              "MaxConcurrency" => 1,
              "ItemProcessor"  => {
                "StartAt" => "Validate",
                "States"  => {
                  "Validate" => {
                    "Type"      => "Pass",
                    "InputPath" => "$.Items",
                    "End"       => true
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
          expect(ctx.output).to eq([["red", "green"], ["blue"]])
        end
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

RSpec.describe Floe::Workflow::States::Map, "with QueryLanguage JSONata" do
  let(:input)    { {"colors" => %w[red green blue], "partner" => "ACME"} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:workflow) { make_workflow(ctx, payload) }
  let(:processor_states) { {"Validate" => {"Type" => "Pass", "End" => true}} }
  let(:map) do
    {
      "Type"          => "Map",
      "QueryLanguage" => "JSONata",
      "Items"         => "{% $states.input.colors %}",
      "ItemProcessor" => {"StartAt" => "Validate", "States" => processor_states},
      "End"           => true
    }
  end
  let(:payload) { {"MapState" => map} }

  def run_workflow
    workflow.run_nonblock
    workflow
  end

  describe "#initialize" do
    %w[ItemsPath InputPath OutputPath ResultPath ResultSelector Parameters].each do |field|
      context "with #{field}" do
        before { map[field] = "$" }

        it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.MapState field \"#{field}\" is not allowed when QueryLanguage is \"JSONata\"") }
      end
    end

    context "with Items in a JSONPath state" do
      let(:map) { {"Type" => "Map", "Items" => [], "ItemProcessor" => {"StartAt" => "A", "States" => {"A" => {"Type" => "Succeed"}}}, "End" => true} }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, "States.MapState field \"Items\" is not allowed when QueryLanguage is \"JSONPath\"") }
    end

    context "with ItemBatcher" do
      before { map["ItemBatcher"] = {"MaxItemsPerBatch" => 1} }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "ItemBatcher" is not supported/) }
    end

    context "with Items that is not an array or an expression" do
      before { map["Items"] = "$.colors" }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "Items" value "\$.colors" must be an array or a JSONata expression/) }
    end

    context "with a static MaxConcurrency of 0" do
      before { map["MaxConcurrency"] = 0 }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "MaxConcurrency" value "0" must be greater than 0/) }
    end

    context "with a MaxConcurrency expression" do
      before { map["MaxConcurrency"] = "{% 2 %}" }

      it { expect { workflow }.not_to raise_error }
    end

    context "with an invalid ItemSelector expression" do
      before { map["ItemSelector"] = {"a" => "{% ( %}"} }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /Invalid JSONata expression/) }
    end

    context "with an Arguments field" do
      before { map["Arguments"] = {} }

      it { expect { workflow }.to raise_error(Floe::InvalidWorkflowError, /field "Arguments" is not supported/) }
    end
  end

  describe "Items" do
    it "runs the ItemProcessor for each item and defaults the output to the results" do
      expect(run_workflow.output).to eq(%w[red green blue].to_json)
    end

    context "with a literal array" do
      before { map["Items"] = [1, 2] }

      it { expect(run_workflow.output).to eq("[1,2]") }
    end

    context "with an expression which builds the array" do
      before { map["Items"] = "{% $states.input.colors.$uppercase($) %}" }

      it { expect(run_workflow.output).to eq(%w[RED GREEN BLUE].to_json) }
    end

    context "without Items" do
      let(:input) { [1, 2, 3] }

      before { map.delete("Items") }

      it "uses the state input" do
        expect(run_workflow.output).to eq("[1,2,3]")
      end
    end

    context "with an Items expression which is not an array" do
      before { map["Items"] = "{% $states.input.partner %}" }

      it "fails with States.QueryEvaluationError" do
        run_workflow

        expect(ctx.status).to eq("failure")
        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
      end
    end
  end

  describe "ItemSelector" do
    before do
      map["ItemSelector"] = {
        "index"   => "{% $states.context.Map.Item.Index %}",
        "value"   => "{% $states.context.Map.Item.Value %}",
        "partner" => "{% $states.input.partner %}",
        "static"  => 1
      }
    end

    it "can use the item context and the state input" do
      expect(JSON.parse(run_workflow.output)).to eq(
        [
          {"index" => 0, "value" => "red", "partner" => "ACME", "static" => 1},
          {"index" => 1, "value" => "green", "partner" => "ACME", "static" => 1},
          {"index" => 2, "value" => "blue", "partner" => "ACME", "static" => 1}
        ]
      )
    end
  end

  describe "ItemProcessor" do
    let(:processor_states) do
      {"Validate" => {"Type" => "Pass", "End" => true, "Output" => {"color" => "{% $states.input %}", "prefix" => "{% $prefix %}"}}}
    end

    before { ctx.variables["prefix"] = "pre" }

    it "inherits the QueryLanguage and can read the variables of the parent" do
      expect(JSON.parse(run_workflow.output)).to eq(
        [
          {"color" => "red", "prefix" => "pre"},
          {"color" => "green", "prefix" => "pre"},
          {"color" => "blue", "prefix" => "pre"}
        ]
      )
    end

    context "when the ItemProcessor assigns variables" do
      let(:processor_states) { {"Validate" => {"Type" => "Pass", "End" => true, "Assign" => {"prefix" => "child"}}} }

      it "does not change the variables of the parent" do
        run_workflow

        expect(ctx.variables).to eq("prefix" => "pre")
      end
    end

    context "with a JSONPath ItemProcessor" do
      let(:processor_states) { {"Validate" => {"Type" => "Pass", "End" => true, "QueryLanguage" => "JSONPath", "Parameters" => {"c.$" => "$"}}} }

      it "uses the language of the nested state" do
        expect(JSON.parse(run_workflow.output)).to eq([{"c" => "red"}, {"c" => "green"}, {"c" => "blue"}])
      end
    end
  end

  describe "Output and Assign" do
    before do
      map["Output"] = {"count" => "{% $count($states.result) %}", "first" => "{% $states.result[0] %}", "in" => "{% $states.input.partner %}"}
      map["Assign"] = {"results" => "{% $states.result %}"}
    end

    it "can use $states.result" do
      run_workflow

      expect(JSON.parse(workflow.output)).to eq("count" => 3, "first" => "red", "in" => "ACME")
      expect(ctx.variables).to eq("results" => %w[red green blue])
    end
  end

  describe "MaxConcurrency" do
    before { map["MaxConcurrency"] = "{% 1 %}" }

    it "evaluates the expression" do
      expect(run_workflow.output).to eq(%w[red green blue].to_json)
    end

    context "with an expression which is not a positive integer" do
      before { map["MaxConcurrency"] = "{% 'a' %}" }

      it "fails the state" do
        run_workflow

        expect(ctx.status).to eq("failure")
        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
      end
    end
  end

  describe "ToleratedFailureCount and ToleratedFailurePercentage" do
    let(:processor_states) { {"Validate" => {"Type" => "Fail", "Error" => "Nope"}} }

    context "without tolerance" do
      it "fails with the child error" do
        run_workflow

        expect(ctx.status).to eq("failure")
        expect(ctx.output).to eq("Error" => "Nope")
      end
    end

    context "with a ToleratedFailureCount expression that is exceeded" do
      before { map["ToleratedFailureCount"] = "{% 2 %}" }

      it "fails with States.ExceedToleratedFailureThreshold" do
        run_workflow

        expect(ctx.output).to eq("Error" => "States.ExceedToleratedFailureThreshold")
      end
    end

    context "with a ToleratedFailureCount expression that is not exceeded" do
      before { map["ToleratedFailureCount"] = "{% $count($states.input.colors) + 1 %}" }

      it "succeeds" do
        run_workflow

        expect(ctx.status).to eq("success")
      end
    end

    context "with a ToleratedFailurePercentage expression" do
      before { map["ToleratedFailurePercentage"] = 100 }

      it "succeeds" do
        run_workflow

        expect(ctx.status).to eq("success")
      end
    end

    context "with an expression which is not valid" do
      before { map["ToleratedFailureCount"] = "{% -1 %}" }

      it "fails with States.QueryEvaluationError" do
        run_workflow

        expect(ctx.output["Error"]).to eq("States.QueryEvaluationError")
      end
    end
  end

  describe "Catch" do
    let(:payload) { {"MapState" => map.merge("End" => nil, "Next" => "Recover", "Catch" => catchers), "Recover" => {"Type" => "Pass", "QueryLanguage" => "JSONata", "End" => true}} }
    let(:catchers) { [{"ErrorEquals" => ["Nope"], "Next" => "Recover", "Output" => {"caught" => "{% $states.errorOutput.Error %}"}, "Assign" => {"err" => "{% $states.errorOutput %}"}}] }
    let(:processor_states) { {"Validate" => {"Type" => "Fail", "Error" => "Nope"}} }

    it "uses Output and Assign of the catcher" do
      run_workflow

      expect(ctx.status).to eq("success")
      expect(JSON.parse(workflow.output)).to eq("caught" => "Nope")
      expect(ctx.variables).to eq("err" => {"Error" => "Nope"})
    end
  end

  describe "Retry" do
    let(:processor_states) { {"Validate" => {"Type" => "Fail", "Error" => "Nope"}} }

    before { map["Retry"] = [{"ErrorEquals" => ["Nope"], "MaxAttempts" => 1, "IntervalSeconds" => 30}] }

    it "retries the state until MaxAttempts is exceeded" do
      workflow.run_nonblock

      expect(ctx.state["Retrier"]).to eq(["Nope"])
      expect(ctx.state_history.count).to eq(2)
      expect(ctx.status).to eq("failure")
      expect(ctx.output).to eq("Error" => "Nope")
    end
  end
end
