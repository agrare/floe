# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Pass < Floe::Workflow::State
        include InputOutputMixin
        include NonTerminalMixin

        attr_reader :end, :next, :result, :parameters, :input_path, :output_path, :result_path

        def initialize(workflow, name, payload)
          super

          validate_query_language_fields!(
            :jsonpath_only => %w[Result Parameters InputPath OutputPath ResultPath],
            :jsonata_only  => %w[Arguments Output Assign]
          )

          @next        = payload["Next"]
          @end         = !!payload["End"]

          if jsonata?
            parse_jsonata_fields(payload)
          else
            @result      = payload["Result"]
            @parameters  = PayloadTemplate.new(payload["Parameters"]) if payload["Parameters"]
            @input_path  = Path.new(payload.fetch("InputPath", "$"))
            @output_path = Path.new(payload.fetch("OutputPath", "$"))
            @result_path = ReferencePath.new(payload.fetch("ResultPath", "$"))
          end

          validate_state!(workflow)
        end

        def finish(context)
          if jsonata?
            # A Pass state has no $states.result
            context.output = process_output_jsonata(context, context.input)
          else
            input = result.nil? ? process_input(context) : result
            context.output = process_output(context, input)
          end
          super
        end

        def running?(_)
          false
        end

        def end?
          @end
        end

        private

        def validate_state!(workflow)
          validate_state_next!(workflow)
        end
      end
    end
  end
end
