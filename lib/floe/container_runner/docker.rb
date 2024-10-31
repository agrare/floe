# frozen_string_literal: true

module Floe
  class ContainerRunner
    class Docker < Floe::Runner
      include Floe::ContainerRunner::DockerMixin

      DOCKER_COMMAND = "docker"

      def initialize(options = {})
        require "awesome_spawn"
        require "io/wait"
        require "tempfile"

        super

        @network     = options.fetch("network", "bridge")
        @pull_policy = options["pull-policy"]
      end

      def run_async!(resource, env, secrets, context)
        raise ArgumentError, "Invalid resource" unless resource&.start_with?("docker://")

        image          = resource.sub("docker://", "")
        execution_id   = context.execution["Id"]
        runner_context = {}

        if secrets && !secrets.empty?
          runner_context["secrets_ref"] = create_secret(secrets)
        end

        begin
          runner_context["container_ref"] = run_container(image, env, execution_id, runner_context["secrets_ref"], context.logger)
          runner_context
        rescue AwesomeSpawn::CommandResultError => err
          cleanup(runner_context)
          {"Error" => "States.TaskFailed", "Cause" => err.to_s}
        end
      end

      def cleanup(runner_context)
        container_id, secrets_file = runner_context.values_at("container_ref", "secrets_ref")

        delete_container(container_id) if container_id
        delete_secret(secrets_file)    if secrets_file
      end

      def wait(timeout: nil, events: %i[create update delete], &block)
        until_timestamp = Time.now.utc + timeout if timeout

        r, w = IO.pipe

        pid = AwesomeSpawn.run_detached(
          self.class::DOCKER_COMMAND, :err => :out, :out => w, :params => wait_params(until_timestamp)
        )

        w.close

        loop do
          readable_timeout = until_timestamp - Time.now.utc if until_timestamp

          # Wait for our end of the pipe to be readable and if it didn't timeout
          # get the events from stdout
          next if r.wait_readable(readable_timeout).nil?

          # Get all events while the pipe is readable
          notices = []
          while r.ready?
            notice = r.gets

            # If the process has exited `r.gets` returns `nil` and the pipe is
            # always `ready?`
            break if notice.nil?

            event, runner_context = parse_notice(notice)
            next if event.nil? || !events.include?(event)

            notices << [event, runner_context]
          end

          # If we're given a block yield the events otherwise return them
          if block
            notices.each(&block)
          else
            # Terminate the `docker events` process before returning the events
            sigterm(pid)

            return notices
          end

          # Check that the `docker events` process is still alive
          Process.kill(0, pid)
        rescue Errno::ESRCH
          # Break out of the loop if the `docker events` process has exited
          break
        end
      ensure
        r.close
      end

      def status!(runner_context)
        return if runner_context.key?("Error")

        runner_context["container_state"] = inspect_container(runner_context["container_ref"])&.dig("State")
      end

      def running?(runner_context)
        !!runner_context.dig("container_state", "Running")
      end

      def success?(runner_context)
        runner_context.dig("container_state", "ExitCode") == 0
      end

      def output(runner_context)
        return runner_context.slice("Error", "Cause") if runner_context.key?("Error")

        output = docker!("logs", runner_context["container_ref"], :combined_output => true).output
        runner_context["output"] = output
      end

      private

      attr_reader :network

      def run_container(image, env, execution_id, secrets_file, logger)
        params = run_container_params(image, env, execution_id, secrets_file)

        logger.debug("Running #{AwesomeSpawn.build_command_line(self.class::DOCKER_COMMAND, params)}")

        result = docker!(*params)
        result.output.chomp
      end

      def run_container_params(image, env, execution_id, secrets_file)
        params  = ["run"]
        params << :detach
        params += env.map { |k, v| [:e, "#{k}=#{v}"] }
        params << [:e, "_CREDENTIALS=/run/secrets"] if secrets_file
        params << [:pull, @pull_policy] if @pull_policy
        params << [:net, "host"] if @network == "host"
        params << [:label, "execution_id=#{execution_id}"]
        params << [:v, "#{secrets_file}:/run/secrets:z"] if secrets_file
        params << [:name, container_name(image)]
        params << image
      end

      def wait_params(until_timestamp)
        params = ["events", [:format, "{{json .}}"], [:filter, "type=container"], [:since, Time.now.utc.to_i]]
        params << [:until, until_timestamp.to_i] if until_timestamp
        params
      end

      def parse_notice(notice)
        notice = JSON.parse(notice)

        status  = notice["status"]
        event   = docker_event_status_to_event(status)
        running = event != :delete

        name, exit_code, execution_id = notice.dig("Actor", "Attributes")&.values_at("name", "exitCode", "execution_id")

        runner_context = {"container_ref" => name, "container_state" => {"Running" => running, "ExitCode" => exit_code.to_i}}

        [event, {"execution_id" => execution_id, "runner_context" => runner_context}]
      rescue JSON::ParserError
        []
      end

      def docker_event_status_to_event(status)
        case status
        when "create"
          :create
        when "start"
          :update
        when "die", "destroy"
          :delete
        else
          :unkonwn
        end
      end

      def inspect_container(container_id)
        JSON.parse(docker!("inspect", container_id).output).first
      rescue
        nil
      end

      def delete_container(container_id)
        docker!("rm", container_id)
      rescue
        nil
      end

      def delete_secret(secrets_file)
        return unless File.exist?(secrets_file)

        File.unlink(secrets_file)
      rescue
        nil
      end

      def create_secret(secrets)
        secrets_file = Tempfile.new
        secrets_file.write(secrets.to_json)
        secrets_file.close
        secrets_file.path
      end

      def sigterm(pid)
        Process.kill("TERM", pid)
      rescue Errno::ESRCH
        nil
      end

      def global_docker_options
        []
      end

      def docker!(*args, **kwargs)
        params = global_docker_options + args
        AwesomeSpawn.run!(self.class::DOCKER_COMMAND, :params => params, **kwargs)
      end
    end
  end
end
