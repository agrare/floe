# frozen_string_literal: true

module Floe
  class Workflow
    class Retrier
      include ErrorMatcherMixin
      include ValidationMixin

      attr_reader :error_equals, :interval_seconds, :max_attempts, :backoff_rate, :name

      def initialize(_workflow, name, payload)
        @name             = name
        @payload          = payload

        @error_equals     = payload["ErrorEquals"]
        @interval_seconds = payload["IntervalSeconds"] || 1.0
        @max_attempts     = payload["MaxAttempts"] || 3
        @backoff_rate     = payload["BackoffRate"] || 2.0

        validate_retrier!
      end

      # @param [Integer] attempt 1 for the first attempt
      def sleep_duration(attempt)
        interval_seconds * (backoff_rate**(attempt - 1))
      end

      private

      def validate_retrier!
        validate_error_equals!

        interval_seconds = @payload["IntervalSeconds"]
        max_attempts     = @payload["MaxAttempts"]
        backoff_rate     = @payload["BackoffRate"]

        invalid_field_error!("IntervalSeconds", interval_seconds, "must be a positive integer") if interval_seconds && !(interval_seconds.kind_of?(Integer) && interval_seconds.positive?)
        invalid_field_error!("MaxAttempts", max_attempts, "must be a non-negative integer")     if max_attempts && !(max_attempts.kind_of?(Integer) && max_attempts >= 0)
        invalid_field_error!("BackoffRate", backoff_rate, "must be a number greater than or equal to 1.0") if backoff_rate && !(backoff_rate.kind_of?(Numeric) && backoff_rate >= 1.0)
      end
    end
  end
end
