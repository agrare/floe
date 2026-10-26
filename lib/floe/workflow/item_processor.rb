# frozen_string_literal: true

module Floe
  class Workflow
    class ItemProcessor < Floe::WorkflowBase
      attr_reader :processor_config

      def initialize(payload, name = nil, query_language: nil)
        super
        @processor_config = payload.fetch("ProcessorConfig", "INLINE")
      end
    end
  end
end
