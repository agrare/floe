# frozen_string_literal: true

module Floe
  class ContainerRunner
    class Kubernetes
      # Mixin that attaches pre-made volumes (e.g. pre-created docker volumes or
      # PersistentVolumeClaims) directly to a pod spec without any staging.
      # Each volume entry must have a :volume_name key (the PVC claim name) and
      # a :container_path key. An optional :read_only key sets readOnly on the
      # mount.
      module PreMadeVolumeHandler
        private

        # Mutates spec in-place to attach pre-made volumes as PVCs without any
        # S3 staging. Each entry must have :volume_name (the PVC claim name)
        # and :container_path.
        def add_pre_made_volumes_to_spec!(spec, pre_made_volumes)
          spec[:spec][:volumes] ||= []
          primary = spec[:spec][:containers][0]
          primary[:volumeMounts] ||= []

          pre_made_volumes.each_with_index do |vol, idx|
            vol_name = "floe-pre-made-volume-#{idx}"

            spec[:spec][:volumes] << {
              :name                  => vol_name,
              :persistentVolumeClaim => {:claimName => vol[:volume_name]}
            }

            primary[:volumeMounts] << {
              :name      => vol_name,
              :mountPath => vol[:container_path],
              :readOnly  => vol.fetch(:read_only, false)
            }.tap { |m| m.delete(:readOnly) unless m[:readOnly] }
          end
        end
      end
    end
  end
end
