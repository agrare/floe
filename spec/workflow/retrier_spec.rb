RSpec.describe Floe::Workflow::Retrier do
  let(:input) { {} }
  let(:ctx) { Floe::Workflow::Context.new(:input => input.to_json) }
  let(:resource) { "docker://hello-world:latest" }
  let(:workflow) do
    make_workflow(
      ctx, {
        "State"        => {
          "Type"     => "Task",
          "Resource" => resource,
          "Retry"    => retriers,
          "Next"     => "SuccessState"
        }.compact,
        "FirstState"   => {"Type" => "Succeed"},
        "SuccessState" => {"Type" => "Succeed"},
        "FailState"    => {"Type" => "Succeed"}
      }
    )
  end

  let(:retriers) { [{"ErrorEquals" => ["States.ALL"]}] }
  subject { workflow.start_workflow.current_state.retry.first }

  {1 => 1, 2 => 2, 3 => 4}.each do |attempt, duration|
    it "try #{attempt} takes #{duration}" do
      expect(subject.sleep_duration(attempt)).to eq(duration)
    end
  end

  describe "validation" do
    def self.invalid(description, retrier, message)
      context "with #{description}" do
        let(:retriers) { [{"ErrorEquals" => ["Exception"]}.merge(retrier)] }
        it { expect { subject }.to raise_error(Floe::InvalidWorkflowError, "States.State.Retry.0 #{message}") }
      end
    end

    def self.valid(description, retrier)
      context "with #{description}" do
        let(:retriers) { [{"ErrorEquals" => ["Exception"]}.merge(retrier)] }
        it { expect { subject }.not_to raise_error }
      end
    end

    invalid "an ErrorEquals with States.ALL and another error", {"ErrorEquals" => ["States.ALL", "Exception"]}, "field \"ErrorEquals\" must contain \"States.ALL\" alone"
    valid   "an ErrorEquals with only States.ALL", {"ErrorEquals" => ["States.ALL"]}

    valid   "an IntervalSeconds of 1", {"IntervalSeconds" => 1}
    invalid "an IntervalSeconds of 0", {"IntervalSeconds" => 0}, "field \"IntervalSeconds\" value \"0\" must be a positive integer"
    invalid "a negative IntervalSeconds", {"IntervalSeconds" => -1}, "field \"IntervalSeconds\" value \"-1\" must be a positive integer"
    invalid "a non-integer IntervalSeconds", {"IntervalSeconds" => 1.5}, "field \"IntervalSeconds\" value \"1.5\" must be a positive integer"
    invalid "a string IntervalSeconds", {"IntervalSeconds" => "1"}, "field \"IntervalSeconds\" value \"1\" must be a positive integer"

    valid   "a MaxAttempts of 0", {"MaxAttempts" => 0}
    valid   "a MaxAttempts of 3", {"MaxAttempts" => 3}
    invalid "a negative MaxAttempts", {"MaxAttempts" => -1}, "field \"MaxAttempts\" value \"-1\" must be a non-negative integer"
    invalid "a non-integer MaxAttempts", {"MaxAttempts" => 1.5}, "field \"MaxAttempts\" value \"1.5\" must be a non-negative integer"
    invalid "a string MaxAttempts", {"MaxAttempts" => "3"}, "field \"MaxAttempts\" value \"3\" must be a non-negative integer"

    valid   "a BackoffRate of 1", {"BackoffRate" => 1}
    valid   "a BackoffRate of 1.5", {"BackoffRate" => 1.5}
    invalid "a BackoffRate less than 1.0", {"BackoffRate" => 0.5}, "field \"BackoffRate\" value \"0.5\" must be a number greater than or equal to 1.0"
    invalid "a negative BackoffRate", {"BackoffRate" => -2}, "field \"BackoffRate\" value \"-2\" must be a number greater than or equal to 1.0"
    invalid "a string BackoffRate", {"BackoffRate" => "2"}, "field \"BackoffRate\" value \"2\" must be a number greater than or equal to 1.0"
  end

  # https://docs.aws.amazon.com/step-functions/latest/dg/concepts-error-handling.html
  # For example, say your IntervalSeconds is 3, MaxAttempts is 3, and BackoffRate is 2.
  # The first retry attempt takes place three seconds after the error occurs.
  # The second retry takes place six seconds after the first retry attempt.
  # While the third retry takes place 12 seconds after the second retry attempt.
  context "with values specified" do
    let(:retriers) do
      [{
        "IntervalSeconds" => 3,
        "BackoffRate"     => 2,
        "MaxAttempts"     => 3,
        "ErrorEquals"     => ["States.ALL"]
      }]
    end

    {1 => 3, 2 => 6, 3 => 12}.each do |attempt, duration|
      it "try #{attempt} takes #{duration}" do
        expect(subject.sleep_duration(attempt)).to eq(duration)
      end
    end
  end
end
