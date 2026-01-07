require "sinatra"
require "rollout"

require "rollout/ui/version"

module Rollout::UI
  module Helpers
    def stylesheet_path(name)
      "#{request.script_name}/css/#{name}.css"
    end

    def index_path
      "#{request.script_name}/"
    end

    def new_feature_path
      "#{request.script_name}/features/new"
    end

    def feature_path(feature_name)
      "#{request.script_name}/features/#{feature_name}"
    end

    def delete_feature_path(feature_name)
      "#{request.script_name}/features/#{feature_name}/delete"
    end

    def activate_percentage_feature_path(feature_name, percentage)
      "#{request.script_name}/features/#{feature_name}/activate-percentage?percentage=#{percentage.to_f}"
    end

    def current_user
      @current_user ||= begin
        id = request.session["warden.user.user.key"].try(:[], 0).try(:[], 0)
        User.find_by(id: id) unless id.nil?
      end
    end

    def with_rollout_context(rollout, context)
      if rollout.respond_to?(:logging)
        rollout.logging.with_context(context) do
          yield
        end
      else
        yield
      end
    end

    def config
      Rollout::UI.config
    end

    def time_ago(time)
      return '' unless time

      diff = (Time.now-time).to_i

      case diff
      when 0 then 'just now'
      when 1 then 'a second ago'
      when 2..59 then diff.to_s+' seconds ago'
      when 60..119 then 'a minute ago' #120 = 2 minutes
      when 120..3540 then (diff/60).to_i.to_s+' minutes ago'
      when 3541..7100 then 'an hour ago' # 3600 = 1 hour
      when 7101..82800 then ((diff+99)/3600).to_i.to_s+' hours ago'
      when 82801..172000 then 'a day ago' # 86400 = 1 day
      when 172001..518400 then ((diff+800)/(60*60*24)).to_i.to_s+' days ago'
      when 518400..1036800 then 'a week ago'
      else ((diff+180000)/(60*60*24*7)).to_i.to_s+' weeks ago'
      end
    end

    def format_change_key(key)
      key.to_s.gsub('data.', '')
    end

    def format_change_value(value)
      case value
      when Array
        "[#{value.join(', ')}]"
      when String, nil
        "'#{value}'"
      else
        value
      end
    end

    def json_request?
      request.env['HTTP_ACCEPT'] == 'application/json'
    end

    # Filters features by user and group if those params are provided
    def filtered_features(rollout, feature_names)
      feature_names.select do |feature_name|
        feature = rollout.get(feature_name)
        user_match = params[:user].nil? || feature.users.member?(params[:user])
        group_match = params[:group].nil? || feature.groups.member?(params[:group].to_sym)
        user_match && group_match
      end
    end

    # Returns a hash of feature data to be rendered as json
    def feature_to_hash(feature)
      {
        data: feature.data,
        groups: feature.groups,
        name: feature.name,
        percentage: feature.percentage,
        team: feature.data['team']
      }
    end

    def confirmation_message(feature, percent)
      if consumer_cache_break?(feature)
        "Please allow 20 minutes between changes for caching to recover. \\nAre you sure you want update #{feature.name} to #{percent}%?"
      else
        "Are you sure you want update #{feature.name} to #{percent}%?"
      end
    end
    def consumer_cache_break?(feature)
      feature.data['consumer_cache_break'] == 'true'
    end

    def get_high_percent_activate(feature)
      return 100 unless consumer_cache_break?(feature)

      [100, feature.percentage + 20].min
    end

    def get_low_percent_activate(feature)
      return 0 unless consumer_cache_break?(feature)

      [0, feature.percentage - 20].max
    end

    # SVG Icon Helpers
    def icon_chevron_left(size: 16)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M10 12L6 8L10 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>)
    end

    def icon_chevron_right(size: 12)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M4.5 2L8.5 6L4.5 10" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>)
    end

    def icon_trash(size: 14)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="3 6 5 6 21 6"></polyline>
        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
        <line x1="10" y1="11" x2="10" y2="17"></line>
        <line x1="14" y1="11" x2="14" y2="17"></line>
      </svg>)
    end

    def icon_grid(size: 16)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M2 3H6V7H2V3Z" stroke="currentColor" stroke-width="1.5"/>
        <path d="M10 3H14V7H10V3Z" stroke="currentColor" stroke-width="1.5"/>
        <path d="M2 9H6V13H2V9Z" stroke="currentColor" stroke-width="1.5"/>
        <path d="M10 9H14V13H10V9Z" stroke="currentColor" stroke-width="1.5"/>
      </svg>)
    end

    def icon_list(size: 16)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M2 4H14M2 8H14M2 12H14" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
      </svg>)
    end
  end
end
