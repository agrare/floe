# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Map < Floe::Workflow::State
        include ChildWorkflowMixin
        include InputOutputMixin
        include NonTerminalMixin
        include RetryCatchMixin

        attr_reader :end, :next, :parameters, :input_path, :output_path, :result_path,
                    :result_selector, :retry, :catch, :item_processor, :items_path,
                    :item_reader, :item_selector, :item_batcher, :result_writer,
                    :max_concurrency, :tolerated_failure_percentage, :tolerated_failure_count

        def initialize(workflow, name, payload)
          super

          missing_field_error!("InputProcessor") if payload["ItemProcessor"].nil?

          @next            = payload["Next"]
          @end             = !!payload["End"]
          @parameters      = PayloadTemplate.new(payload["Parameters"]) if payload["Parameters"]
          @input_path      = Path.new(payload.fetch("InputPath", "$"))
          @output_path     = Path.new(payload.fetch("OutputPath", "$"))
          @result_path     = ReferencePath.new(payload.fetch("ResultPath", "$"))
          @result_selector = PayloadTemplate.new(payload["ResultSelector"]) if payload["ResultSelector"]
          @retry           = payload["Retry"].to_a.map { |retrier| Retrier.new(retrier) }
          @catch           = payload["Catch"].to_a.map { |catcher| Catcher.new(catcher) }
          @item_processor  = ItemProcessor.new(payload["ItemProcessor"], name)
          @items_path      = ReferencePath.new(payload.fetch("ItemsPath", "$"))
          @item_reader     = ItemReader.new(payload["ItemReader"], name + ["ItemReader"]) if payload["ItemReader"]
          @item_selector   = payload["ItemSelector"]
          @item_batcher    = payload["ItemBatcher"]
          @result_writer   = payload["ResultWriter"]
          @max_concurrency = payload["MaxConcurrency"]&.to_i
          @tolerated_failure_percentage = payload["ToleratedFailurePercentage"]&.to_i
          @tolerated_failure_count      = payload["ToleratedFailureCount"]&.to_i

          validate_state!(workflow)
        end

        def process_input(context)
          input = super
          items_path.value(context, input)
        end

        def start(context)
          super

          input = process_input(context)

          context.state["ItemProcessorContext"] = input.map { |item| Context.new({"Execution" => {"Id" => context.execution["Id"]}}, :input => item.to_json).to_h }
        end

        def end?
          @end
        end

        def success?(context)
          contexts   = each_child_context(context)
          num_failed = contexts.count(&:failed?)
          total      = contexts.count

          return true if num_failed.zero? || total.zero?
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
          max_concurrency && num_running(context) >= max_concurrency
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

        def validate_state!(workflow)
          validate_state_next!(workflow)
          invalid_field_error!("MaxConcurrency", @max_concurrency, "must be greater than 0") if @max_concurrency && @max_concurrency <= 0
        end
      end
    end
  end
end
