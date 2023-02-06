# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Choice < Floe::Workflow::State
        attr_reader :choices, :default, :input_path, :output_path

        def initialize(workflow, name, payload)
          super

          @choices = payload["Choices"].map { |choice| ChoiceRule.build(choice) }
          @default = payload["Default"]

          @input_path  = Path.new(payload.fetch("InputPath", "$"))
          @output_path = Path.new(payload.fetch("OutputPath", "$"))
        end

        def run!(*)
          super do |input|
            next_state_name = choices.detect { |choice| choice.true?(context, input) }&.next || default
            next_state      = workflow.states_by_name[next_state_name]

            output = input

            [output, next_state]
          end
        end

        private def to_dot_attributes
          super.merge(:shape => "diamond")
        end

        def to_dot_transitions
          [].tap do |a|
            choices.each do |choice|
              choice_label = choice.to_dot_label
              a << "  #{name} -> #{choice.next} [ label=#{choice_label.inspect} ]"
            end

            a << "  #{name} -> #{default} [ label=\"Default\" ]" if default
          end
        end
      end
    end
  end
end
