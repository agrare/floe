module Floe
  class CLI
    def initialize
      require "optimist"
      require "floe"
      require "floe/container_runner"
      require "logger"

      Floe.logger = Logger.new($stdout)
    end

    def run(args = ARGV)
      workflows_inputs, opts = parse_options!(args)

      credentials =
        if opts[:credentials_given]
          opts[:credentials] == "-" ? $stdin.read : opts[:credentials]
        elsif opts[:credentials_file_given]
          File.read(opts[:credentials_file])
        end

      workflows =
        workflows_inputs.each_slice(2).map do |workflow, input|
          context = Floe::Workflow::Context.new(opts[:context], :input => input, :credentials => credentials)
          Floe::Workflow.load(workflow, context)
        end

      Floe::Workflow.wait(workflows, &:run_nonblock)

      # Display status
      workflows.each do |workflow|
        puts "", "#{workflow.name}#{" (#{workflow.status})" unless workflow.context.success?}", "===" if workflows.size > 1
        puts workflow.output
      end

      workflows.all? { |workflow| workflow.context.success? }
    rescue Floe::Error => err
      abort(err.message)
    end

    private

    def parse_options!(args)
      opts = Optimist.options(args) do
        version("v#{Floe::VERSION}\n")
        usage("[options] workflow input [workflow2 input2]")

        opt :workflow, "Path to your workflow json file (alternative to passing a bare workflow)", :type => :string
        opt :input, <<~EOMSG, :type => :string
          JSON payload of the Input to the workflow
            If --input is passed and --workflow is not passed, will be used for all bare workflows listed.
            If --input is not passed and --workflow is passed, defaults to '{}'.
        EOMSG
        opt :context, "JSON payload of the Context",              :type => :string
        opt :credentials, "JSON payload with Credentials",        :type => :string
        opt :credentials_file, "Path to a file with Credentials", :type => :string

        Floe::ContainerRunner.cli_options(self)

        banner("")
        banner("General options:")
      end

      # Create workflow/input pairs from the various combinations of paramaters
      workflows_inputs =
        if opts[:workflow_given]
          Optimist.die("cannot specify both --workflow and bare workflows") if args.any?

          [opts[:workflow], opts.fetch(:input, "{}")]
        elsif opts[:input_given]
          Optimist.die("workflow(s) must be specified") if args.empty?

          args.flat_map { |w| [w, opts[:input].dup] }
        else
          Optimist.die("workflow/input pairs must be specified") if args.empty? || (args.size > 1 && args.size.odd?)

          args
        end

      Floe::ContainerRunner.resolve_cli_options!(opts)

      return workflows_inputs, opts
    end
  end
end
