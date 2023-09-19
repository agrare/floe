require 'active_support/time'

RSpec.describe Floe::Workflow do
  let(:now)     { Time.now.utc }
  let(:input)   { {"input" => "value"}.freeze }
  let(:context) { Floe::Workflow::Context.new(:input => input) }

  describe "#new" do
    it "sets initial state" do
      workflow = make_workflow(input, {"FirstState" => {"Type" => "Succeed"}})

      expect(workflow.status).to eq("pending")
      expect(workflow.end?).to eq(false)

      expect(context.status).to eq("pending")
      expect(context.started?).to eq(false)
      expect(context.running?).to eq(false)
      expect(context.ended?).to eq(false)
    end

    # I would prefer this not be here, but it is, so lets test it
    it "sets context to proper start_at" do
      workflow = make_workflow(input, {"FirstState" => {"Type" => "Succeed"}})
      expect(context.state_name).to eq("FirstState")
      expect(context.input).to eq(input)
    end
  end

  describe "#run!" do
    it "sets execution variables for success" do
      workflow = make_workflow(input, {"FirstState" => {"Type" => "Succeed"}})
      workflow.run!

      # state
      expect(context.state["EnteredTime"]).to be_within(1.second).of(now)
      expect(context.state["Guid"]).to be
      expect(context.state_name).to eq("FirstState")
      expect(context.input).to eq(input)
      expect(context.output).to eq(input)
      expect(context.state["FinishedTime"]).to be_within(1.second).of(now)
      expect(context.state["Duration"]).to be <= 1
      expect(context.status).to eq("success")

      # execution
      expect(context.started?).to eq(true)
      expect(context.running?).to eq(false)
      expect(context.ended?).to eq(true)

      # final results
      expect(workflow.output).to eq(input)
      expect(workflow.status).to eq("success")
      expect(workflow.end?).to eq(true)
    end

    it "sets execution variables for failure" do
      workflow = make_workflow(input, {"FirstState" => {"Type" => "Fail", "Cause" => "Bad Stuff", "Error" => "Issue"}})
      workflow.run!

      # state
      expect(context.state["EnteredTime"]).to be_within(1.second).of(now)
      expect(context.state["Guid"]).to be
      expect(context.state_name).to eq("FirstState")
      expect(context.input).to eq(input)
      expect(context.output).to eq(input)
      expect(context.state["FinishedTime"]).to be_within(1.second).of(now)
      expect(context.state["Duration"]).to be <= 1
      expect(context.state["Cause"]).to eq("Bad Stuff")
      expect(context.state["Error"]).to eq("Issue")
      expect(context.status).to eq("failure")

      # execution
      expect(context.started?).to eq(true)
      expect(context.running?).to eq(false)
      expect(context.ended?).to eq(true)

      # final results
      expect(workflow.output).to eq(input)
      expect(workflow.status).to eq("failure")
      expect(workflow.end?).to eq(true)
    end
  end

  describe "#run_nonblock" do
    it "starts the first state" do
      workflow = make_workflow(input, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})
      workflow.run_nonblock

      expect(context.started?).to eq(true)
    end

    it "doesn't wait for the state to finish" do
      workflow = make_workflow(input, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})
      workflow.run_nonblock

      expect(context.running?).to eq(true)
      expect(context.ended?).to   eq(false)
    end
  end

  describe "#step" do
    it "runs a success step" do
      workflow = make_workflow(input, {"FirstState" => {"Type" => "Succeed"}})

      expect(workflow.status).to eq("pending")
      expect(workflow.end?).to eq(false)
      expect(context.status).to eq("pending")
      expect(context.started?).to eq(false)
      expect(context.running?).to eq(false)
      expect(context.ended?).to eq(false)

      workflow.step

      expect(workflow.output).to eq(input)
      expect(workflow.status).to eq("success")
      expect(workflow.end?).to eq(true)
      expect(context.output).to eq(input)
      expect(context.status).to eq("success")
      expect(context.started?).to eq(true)
      expect(context.running?).to eq(false)
      expect(context.ended?).to eq(true)
    end
  end

  describe "#step_nonblock" do
    context "with a workflow that hasn't started yet" do
      it "starts the first step" do
        workflow = make_workflow(input, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})
        workflow.step_nonblock

        expect(workflow.status).to eq("running")
        expect(workflow.end?).to   eq(false)
      end
    end

    context "with a running state" do
      it "returns Try again" do
        workflow = make_workflow(input, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})
        expect(workflow.step_nonblock).to eq(Errno::EAGAIN)
      end
    end

    context "with a state that has finished" do
      it "completes the final tasks for a state" do
        workflow = make_workflow(input, {"FirstState" => {"Type" => "Wait", "Seconds" => 10, "End" => true}})

        # Start the workflow
        workflow.run_nonblock

        # Mark the Wait state as having started 1 minute ago
        context.state["EnteredTime"] = Time.now.utc - 60

        # step_nonblock should return 0 and mark the workflow as completed
        expect(workflow.step_nonblock).to eq(0)

        expect(workflow.output).to eq(input)
        expect(workflow.status).to eq("success")
        expect(workflow.end?).to eq(true)
        expect(context.output).to eq(input)
        expect(context.status).to eq("success")
        expect(context.started?).to eq(true)
        expect(context.running?).to eq(false)
        expect(context.ended?).to eq(true)
      end
    end

    it "return Operation not permitted if workflow has ended" do
      workflow = make_workflow(input, {"FirstState" => {"Type" => "Succeed"}})

      context.execution["EndTime"] = Time.now.utc

      expect(workflow.step_nonblock).to eq(Errno::EPERM)
    end
  end

  describe "#step_nonblock_wait" do
    context "with a state that hasn't started yet" do
      it "returns 0" do
        workflow = make_workflow(input, {"FirstState" => {"Type" => "Succeed"}})
        expect(workflow.step_nonblock_wait).to eq(0)
      end
    end

    context "with a state that has finished" do
      it "return 0" do
        context.state["EnteredTime"] = Time.now.utc
        workflow = make_workflow(input, {"FirstState" => {"Type" => "Succeed"}})
        expect(workflow.current_state).to receive(:running?).and_return(false)
        expect(workflow.step_nonblock_wait).to eq(0)
      end
    end

    context "with a state that is running" do
      it "returns Try again" do
        context.state["EnteredTime"] = Time.now.utc
        workflow = make_workflow(input, {"FirstState" => {"Type" => "Task", "Resource" => "docker://agrare/hello-world:latest"}})
        expect(workflow.current_state).to receive(:running?).and_return(true)
        expect(workflow.step_nonblock_wait(:timeout => 0)).to eq(Errno::EAGAIN)
      end
    end
  end

  describe "#step_nonblock_ready?" do
    context "with a state that hasn't started yet" do
      it "returns true" do
        workflow = make_workflow(input, {"FirstState" => {"Type" => "Succeed"}})
        expect(workflow.step_nonblock_ready?).to be_truthy
      end
    end

    context "with a state that has finished" do
      it "return true" do
        context.state["EnteredTime"] = Time.now.utc
        workflow = make_workflow(input, {"FirstState" => {"Type" => "Succeed"}})
        expect(workflow.current_state).to receive(:running?).and_return(false)
        expect(workflow.step_nonblock_ready?).to be_truthy
      end
    end

    context "with a state that is running" do
      it "returns false" do
        context.state["EnteredTime"] = Time.now.utc
        workflow = make_workflow(input, {"FirstState" => {"Type" => "Task", "Resource" => "docker://agrare/hello-world:latest"}})
        expect(workflow.current_state).to receive(:running?).and_return(true)
        expect(workflow.step_nonblock_ready?).to be_falsey
      end
    end
  end

  private

  def make_workflow(input, payload, creds: {})
    Floe::Workflow.new(make_payload(payload), context, creds)
  end

  def make_payload(states)
    start_at ||= states.keys.first

    {
      "Comment" => "Sample",
      "StartAt" => start_at,
      "States"  => states
    }
  end
end
