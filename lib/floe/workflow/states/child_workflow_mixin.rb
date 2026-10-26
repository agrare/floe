# frozen_string_literal: true

module Floe
  class Workflow
    module States
      module ChildWorkflowMixin
        def run_nonblock!(context)
          start(context) unless context.state_started?
          step_nonblock!(context)
          return Errno::EAGAIN unless ready?(context)

          finish(context) if ended?(context)
        rescue Floe::ExecutionError => e
          mark_error(context, e)
        end

        # An error evaluating this state (e.g. a JSONata expression) rather than an error from a child
        def mark_error(context, exception)
          error = exception.to_output

          retry_state!(context, error) || catch_error!(context, error) || fail_workflow!(context, error)
          mark_finished(context)
        end

        def finish(context)
          if success?(context)
            result = each_child_context(context).map(&:output)
            context.output = process_output(context, result)
          else
            error = parse_error(context)
            retry_state!(context, error) || catch_error!(context, error) || fail_workflow!(context, error)
          end

          super
        end

        def ready?(context)
          !context.state_started? || each_child_workflow(context).any? { |wf, ctx| wf.step_nonblock_ready?(ctx) }
        end

        def wait_until(context)
          each_child_workflow(context).filter_map { |wf, ctx| wf.wait_until(ctx) }.min
        end

        def waiting?(context)
          each_child_workflow(context).any? { |wf, ctx| wf.waiting?(ctx) }
        end

        def running?(context)
          !ended?(context)
        end

        def ended?(context)
          each_child_context(context).all?(&:ended?)
        end

        def success?(context)
          each_child_context(context).none?(&:failed?)
        end

        def each_child_context(context)
          context.state[child_context_key].map { |ctx| Context.new(ctx, :credentials => context.credentials) }
        end
      end
    end
  end
end
