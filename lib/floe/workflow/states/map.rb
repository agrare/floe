# frozen_string_literal: true

require_relative "input_output_mixin"
require_relative "non_terminal_mixin"
require_relative "retry_catch_mixin"

module Floe
  class Workflow
    module States
      class Map < Floe::Workflow::State
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
          @item_reader     = payload["ItemReader"]
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

        def finish(context)
          if success?(context)
            result = each_item_processor(context).map(&:output)
            context.output = process_output(context, result)
          else
            error = parse_error(context)
            retry_state!(context, error) || catch_error!(context, error) || fail_workflow!(context, error)
          end

          super
        end

        def run_nonblock!(context)
          start(context) unless context.state_started?

          loop while step_nonblock!(context) == 0 && running?(context)
          return Errno::EAGAIN unless ready?(context)

          finish(context) if ended?(context)
        end

        def end?
          @end
        end

        def ready?(context)
          !context.state_started? || each_item_processor(context).any? { |ctx| item_processor.step_nonblock_ready?(ctx) }
        end

        def wait_until(context)
          each_item_processor(context).filter_map { |ctx| item_processor.wait_until(ctx) }.min
        end

        def waiting?(context)
          each_item_processor(context).any? { |ctx| item_processor.waiting?(ctx) }
        end

        def running?(context)
          !ended?(context)
        end

        def ended?(context)
          each_item_processor(context).all?(&:ended?)
        end

        def success?(context)
          contexts   = each_item_processor(context)
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

        def each_item_processor(context)
          context.state["ItemProcessorContext"].map { |ctx| Context.new(ctx) }
        end

        def step_nonblock!(context)
          child_contexts = each_item_processor(context)

          child_contexts.each do |ctx|
            num_running = child_contexts.count(&:running?)
            # If this iteration isn't already running and we can't start any more
            next if !ctx.running? && max_concurrency && num_running >= max_concurrency
            # If the current iteration is running but not ready
            next unless item_processor.step_nonblock_ready?(ctx)

            item_processor.run_nonblock(ctx)
          end

          ended?(context) ? 0 : Errno::EAGAIN
        end

        def parse_error(context)
          # If ToleratedFailureCount or ToleratedFailurePercentage is present
          # then use States.ExceedToleratedFailureThreshold otherwise
          # take the error from the first failed state
          if tolerated_failure_count || tolerated_failure_percentage
            {"Error" => "States.ExceedToleratedFailureThreshold"}
          else
            each_item_processor(context).detect(&:failed?)&.output || {"Error" => "States.Error"}
          end
        end

        def validate_state!(workflow)
          validate_state_next!(workflow)
          invalid_field_error!("MaxConcurrency", @max_concurrency, "must be greater than 0") if @max_concurrency && @max_concurrency <= 0
        end
      end
    end
  end
end
