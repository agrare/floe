# frozen_string_literal: true

module Floe
  class Workflow
    module States
      class Parallel < Floe::Workflow::State
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

        def finish(context)
          if success?(context)
            result = each_branch_context(context).map(&:output)
            context.output = process_output(context, result)
          else
            error = parse_error(context)
            retry_state!(context, error) || catch_error!(context, error) || fail_workflow!(context, error)
          end

          super
        end

        def run_nonblock!(context)
          start(context) unless context.state_started?

          step_nonblock!(context) while running?(context)
          return Errno::EAGAIN unless ready?(context)

          finish(context) if ended?(context)
        end

        def end?
          @end
        end

        def ready?(context)
          !context.state_started? || each_branch(context).any? { |branch, ctx| branch.step_nonblock_ready?(ctx) }
        end

        def wait_until(context)
          each_branch(context).filter_map { |branch, ctx| branch.wait_until(ctx) }.min
        end

        def waiting?(context)
          each_branch(context).any? { |branch, ctx| branch.waiting?(ctx) }
        end

        def running?(context)
          !ended?(context)
        end

        def ended?(context)
          each_branch_context(context).all?(&:ended?)
        end

        def success?(context)
          each_branch_context(context).none?(&:failed?)
        end

        private

        def step_nonblock!(context)
          each_branch(context).each do |branch, ctx|
            branch.run_nonblock(ctx) if branch.step_nonblock_ready?(ctx)
          end
        end

        def each_branch(context)
          branches.filter_map.with_index do |branch, i|
            ctx = context.state.dig("BranchContext", i)
            next if ctx.nil?

            [branch, Context.new(ctx)]
          end
        end

        def each_branch_context(context)
          context.state["BranchContext"].map { |ctx| Context.new(ctx) }
        end

        def parse_error(context)
          each_branch_context(context).detect(&:failed?)&.output || {"Error" => "States.Error"}
        end

        def validate_state!(workflow)
          validate_state_next!(workflow)
        end
      end
    end
  end
end
