require "sinatra"
require "rollout"
require "erb"
require "cgi"

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
      "#{request.script_name}/features/#{ERB::Util.url_encode(feature_name.to_s)}"
    end

    def delete_feature_path(feature_name)
      "#{request.script_name}/features/#{ERB::Util.url_encode(feature_name.to_s)}/delete"
    end

    def activate_percentage_feature_path(feature_name, percentage)
      "#{request.script_name}/features/#{ERB::Util.url_encode(feature_name.to_s)}/activate-percentage?percentage=#{percentage.to_f}"
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

    def rollout
      @rollout ||= config.get(:instance)
    end

    def has_logging?
      rollout.respond_to?(:logging)
    end
    
    # @return [Array<Rollout::Feature>]
    def features
      @features ||= rollout.features.sort_by(&:downcase).map { |feature| rollout.get(feature) }
    end

    # @return [Array<String>] sorted list of unique team names
    def team_names
      @team_names ||= features.filter_map do |feature|
        team = feature.data['team'].to_s
        team unless team.empty?
      end.uniq.sort
    end

    # @return [Hash<String, Array<Rollout::Feature>>]
    def features_by_team
      @features_by_team ||= features.group_by do |feature|
        feature.data['team'].to_s.strip.empty? ? 'Uncategorized' : feature.data['team']
      end.sort_by { |team, _| team == 'Uncategorized' ? 'zzz' : team.downcase }
    end

    # Returns badge color classes based on feature count
    # green < 15, yellow 15-29, orange 30-44, red 45+
    def feature_count_badge_classes(count)
      case count
      when 0..14 then 'bg-emerald-100 text-emerald-600'
      when 15..29 then 'bg-yellow-100 text-yellow-700'
      when 30..44 then 'bg-orange-100 text-orange-600'
      else 'bg-red-100 text-red-600'
      end
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

    # Extracts team from params, handling the "Add new team" option
    def extract_team_from_params
      team = params[:team] == '__new__' ? params[:new_team] : params[:team]
      team.to_s.strip
    end

    # Validates team and redirects with error if invalid
    # Returns the validated team if valid, otherwise redirects
    def validate_team!(team, error_redirect_path)
      if team.empty?
        redirect "#{error_redirect_path}?error=#{CGI.escape('Team is required')}"
      end

      if team.length < 2
        redirect "#{error_redirect_path}?error=#{CGI.escape('Team name must be at least 2 characters')}"
      end

      team
    end

    # Filters features by user and group if those params are provided
    def filtered_features
      features.select do |feature|
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
    def chevron_left_icon(size: 16)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M10 12L6 8L10 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>)
    end

    def chevron_right_icon(size: 12)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M4.5 2L8.5 6L4.5 10" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>)
    end

    def trash_icon(size: 14)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="3 6 5 6 21 6"></polyline>
        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
        <line x1="10" y1="11" x2="10" y2="17"></line>
        <line x1="14" y1="11" x2="14" y2="17"></line>
      </svg>)
    end

    def team_icon(size: 16)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="8" cy="5" r="2" stroke="currentColor" stroke-width="1.5"/>
        <path d="M4 14c0-2.2 1.8-4 4-4s4 1.8 4 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
        <circle cx="3" cy="6" r="1.5" stroke="currentColor" stroke-width="1"/>
        <path d="M1 12.5c0-1.4 0.9-2.5 2-2.5" stroke="currentColor" stroke-width="1" stroke-linecap="round"/>
        <circle cx="13" cy="6" r="1.5" stroke="currentColor" stroke-width="1"/>
        <path d="M15 12.5c0-1.4-0.9-2.5-2-2.5" stroke="currentColor" stroke-width="1" stroke-linecap="round"/>
      </svg>)
    end

    def list_icon(size: 16)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M2 4H14M2 8H14M2 12H14" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
      </svg>)
    end

    def info_icon(size: 16)
      %(<svg width="#{size}" height="#{size}" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="8" cy="8" r="8" fill="#3b82f6"/>
        <circle cx="8" cy="4.5" r="1.25" fill="white"/>
        <rect x="6.75" y="6.75" width="2.5" height="6" rx="1.25" fill="white"/>
      </svg>)
    end

    # Returns consistent Tailwind color classes for a team badge based on team name
    TEAM_COLORS = [
      'bg-blue-100 text-blue-700',
      'bg-emerald-100 text-emerald-700',
      'bg-purple-100 text-purple-700',
      'bg-amber-100 text-amber-700',
      'bg-rose-100 text-rose-700',
      'bg-cyan-100 text-cyan-700',
      'bg-indigo-100 text-indigo-700',
      'bg-orange-100 text-orange-700',
      'bg-teal-100 text-teal-700',
      'bg-pink-100 text-pink-700',
      'bg-lime-100 text-lime-700',
      'bg-sky-100 text-sky-700',
    ].freeze

    def team_badge_colors(team_name)
      return 'bg-slate-100 text-slate-600' if team_name.to_s.strip.empty?
      
      # Use hash of team name to get consistent color index
      index = team_name.to_s.downcase.sum % TEAM_COLORS.length
      TEAM_COLORS[index]
    end
  end
end
