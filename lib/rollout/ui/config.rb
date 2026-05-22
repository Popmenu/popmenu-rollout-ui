require "sinatra"
require "rollout"

require "rollout/ui/version"

module Rollout::UI
  class Config
    KEYS = %i[
      instance
      actor
      actor_url
      active_users_exporter
      active_users_export_label
      environment_label
      current_user_resolver
    ].freeze

    KEYS.each do |key|
      define_method(key) do |&block|
        @blocks ||= {}

        if block
          @blocks[key] = block
        else
          raise ArgumentError, "#{key}: block is required"
        end
      end
    end

    def get(key, *args, scope: nil)
      raise ArgumentError, "Invalid config key: #{key}" unless KEYS.include?(key)

      @blocks ||= {}
      block = @blocks[key]

      return if block.nil?

      if scope
        scope.instance_eval(&block)
      else
        block.call(*args)
      end
    end

    def defined?(key)
      !@blocks.nil? && @blocks.key?(key)
    end

    def reset!(key)
      return if @blocks.nil?

      @blocks.delete(key)
    end
  end
end
