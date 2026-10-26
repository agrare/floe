# frozen_string_literal: true

module Floe
  class Workflow
    module States
      module InputOutputMixin
        include JsonataMixin

        def process_input(context)
          return process_input_jsonata(context) if jsonata?

          input = input_path.value(context, context.input)
          input = parameters.value(context, input) if parameters
          input
        end

        def process_output(context, results)
          return process_output_jsonata(context, results, :result => results) if jsonata?

          return context.input.dup if results.nil?
          return if output_path.nil?

          results = result_selector.value(context, results) if @result_selector
          if result_path.payload.match?(/^\$\$\.Credentials\b/)
            context.credentials.merge!(result_path.set(context.credentials, results))
            output = context.input.dup
          else
            output = result_path.set(context.input.dup, results)
          end

          output_path.value(context, output)
        end

        private

        # In JSONata the input to the state is $states.input unless Arguments is given
        def process_input_jsonata(context)
          arguments ? arguments.value(jsonata_bindings(context)) : context.input
        end
      end
    end
  end
end
