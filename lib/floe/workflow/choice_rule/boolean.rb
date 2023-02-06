# frozen_string_literal: true

module Floe
  class Workflow
    class ChoiceRule
      class Boolean < Floe::Workflow::ChoiceRule
        def true?(context, input)
          if payload.key?("Not")
            !ChoiceRule.true?(payload["Not"], context, input)
          elsif payload.key?("And")
            payload["And"].all? { |choice| ChoiceRule.true?(choice, context, input) }
          else
            payload["Or"].any? { |choice| ChoiceRule.true?(choice, context, input) }
          end
        end

        def to_dot_label
          if payload.key?("Not")
            "!(#{ChoiceRule.build(payload["Not"]).to_dot_label})"
          elsif payload.key?("And")
            "#{payload["And"].map { |choice| ChoiceRule.build(choice).to_dot_label }.join(" && ")}"
          else
            "#{payload["Or"].map { |choice| ChoiceRule.build(choice).to_dot_label }.join(" || ")}"
          end
        end
      end
    end
  end
end
