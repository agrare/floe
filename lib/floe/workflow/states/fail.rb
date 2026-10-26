# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Fail < Floe::Workflow::State
        include JsonataMixin

        attr_reader :cause, :error, :cause_path, :error_path

        def initialize(workflow, name, payload)
          super

          validate_query_language_fields!(
            :jsonpath_only => %w[CausePath ErrorPath],
            :jsonata_only  => []
          )

          @cause      = parse_jsonata_value(payload["Cause"])
          @error      = parse_jsonata_value(payload["Error"])
          @cause_path = Path.new(payload["CausePath"]) if payload["CausePath"]
          @error_path = Path.new(payload["ErrorPath"]) if payload["ErrorPath"]
        end

        def finish(context)
          context.next_state = nil
          # TODO: support intrinsic functions here
          # see https://docs.aws.amazon.com/step-functions/latest/dg/amazon-states-language-fail-state.html
          #     https://docs.aws.amazon.com/step-functions/latest/dg/amazon-states-language-intrinsic-functions.html#asl-intrsc-func-generic
          context.output     = {
            "Error" => error_value(context),
            "Cause" => cause_value(context)
          }.compact
          super
        end

        def running?(_)
          false
        end

        def end?
          true
        end

        private

        def error_value(context)
          return evaluate_jsonata_value(context, error) if jsonata?

          @error_path ? @error_path.value(context, context.input) : error
        end

        def cause_value(context)
          return evaluate_jsonata_value(context, cause) if jsonata?

          @cause_path ? @cause_path.value(context, context.input) : cause
        end
      end
    end
  end
end
