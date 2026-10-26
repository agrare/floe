# frozen_string_literal: true

require "active_support/core_ext/object/deep_dup"

module Floe
  class Workflow
    module States
      class Map < Floe::Workflow::State
        include ChildWorkflowMixin
        include InputOutputMixin
        include NonTerminalMixin
        include RetryCatchMixin

        attr_reader :end, :next, :parameters, :input_path, :output_path, :result_path,
                    :result_selector, :retry, :catch, :item_processor, :items_path, :items,
                    :item_reader, :item_selector, :item_batcher, :result_writer,
                    :max_concurrency, :tolerated_failure_percentage, :tolerated_failure_count

        def initialize(workflow, name, payload)
          super

          missing_field_error!("InputProcessor") if payload["ItemProcessor"].nil?

          validate_query_language_fields!(
            :jsonpath_only => %w[Parameters InputPath OutputPath ResultPath ResultSelector ItemsPath],
            :jsonata_only  => %w[Arguments Output Assign Items]
          )
          validate_jsonata_unsupported_fields! if jsonata?

          @next            = payload["Next"]
          @end             = !!payload["End"]
          @retry           = payload["Retry"].to_a.map.with_index { |retrier, i| Retrier.new(workflow, name + ["Retry", i.to_s], retrier) }
          @catch           = payload["Catch"].to_a.map.with_index { |catcher, i| Catcher.new(workflow, name + ["Catch", i.to_s], catcher, :query_language => query_language) }
          @item_processor  = ItemProcessor.new(payload["ItemProcessor"], name, :query_language => query_language)
          @item_reader     = payload["ItemReader"]
          @result_writer   = payload["ResultWriter"]

          if jsonata?
            parse_jsonata_fields(payload)
            @items                        = parse_jsonata_items(payload["Items"])
            @item_selector                = JsonataTemplate.new(payload["ItemSelector"], name + ["ItemSelector"]) if payload["ItemSelector"]
            @max_concurrency              = parse_jsonata_integer(payload["MaxConcurrency"])
            @tolerated_failure_percentage = parse_jsonata_integer(payload["ToleratedFailurePercentage"])
            @tolerated_failure_count      = parse_jsonata_integer(payload["ToleratedFailureCount"])
          else
            @parameters      = PayloadTemplate.new(payload["Parameters"]) if payload["Parameters"]
            @input_path      = Path.new(payload.fetch("InputPath", "$"))
            @output_path     = Path.new(payload.fetch("OutputPath", "$"))
            @result_path     = ReferencePath.new(payload.fetch("ResultPath", "$"))
            @result_selector = PayloadTemplate.new(payload["ResultSelector"]) if payload["ResultSelector"]
            @items_path      = ReferencePath.new(payload.fetch("ItemsPath", "$"))
            @item_selector   = PayloadTemplate.new(payload["ItemSelector"]) if payload["ItemSelector"]
            @item_batcher    = ItemBatcher.new(payload["ItemBatcher"], name + ["ItemBatcher"]) if payload["ItemBatcher"]
            @max_concurrency = payload["MaxConcurrency"]&.to_i
            @tolerated_failure_percentage = payload["ToleratedFailurePercentage"]&.to_i
            @tolerated_failure_count      = payload["ToleratedFailureCount"]&.to_i
          end

          validate_state!(workflow)
        end

        def process_input(context)
          return process_input_jsonata_items(context) if jsonata?

          input = super
          input = items_path.value(context, input)
          input = item_batcher.value(context, input, context.state["Input"]) if item_batcher
          input
        end

        def start(context)
          super

          input = process_input(context)

          context.state["ItemProcessorContext"] = input.map.with_index do |item, index|
            item_processor_context = {
              "Execution" => {
                "Id" => context.execution["Id"]
              },
              "Map"       => {
                "Item" => {"Index" => index, "Value" => item}
              },
              "Variables" => context.variables.deep_dup
            }

            item_processor_input = item_selector ? item_selector_value(context, item_processor_context) : item

            Context.new(item_processor_context, :input => item_processor_input.to_json).to_h
          end
        end

        def end?
          @end
        end

        def success?(context)
          contexts   = each_child_context(context)
          num_failed = contexts.count(&:failed?)
          total      = contexts.count

          return true if num_failed.zero? || total.zero?

          tolerated_failure_count      = tolerated_failure_value(context, "ToleratedFailureCount", @tolerated_failure_count)
          tolerated_failure_percentage = tolerated_failure_value(context, "ToleratedFailurePercentage", @tolerated_failure_percentage)
          return false if tolerated_failure_count.nil? && tolerated_failure_percentage.nil?

          # Some have failed, check the tolerated_failure thresholds to see if
          # we should fail the whole state.
          #
          # If either ToleratedFailureCount or ToleratedFailurePercentage are breached
          # then the whole state is considered failed.
          count_tolerated = tolerated_failure_count.nil?      || num_failed < tolerated_failure_count
          pct_tolerated   = tolerated_failure_percentage.nil? || tolerated_failure_percentage == 100 ||
                            ((100 * num_failed / total.to_f) < tolerated_failure_percentage)

          count_tolerated && pct_tolerated
        end

        private

        def step_nonblock!(context)
          each_child_context(context).each do |ctx|
            # If this iteration isn't already running and we can't start any more
            next if !ctx.started? && concurrency_exceeded?(context)

            item_processor.run_nonblock(ctx) if item_processor.step_nonblock_ready?(ctx)
          end
        end

        def each_child_workflow(context)
          each_child_context(context).map do |ctx|
            [item_processor, Context.new(ctx)]
          end
        end

        def concurrency_exceeded?(context)
          max = evaluate_jsonata_value(context, max_concurrency)
          return false if max.nil?

          runtime_field_error!("MaxConcurrency", max, "must be a positive integer", :floe_error => "States.QueryEvaluationError") unless max.kind_of?(Integer) && max.positive?

          num_running(context) >= max
        end

        def tolerated_failure_value(context, field, value)
          value = evaluate_jsonata_value(context, value)
          return value if value.nil?

          runtime_field_error!(field, value, "must be a non-negative integer", :floe_error => "States.QueryEvaluationError") unless value.kind_of?(Integer) && !value.negative?

          value
        end

        def num_running(context)
          each_child_context(context).count(&:running?)
        end

        def parse_error(context)
          # If ToleratedFailureCount or ToleratedFailurePercentage is present
          # then use States.ExceedToleratedFailureThreshold otherwise
          # take the error from the first failed state
          if tolerated_failure_count || tolerated_failure_percentage
            {"Error" => "States.ExceedToleratedFailureThreshold"}
          else
            each_child_context(context).detect(&:failed?)&.output || {"Error" => "States.Error"}
          end
        end

        def child_context_key
          "ItemProcessorContext"
        end

        # In JSONata, Items is an array or an expression which evaluates to an array.
        # When it isn't given the items are the state input.
        def process_input_jsonata_items(context)
          items = items_value(context)
          return items if items.kind_of?(Array)

          runtime_field_error!("Items", items.inspect, "must be an array", :floe_error => "States.QueryEvaluationError")
        end

        def items_value(context)
          return context.input unless payload.key?("Items")

          items.kind_of?(JsonataExpression) ? items.value(jsonata_bindings(context)) : items
        end

        def item_selector_value(context, item_context)
          return item_selector.value(item_context, context.state["Input"]) unless jsonata?

          # $states.context.Map.Item is available to ItemSelector
          bindings = jsonata_bindings(context)
          bindings["states"]["context"] = bindings["states"]["context"].merge("Map" => item_context["Map"])
          item_selector.value(bindings)
        end

        def parse_jsonata_items(value)
          return value if value.nil? || value.kind_of?(Array)

          expression = parse_jsonata_value(value)
          invalid_field_error!("Items", value, "must be an array or a JSONata expression") unless expression.kind_of?(JsonataExpression)

          expression
        end

        def parse_jsonata_integer(value)
          parse_jsonata_value(value)
        end

        def validate_jsonata_unsupported_fields!
          %w[Arguments ItemBatcher].each do |field|
            invalid_field_error!(field, nil, "is not supported for a Map state when QueryLanguage is \"JSONata\"") if payload.key?(field)
          end
        end

        def validate_state!(workflow)
          validate_state_next!(workflow)
          validate_state_max_concurrency!
        end

        def validate_state_max_concurrency!
          return if @max_concurrency.nil? || @max_concurrency.kind_of?(JsonataExpression)

          invalid_field_error!("MaxConcurrency", @max_concurrency, "must be greater than 0") if @max_concurrency <= 0
        end
      end
    end
  end
end
