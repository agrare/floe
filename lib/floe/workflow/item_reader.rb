# frozen_string_literal: true

module Floe
  class Workflow
    class ItemReader
      include ValidationMixin

      attr_reader :name, :resource, :parameters, :reader_config, :max_items, :runner

      def initialize(payload, name)
        @name          = name
        @resource      = payload["Resource"]
        @parameters    = PayloadTemplate.new(payload["Parameters"]) if payload["Parameters"]
        @reader_config = payload["ReaderConfig"] || {}
        @max_items     = reader_config["MaxItems"]

        missing_field_error!("Resource") unless @resource.kind_of?(String)
        invalid_field_error!("ReaderConfig.MaxItems", @max_items, "must be positive") if @max_items && @max_items < 0

        @runner = wrap_parser_error("Resource", @resource) { Floe::Runner.for_resource(@resource) }
      end
    end
  end
end
