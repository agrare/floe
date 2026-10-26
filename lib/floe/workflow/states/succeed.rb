# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Succeed < Floe::Workflow::State
        include JsonataMixin

        attr_reader :input_path, :output_path

        def initialize(workflow, name, payload)
          super

          validate_query_language_fields!(
            :jsonpath_only => %w[InputPath OutputPath],
            :jsonata_only  => %w[Output Assign]
          )

          if jsonata?
            parse_jsonata_fields(payload)
          else
            @input_path  = Path.new(payload.fetch("InputPath", "$"))
            @output_path = Path.new(payload.fetch("OutputPath", "$"))
          end
        end

        def finish(context)
          if jsonata?
            context.output = process_output_jsonata(context, context.input)
          else
            input          = input_path.value(context, context.input)
            context.output = output_path.value(context, input)
          end
          context.next_state = nil

          super
        end

        def running?(_)
          false
        end

        def end?
          true
        end
      end
    end
  end
end
