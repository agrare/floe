# frozen_string_literal: true

module Floe
  class Workflow
    module States
      module RetryCatchMixin
        def find_retrier(error)
          self.retry.detect { |r| r.match_error?(error) }
        end

        def find_catcher(error)
          self.catch.detect { |c| c.match_error?(error) }
        end

        def retry_state!(context, error)
          retrier = find_retrier(error["Error"]) if error
          return if retrier.nil?

          # If a different retrier is hit reset the context
          if !context["State"].key?("RetryCount") || context["State"]["Retrier"] != retrier.error_equals
            context["State"]["RetryCount"] = 0
            context["State"]["Retrier"]    = retrier.error_equals
          end

          context["State"]["RetryCount"] += 1

          return if context["State"]["RetryCount"] > retrier.max_attempts

          wait_until!(context, :seconds => retrier.sleep_duration(context["State"]["RetryCount"]))
          context.next_state = context.state_name
          context.output     = error
          context.logger.info("Running state: [#{long_name}] with input [#{context.json_input}] got error[#{context.json_output}]...Retry - delay: #{wait_until(context)}")
          true
        end

        def catch_error!(context, error)
          catcher = find_catcher(error["Error"]) if error
          return if catcher.nil?

          context.next_state = catcher.next
          context.output     = catcher.result_path.set(context.input, error)
          context.logger.info("Running state: [#{long_name}] with input [#{context.json_input}]...CatchError - next state: [#{context.next_state}] output: [#{context.json_output}]")

          true
        end

        def fail_workflow!(context, error)
          # next_state is nil, and will be set to nil again in super
          # keeping in here for completeness
          context.next_state = nil
          context.output = error
          context.logger.error("Running state: [#{long_name}] with input [#{context.json_input}]...Complete workflow - output: [#{context.json_output}]")
        end
      end
    end
  end
end
