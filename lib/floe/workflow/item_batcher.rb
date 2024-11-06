# frozen_string_literal: true

module Floe
  class Workflow
    class ItemBatcher
      include ValidationMixin

      attr_reader :name, :batch_input, :max_items_per_batch, :max_items_per_batch_path, :max_input_bytes_per_batch, :max_input_bytes_per_batch_path

      def initialize(payload, name)
        @name = name

        @batch_input               = PayloadTemplate.new(payload["BatchInput"]) if payload["BatchInput"]
        @max_items_per_batch       = payload["MaxItemsPerBatch"]
        @max_input_bytes_per_batch = payload["MaxInputBytesPerBatch"]

        @max_items_per_batch_path       = ReferencePath.new(payload["MaxItemsPerBatchPath"])      if payload["MaxItemsPerBatchPath"]
        @max_input_bytes_per_batch_path = ReferencePath.new(payload["MaxInputBytesPerBatchPath"]) if payload["MaxInputBytesPerBatchPath"]

        if [max_items_per_batch, max_input_bytes_per_batch, max_items_per_batch_path, max_input_bytes_per_batch_path].all?(&:nil?)
          parser_error!("must have one of \"MaxItemsPerBatch\", \"MaxItemsPerBatchPath\", \"MaxInputBytesPerBatch\", \"MaxInputBytesPerBatchPath\"")
        end

        parser_error!("must not specify both \"MaxItemsPerBatch\" and \"MaxItemsPerBatchPath\"")               if max_items_per_batch && max_items_per_batch_path
        parser_error!("must not specify both \"MaxInputBytesPerBatch\" and \"MaxInputBytesPerBatchPath\"")     if max_input_bytes_per_batch && max_input_bytes_per_batch_path
        invalid_field_error!("MaxItemsPerBatch", max_items_per_batch, "must be a positive integer")            if max_items_per_batch && max_items_per_batch <= 0
        invalid_field_error!("MaxInputBytesPerBatch", max_input_bytes_per_batch, "must be a positive integer") if max_input_bytes_per_batch && max_input_bytes_per_batch <= 0
      end

      def value(context, input, state_input = nil)
        state_input ||= input

        max_items       = max_items_per_batch       || max_items_per_batch_path&.value(context, state_input)
        max_input_bytes = max_input_bytes_per_batch || max_input_bytes_per_batch_path&.value(context, state_input)

        raise runtime_field_error!("MaxItemsPerBatchPath", max_items, "must be a positive integer")            if max_items && max_items <= 0
        raise runtime_field_error!("MaxInputBytesPerBatchPath", max_input_bytes, "must be a positive integer") if max_input_bytes && max_input_bytes <= 0

        output = batch_input ? batch_input.value(context, state_input) : {}

        input.each_slice(max_items).map do |batch|
          output.merge("Items" => batch)
        end
      end
    end
  end
end
