# frozen_string_literal: true

module Floe
  class ContainerRunner
    class Podman < Docker
      DOCKER_COMMAND = "podman"

      def initialize(options = {})
        require "awesome_spawn"
        require "securerandom"

        super

        @identity        = options["identity"]
        @log_level       = options["log-level"]
        @network         = options["network"]
        @noout           = options["noout"].to_s == "true" if options.key?("noout")
        @pull_policy     = options["pull-policy"]
        @root            = options["root"]
        @runroot         = options["runroot"]
        @runtime         = options["runtime"]
        @runtime_flag    = options["runtime-flag"]
        @storage_driver  = options["storage-driver"]
        @storage_opt     = options["storage-opt"]
        @syslog          = options["syslog"].to_s == "true" if options.key?("syslog")
        @tmpdir          = options["tmpdir"]
        @transient_store = !!options["transient-store"] if options.key?("transient-store")
        @volumepath      = options["volumepath"]
      end

      private

      def run_container_params(image, env, execution_id, secret, volumes = [])
        params  = ["run"]
        params << :detach
        params += env.map { |k, v| [:e, "#{k}=#{v}"] }
        params << [:e, "_CREDENTIALS=/run/secrets/#{secret}"] if secret
        params << [:pull, @pull_policy] if @pull_policy
        params << [:net, "host"]        if @network == "host"
        params << [:label, "execution_id=#{execution_id}"]
        params << [:secret, secret] if secret
        params += volumes.map { |v| [:v, volume_to_flag(v)] }
        params << [:name, container_name(image)]
        params << image
      end

      def create_secret(secrets)
        secret_guid = SecureRandom.uuid
        podman!("secret", "create", secret_guid, "-", :in_data => secrets.to_json)
        secret_guid
      end

      def delete_secret(secret_guid)
        podman!("secret", "rm", secret_guid)
      rescue
        nil
      end

      def parse_notice(notice)
        notice = JSON.parse(notice)
        id, status, exit_code, attributes = notice.values_at("ID", "Status", "ContainerExitCode", "Attributes")

        execution_id = attributes&.dig("execution_id")
        event        = podman_event_status_to_event(status)
        running      = event != :delete

        runner_context = {"container_ref" => id, "container_state" => {"Running" => running, "ExitCode" => exit_code.to_i}}

        [event, {"execution_id" => execution_id, "runner_context" => runner_context}]
      rescue JSON::ParserError
        []
      end

      def podman_event_status_to_event(status)
        case status
        when "create"
          :create
        when "init", "start"
          :update
        when "died", "cleanup", "remove"
          :delete
        else
          :unknown
        end
      end

      alias podman! docker!

      def global_docker_options
        options = []
        options << [:identity, @identity]                 if @identity
        options << [:"log-level", @log_level]             if @log_level
        options << :noout                                 if @noout
        options << [:root, @root]                         if @root
        options << [:runroot, @runroot]                   if @runroot
        options << [:runtime, @runtime]                   if @runtime
        options << [:"runtime-flag", @runtime_flag]       if @runtime_flag
        options << [:"storage-driver", @storage_driver]   if @storage_driver
        options << [:"storage-opt", @storage_opt]         if @storage_opt
        options << :syslog                                if @syslog
        options << [:tmpdir, @tmpdir]                     if @tmpdir
        options << [:"transient-store", @transient_store] if @transient_store
        options << [:volumepath, @volumepath]             if @volumepath
        options
      end
    end
  end
end
