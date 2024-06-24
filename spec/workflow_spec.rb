RSpec.describe Floe::Workflow do
  let(:now)   { Time.now.utc }
  let(:input) { {"input" => "value"}.freeze }
  let(:ctx)   { Floe::Workflow::Context.new(:input => input.to_json) }

  describe "#new" do
    it "sets initial state" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})

      expect(workflow.status).to eq("pending")
      expect(workflow.end?).to eq(false)

      expect(ctx.status).to eq("pending")
      expect(ctx.started?).to eq(false)
      expect(ctx.running?).to eq(false)
      expect(ctx.ended?).to eq(false)
    end

    it "raises an exception for missing States" do
      payload = {"StartAt" => "Nothing"}

      expect { described_class.new(payload) }.to raise_error(Floe::InvalidWorkflowError, "Missing field \"States\"")
    end

    it "raises an exception for invalid States" do
      payload = make_payload({"FirstState" => {"Type" => "Invalid"}})

      expect { described_class.new(payload) }.to raise_error(Floe::InvalidWorkflowError, "Invalid state type: [Invalid]")
    end

    it "raises an exception for missing StartAt" do
      payload = {"States" => {"FirstState" => {"Type" => "Succeed"}}}

      expect { described_class.new(payload) }.to raise_error(Floe::InvalidWorkflowError, "Missing field \"StartAt\"")
    end

    it "raises an exception for StartAt not in States" do
      payload = {"StartAt" => "Foo", "States" => {"FirstState" => {"Type" => "Succeed"}}}

      expect { described_class.new(payload) }.to raise_error(Floe::InvalidWorkflowError, "\"StartAt\" not in the \"States\" field")
    end

    it "raises an exception for a State missing a Type field" do
      payload = make_payload({"FirstState" => {}})

      expect { described_class.new(payload) }.to raise_error(Floe::InvalidWorkflowError, "Missing \"Type\" field in state [FirstState]")
    end

    it "raises an exception for an invalid State name" do
      state_name = "a" * 81
      truncated_state_name = "#{"a" * 80}..."
      payload = make_payload({state_name => {"Type" => "Succeed"}})

      expect { described_class.new(payload) }.to raise_error(Floe::InvalidWorkflowError, "State name [#{truncated_state_name}] must be less than or equal to 80 characters")
    end

    it "raises an exception for invalid context" do
      payload = make_payload({"FirstState" => {"Type" => "Success"}})

      expect { described_class.new(payload, "invalid context") }.to raise_error(Floe::InvalidExecutionInput, "Invalid State Machine Execution Input: unexpected token at 'invalid context': was expecting (JSON String, Number, Array, Object or token 'null', 'true' or 'false')")
    end

    it "raises an exception for invalid resource scheme in a Task state" do
      payload = make_payload({"FirstState" => {"Type" => "Task", "Resource" => "invalid://foo", "End" => true}})

      expect { described_class.new(payload) }.to raise_error(Floe::InvalidWorkflowError, "Invalid resource scheme [invalid]")
    end
  end

  describe "#run_nonblock" do
    it "sets execution variables for success" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})
      workflow.run_nonblock

      # state
      expect(Time.parse(ctx.state["EnteredTime"])).to be_within(1).of(now)
      expect(Time.parse(ctx.state["FinishedTime"])).to be_within(1).of(now)
      expect(ctx.state["Guid"]).to be
      expect(ctx.state_name).to eq("FirstState")
      expect(ctx.input).to eq(input)
      expect(ctx.output).to eq(input)
      expect(ctx.state["Duration"].to_f).to be <= 1
      expect(ctx.status).to eq("success")

      # execution
      expect(ctx.started?).to eq(true)
      expect(ctx.running?).to eq(false)
      expect(ctx.ended?).to eq(true)

      # final results
      expect(workflow.output).to eq(input.to_json)
      expect(workflow.status).to eq("success")
      expect(workflow.end?).to eq(true)
    end

    it "sets execution variables for failure" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Fail", "Cause" => "Bad Stuff", "Error" => "Issue"}})
      workflow.run_nonblock

      # state
      expect(Time.parse(ctx.state["EnteredTime"])).to be_within(1).of(now)
      expect(Time.parse(ctx.state["FinishedTime"])).to be_within(1).of(now)
      expect(ctx.state["Guid"]).to be
      expect(ctx.state_name).to eq("FirstState")
      expect(ctx.input).to eq(input)
      expect(ctx.output).to eq({"Cause" => "Bad Stuff", "Error" => "Issue"})
      expect(ctx.state["Duration"].to_f).to be <= 1
      expect(ctx.status).to eq("failure")

      # execution
      expect(ctx.started?).to eq(true)
      expect(ctx.running?).to eq(false)
      expect(ctx.ended?).to eq(true)

      # final results
      expect(workflow.output).to eq({"Error" => "Issue", "Cause" => "Bad Stuff"}.to_json)
      expect(workflow.status).to eq("failure")
      expect(workflow.end?).to eq(true)
    end

    it "starts the first state" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})
      workflow.run_nonblock

      expect(ctx.started?).to eq(true)
    end

    it "doesn't wait for the state to finish" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})
      workflow.run_nonblock

      expect(ctx.running?).to eq(true)
      expect(ctx.ended?).to   eq(false)
    end
  end

  describe "#step_nonblock" do
    it "runs a success step" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})

      expect(workflow.status).to eq("pending")
      expect(workflow.end?).to eq(false)
      expect(ctx.status).to eq("pending")
      expect(ctx.started?).to eq(false)
      expect(ctx.running?).to eq(false)
      expect(ctx.ended?).to eq(false)

      workflow.start_workflow
      workflow.step_nonblock

      expect(workflow.output).to eq(input.to_json)
      expect(workflow.status).to eq("success")
      expect(workflow.end?).to eq(true)
      expect(ctx.output).to eq(input)
      expect(ctx.status).to eq("success")
      expect(ctx.started?).to eq(true)
      expect(ctx.running?).to eq(false)
      expect(ctx.ended?).to eq(true)
    end

    it "bails from a block" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})
      workflow.start_workflow
      workflow.step_nonblock

      expect(workflow.status).to eq("running")
      expect(workflow.end?).to   eq(false)
    end

    context "with a running state" do
      it "returns Try again" do
        workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})
        workflow.start_workflow
        expect(workflow.step_nonblock).to eq(Errno::EAGAIN)
      end
    end

    context "with a state that has finished" do
      it "completes the final tasks for a state" do
        workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})

        # Start the workflow
        Timecop.travel(Time.now.utc - 60) do
          workflow.run_nonblock
        end

        # step_nonblock should return 0 and mark the workflow as completed
        expect(workflow.step_nonblock).to eq(0)

        expect(workflow.output).to eq(input.to_json)
        expect(workflow.status).to eq("success")
        expect(workflow.end?).to eq(true)
        expect(ctx.output).to eq(input)
        expect(ctx.status).to eq("success")
        expect(ctx.started?).to eq(true)
        expect(ctx.running?).to eq(false)
        expect(ctx.ended?).to eq(true)
      end
    end

    it "return Operation not permitted if workflow has ended" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})

      ctx.execution["EndTime"] = Time.now.utc

      expect(workflow.step_nonblock).to eq(Errno::EPERM)
    end

    it "takes 2 steps" do
      workflow = make_workflow(
        ctx, {
          "FirstState"  => {"Type" => "Pass", "Next" => "SecondState"},
          "SecondState" => {"Type" => "Succeed"}
        }
      )

      expect(ctx.status).to eq("pending")
      expect(ctx.started?).to eq(false)
      expect(ctx.running?).to eq(false)
      expect(ctx.ended?).to eq(false)

      workflow.start_workflow
      workflow.step_nonblock

      expect(ctx.status).to eq("running")

      # execution
      expect(ctx.started?).to eq(true)
      expect(ctx.running?).to eq(true)
      expect(ctx.ended?).to eq(false)

      expect(workflow.output).to be_nil

      # second step

      workflow.step_nonblock

      expect(ctx.state_name).to eq("SecondState")
      expect(ctx.status).to eq("success")

      # execution
      expect(ctx.started?).to eq(true)
      expect(ctx.running?).to eq(false)
      expect(ctx.ended?).to eq(true)

      expect(workflow.output).to eq(input.to_json)
    end
  end

  describe "#step_nonblock_wait" do
    context "with a state that hasn't started yet" do
      it "returns 0" do
        workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})
        expect(workflow.step_nonblock_wait).to eq(0)
      end
    end

    context "with a state that has finished" do
      it "return 0" do
        workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})
        workflow.start_workflow
        workflow.current_state.run_nonblock!(ctx)
        expect(workflow.step_nonblock_wait).to eq(0)
      end
    end

    context "with a state that is running" do
      it "returns Try again" do
        workflow = make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "Seconds" => 10, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}})
        workflow.run_nonblock
        expect(workflow.step_nonblock_wait(:timeout => 0)).to eq(Errno::EAGAIN)
      end
    end
  end

  describe "#step_nonblock_ready?" do
    context "with a state that hasn't started yet" do
      it "returns true" do
        workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})
        expect(workflow.step_nonblock_ready?).to be_truthy
      end
    end

    context "with a state that has finished" do
      it "return true" do
        workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})
        workflow.run_nonblock
        expect(workflow.current_state).to receive(:running?).and_return(false)
        expect(workflow.step_nonblock_ready?).to be_truthy
      end
    end

    context "with a state that is running" do
      it "returns false" do
        workflow = make_workflow(ctx, {"WaitState" => {"Type" => "Wait", "Seconds" => 10, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}})
        workflow.run_nonblock

        expect(workflow.step_nonblock_ready?).to be_falsey
      end
    end
  end

  describe "#wait_until" do
    it "reads when the workflow will be ready to continue" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}})
      workflow.run_nonblock

      expect(workflow.wait_until).to be_within(1).of(Time.now.utc + 10)
    end

    it "doesn't have a wait" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})
      workflow.run_nonblock

      expect(workflow.wait_until).to be_nil
    end
  end

  describe "#waiting?" do
    it "reads when the workflow will be ready to continue" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true, "Next" => "SuccessState"}, "SuccessState" => {"Type" => "Succeed"}})
      workflow.run_nonblock

      expect(workflow.waiting?).to be_truthy
    end

    it "doesn't have a wait" do
      workflow = make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}})
      workflow.run_nonblock

      expect(workflow.waiting?).to be_falsey
    end
  end

  describe ".wait" do
    context "with two ready workflows" do
      let(:workflow_1) { make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}}) }
      let(:workflow_2) { make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}}) }

      it "returns both workflows as ready to step" do
        expect(described_class.wait([workflow_1, workflow_2], :timeout => 0)).to include(workflow_1, workflow_2)
      end
    end

    context "with one ready workflow and one that would block" do
      let(:workflow_1) { make_workflow(ctx, {"FirstState" => {"Type" => "Succeed"}}) }
      let(:workflow_2) { make_workflow(ctx, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}}).start_workflow.tap(&:step_nonblock) }

      it "returns only the first workflow as ready to step" do
        expect(described_class.wait([workflow_1, workflow_2], :timeout => 0)).to eq([workflow_1])
      end
    end

    context "with a workflow that would block for 10 seconds" do
      let(:workflow) { make_workflow(ctx, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}}).start_workflow.tap(&:step_nonblock) }

      it "returns no ready workflows with :timeout => 0" do
        expect(described_class.wait(workflow, :timeout => 0)).to be_empty
      end
    end
  end

  describe "#comment" do
    it "handles no comment" do
      workflow = Floe::Workflow.new({"StartAt" => "First", "States" => {"First" => {"Type" => "Succeed"}}})
      expect(workflow.comment).to be nil
    end

    it "handles a comment" do
      workflow = Floe::Workflow.new({"StartAt" => "First", "Comment" => "great stuff", "States" => {"First" => {"Type" => "Succeed"}}})
      expect(workflow.comment).to eq("great stuff")
    end
  end
end
