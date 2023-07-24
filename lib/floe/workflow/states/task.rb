# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Task < Floe::Workflow::State
        attr_reader :credentials, :end, :heartbeat_seconds, :next, :parameters,
                    :result_selector, :resource, :timeout_seconds, :retry, :catch,
                    :input_path, :output_path, :result_path

        def initialize(workflow, name, payload)
          super

          @end               = payload["End"]
          @heartbeat_seconds = payload["HeartbeatSeconds"]
          @next              = payload["Next"]
          @resource          = payload["Resource"]
          @timeout_seconds   = payload["TimeoutSeconds"]
          @retry             = payload["Retry"].to_a.map { |retrier| Retrier.new(retrier) }
          @catch             = payload["Catch"].to_a.map { |catcher| Catcher.new(catcher) }
          @input_path        = Path.new(payload.fetch("InputPath", "$"))
          @output_path       = Path.new(payload.fetch("OutputPath", "$"))
          @result_path       = ReferencePath.new(payload.fetch("ResultPath", "$"))
          @parameters        = PayloadTemplate.new(payload["Parameters"])     if payload["Parameters"]
          @result_selector   = PayloadTemplate.new(payload["ResultSelector"]) if payload["ResultSelector"]
          @credentials       = PayloadTemplate.new(payload["Credentials"])    if payload["Credentials"]
        end

        def run!(input)
          input = input_path.value(context, input)
          input = parameters.value(context, input) if parameters

          runner = Floe::Workflow::Runner.for_resource(resource)
          _exit_status, results = runner.run!(resource, input, credentials&.value({}, workflow.credentials))

          output = process_output!(input, results)
          [@next, output]
        rescue => err
          retrier = self.retry.detect { |r| (r.error_equals & [err.to_s, "States.ALL"]).any? }
          retry if retry!(retrier)

          catcher = self.catch.detect { |c| (c.error_equals & [err.to_s, "States.ALL"]).any? }
          raise if catcher.nil?

          [catcher.next, output]
        end

        def terminal?
          !!@end
        end

        private

        def retry!(retrier)
          return if retrier.nil?

          # If a different retrier is hit reset the context
          if !context["State"].key?("RetryCount") || context["State"]["Retrier"] != retrier.error_equals
            context["State"]["RetryCount"] = 0
            context["State"]["Retrier"]    = retrier.error_equals
          end

          context["State"]["RetryCount"] += 1

          return if context["State"]["RetryCount"] > retrier.max_attempts

          Kernel.sleep(retrier.sleep_duration(context["State"]["RetryCount"]))
          true
        end

        def process_output!(output, results)
          return output if results.nil?
          return if output_path.nil?

          begin
            results = JSON.parse(results)
          rescue JSON::ParserError
            results = {"results" => results}
          end

          results = result_selector.value(context, results) if result_selector
          output  = result_path.set(output, results)
          output_path.value(context, output)
        end
      end
    end
  end
end
