# End to end tests for workflows using the JSONata query language
RSpec.describe "JSONata workflows" do
  let(:input)    { {"orders" => [{"id" => 1, "price" => 10, "qty" => 3}, {"id" => 2, "price" => 5, "qty" => 1}]} }
  let(:ctx)      { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:workflow) { Floe::Workflow.load(GEM_ROOT.join("examples", "jsonata.asl"), ctx) }

  describe "examples/jsonata.asl" do
    it "uses variables across states and the JSONata Choice" do
      workflow.run_nonblock

      expect(ctx.status).to eq("success")
      expect(ctx.state_history.map { |s| s["Name"] }).to eq(%w[Total CheckTotal Large])
      expect(JSON.parse(workflow.output)).to eq("size" => "large", "orders" => 2, "total" => 35)
      expect(ctx.variables).to eq("orderCount" => 2, "total" => 35)
    end

    context "with a small order" do
      let(:input) { {"orders" => [{"id" => 2, "price" => 5, "qty" => 1}]} }

      it "goes through the default and the JSONPath state" do
        workflow.run_nonblock

        expect(ctx.status).to eq("success")
        expect(ctx.state_history.map { |s| s["Name"] }).to eq(%w[Total CheckTotal Small])
        expect(JSON.parse(workflow.output)).to eq("size" => "small", "orders" => input["orders"])
      end
    end
  end

  describe "persisting the context between steps" do
    it "keeps the variables when the context is serialized and reloaded" do
      workflow.start_workflow
      workflow.step_nonblock
      expect(ctx.variables).to eq("orderCount" => 2, "total" => 35)

      reloaded_ctx = Floe::Workflow::Context.new(JSON.parse(ctx.to_h.to_json))
      reloaded     = Floe::Workflow.load(GEM_ROOT.join("examples", "jsonata.asl"), reloaded_ctx)
      reloaded.run_nonblock

      expect(reloaded_ctx.status).to eq("success")
      expect(JSON.parse(reloaded.output)).to eq("size" => "large", "orders" => 2, "total" => 35)
    end
  end

  describe "a workflow mixing both query languages" do
    let(:workflow) do
      Floe::Workflow.new(
        {
          "StartAt" => "Jsonpath",
          "States"  => {
            "Jsonpath" => {"Type" => "Pass", "Parameters" => {"n.$" => "$.orders[0].qty"}, "Next" => "Jsonata"},
            "Jsonata"  => {"Type" => "Pass", "QueryLanguage" => "JSONata", "Assign" => {"doubled" => "{% $states.input.n * 2 %}"}, "Output" => "{% $states.input %}", "Next" => "Check"},
            "Check"    => {"Type" => "Choice", "QueryLanguage" => "JSONata", "Choices" => [{"Condition" => "{% $doubled = 6 %}", "Next" => "Done"}], "Default" => "Wrong"},
            "Wrong"    => {"Type" => "Fail", "QueryLanguage" => "JSONata", "Error" => "Wrong", "Cause" => "{% 'doubled was ' & $string($doubled) %}"},
            "Done"     => {"Type" => "Succeed", "QueryLanguage" => "JSONata", "Output" => {"result" => "{% $doubled %}"}}
          }
        },
        ctx
      )
    end

    it "passes data and variables between them" do
      workflow.run_nonblock

      expect(ctx.status).to eq("success")
      expect(JSON.parse(workflow.output)).to eq("result" => 6)
    end
  end

  describe "a workflow level QueryLanguage with a Task" do
    let(:mock_runner) { double("Floe::Runner") }
    let(:workflow) do
      Floe::Workflow.new(
        {
          "QueryLanguage" => "JSONata",
          "StartAt"       => "Run",
          "States"        => {
            "Run" => {
              "Type"      => "Task",
              "Resource"  => "docker://hello-world:latest",
              "Arguments" => {"count" => "{% $count($states.input.orders) %}"},
              "Assign"    => {"answer" => "{% $states.result.answer %}"},
              "Output"    => {"answer" => "{% $states.result.answer %}", "input_count" => "{% $states.input.orders[0].id %}"},
              "End"       => true
            }
          }
        },
        ctx
      )
    end

    it "sends Arguments to the runner and uses the result" do
      allow(Floe::Runner).to receive(:for_resource).and_return(mock_runner)
      allow(mock_runner).to receive(:status!).and_return({})
      allow(mock_runner).to receive(:running?).and_return(false)
      allow(mock_runner).to receive(:success?).and_return(true)
      allow(mock_runner).to receive(:output).and_return('{"answer": 42}')
      allow(mock_runner).to receive(:cleanup)
      expect(mock_runner).to receive(:run_async!).with("docker://hello-world:latest", {"count" => 2}, nil, ctx).and_return({})

      workflow.run_nonblock

      expect(ctx.status).to eq("success")
      expect(JSON.parse(workflow.output)).to eq("answer" => 42, "input_count" => 1)
      expect(ctx.variables).to eq("answer" => 42)
    end
  end
end
