# frozen_string_literal: true

module Floe
  class Workflow
    # Methods for common error handling
    module ErrorMatcherMixin
      # @param [String] error the error thrown
      def match_error?(error)
        return false if error == "States.Runtime"
        return true if error_equals.include?("States.ALL")
        return true if error_equals.include?("States.Timeout") && error == "States.HeartbeatTimeout"

        error_equals.include?(error)
      end

      private

      def validate_error_equals!
        missing_field_error!("ErrorEquals") if !error_equals.kind_of?(Array) || error_equals.empty?
        invalid_field_error!("ErrorEquals", nil, "must contain \"States.ALL\" alone") if error_equals.include?("States.ALL") && error_equals.size > 1
      end
    end
  end
end
