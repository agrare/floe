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
