# frozen_string_literal: true

module Floe
  class ContainerRunner
    class Kubernetes
      # Mixin that attaches persistent volumes (e.g. pre-created docker volumes or
      # PersistentVolumeClaims) directly to a pod spec without any staging.
      # Each volume entry must have a :volume_name key (the PVC claim name) and
      # a :container_path key. An optional :read_only key sets readOnly on the
      # mount.
      module PersistentVolumeHandler
        private

        # Mutates spec in-place to attach persistent volumes as PVCs. Each entry
        # must have :volume_name (the PVC claim name) and :container_path.
        def add_persistent_volumes_to_spec!(spec, persistent_volumes)
          spec[:spec][:volumes] ||= []
          primary = spec[:spec][:containers][0]
          primary[:volumeMounts] ||= []

          persistent_volumes.each_with_index do |vol, idx|
            vol_name = "floe-persistent-volume-#{idx}"

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
