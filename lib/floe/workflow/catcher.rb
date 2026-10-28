# frozen_string_literal: true

module Floe
  class Workflow
    class Catcher
      include ErrorMatcherMixin
      include ValidationMixin

      attr_reader :error_equals, :next, :result_path, :name

      def initialize(workflow, name, payload)
        @name         = name
        @payload      = payload

        @error_equals = payload["ErrorEquals"]
        @next         = payload["Next"]
        @result_path  = ReferencePath.new(payload.fetch("ResultPath", "$"))

        validate_error_equals!
        validate_state_next!(workflow)
      end

      private

      def validate_state_next!(workflow)
        missing_field_error!("Next") if @next.nil?
        invalid_field_error!("Next", @next, "is not found in \"States\"") if @next && !workflow.state?(@next)
      end
    end
  end
end
