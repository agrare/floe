# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Succeed < Floe::Workflow::State
        attr_reader :input_path, :output_path

        def initialize(workflow, name, payload)
          super

          @end = true
        end

        def run!(input)
          [nil, input]
        end

        def terminal?
          true
        end
      end
    end
  end
end
