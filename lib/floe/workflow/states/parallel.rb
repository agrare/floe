# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Parallel < Floe::Workflow::State
        include ChildWorkflowMixin
        include InputOutputMixin
        include NonTerminalMixin
        include RetryCatchMixin

        attr_reader :end, :next, :parameters, :input_path, :output_path, :result_path,
                    :result_selector, :retry, :catch, :branches

        def initialize(workflow, name, payload)
          super

          missing_field_error!("Branches") if payload["Branches"].nil?

          @next            = payload["Next"]
          @end             = !!payload["End"]
          @parameters      = PayloadTemplate.new(payload["Parameters"]) if payload["Parameters"]
          @input_path      = Path.new(payload.fetch("InputPath", "$"))
          @output_path     = Path.new(payload.fetch("OutputPath", "$"))
          @result_path     = ReferencePath.new(payload.fetch("ResultPath", "$"))
          @result_selector = PayloadTemplate.new(payload["ResultSelector"]) if payload["ResultSelector"]
          @retry           = payload["Retry"].to_a.map { |retrier| Retrier.new(retrier) }
          @catch           = payload["Catch"].to_a.map { |catcher| Catcher.new(catcher) }
          @branches        = payload["Branches"].map { |branch| Branch.new(branch) }

          validate_state!(workflow)
        end

        def start(context)
          super

          input = process_input(context)

          context.state["BranchContext"] = branches.map { |_branch| Context.new({"Execution" => {"Id" => context.execution["Id"]}}, :input => input.to_json).to_h }
        end

        def end?
          @end
        end

        private

        def step_nonblock!(context)
          each_child_workflow(context).each do |wf, ctx|
            wf.run_nonblock(ctx) if wf.step_nonblock_ready?(ctx)
          end
        end

        def each_child_workflow(context)
          branches.filter_map.with_index do |branch, i|
            ctx = context.state.dig("BranchContext", i)
            next if ctx.nil?

            [branch, Context.new(ctx)]
          end
        end

        def parse_error(context)
          each_child_context(context).detect(&:failed?)&.output || {"Error" => "States.Error"}
        end

        def child_context_key
          "BranchContext"
        end

        def validate_state!(workflow)
          validate_state_next!(workflow)
        end
      end
    end
  end
end
