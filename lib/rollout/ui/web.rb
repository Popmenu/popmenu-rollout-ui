require "sinatra"
require "sinatra/json"
require "rollout"
require "cgi"

require "rollout/ui/version"
require "rollout/ui/config"
require "rollout/ui/helpers"

module Rollout::UI
  class Web < Sinatra::Base
    set :static, true
    set :public_folder, File.dirname(__FILE__) + '/public'

    helpers Helpers

    get '/' do
      @rollout = config.get(:instance)
      @features = @rollout.features.sort_by(&:downcase)
      if json_request?
        json(
          filtered_features(@rollout, @features).map do |feature|
            feature_to_hash(@rollout.get(feature))
          end
        )
      else
        erb :'features/index'
      end
    end

    get '/features/new' do
      @rollout = config.get(:instance)
      @teams = @rollout.features.map { |f| @rollout.get(f).data['team'] }.compact.reject(&:empty?).uniq.sort
      erb :'features/new'
    end

    post '/features/new' do
      # Validate required fields
      if params[:name].to_s.strip.empty?
        redirect "#{new_feature_path}?error=Feature name is required&team=#{CGI.escape(params[:team].to_s)}"
      end

      # Handle team selection - use new_team if "Add new team" was selected
      team = params[:team] == '__new__' ? params[:new_team] : params[:team]
      team = team.to_s.strip

      if team.empty?
        redirect "#{new_feature_path}?error=Team is required&name=#{CGI.escape(params[:name].to_s)}"
      end

      if team.length < 2
        redirect "#{new_feature_path}?error=Team name must be at least 2 characters&name=#{CGI.escape(params[:name].to_s)}"
      end

      rollout = config.get(:instance)
      actor = config.get(:actor, scope: self)

      with_rollout_context(rollout, actor: actor) do
        rollout.with_feature(params[:name]) do |feature|
          feature.data.update(team: team.strip)
          feature.data.update(updated_at: Time.now.to_i)
        end
      end

      redirect feature_path(params[:name])
    end

    get '/features/:feature_name' do
      @rollout = config.get(:instance)
      @feature = @rollout.get(params[:feature_name])
      @teams = @rollout.features.map { |f| @rollout.get(f).data['team'] }.compact.reject(&:empty?).uniq.sort

      if json_request?
        json(feature_to_hash(@feature))
      else
        erb :'features/show'
      end
    end

    post '/features/:feature_name' do
      rollout = config.get(:instance)
      actor = config.get(:actor, scope: self)
      feature_data = rollout.get(params[:feature_name]).data
      if feature_data['updated_at'] && params[:last_updated_at].to_s != feature_data['updated_at'].to_s
        redirect "#{feature_path(params[:feature_name])}?error=Rollout version outdated. Review changes below and try again."
      end
      with_rollout_context(rollout, actor: actor) do
        rollout.with_feature(params[:feature_name]) do |feature|
          feature.percentage = params[:percentage].to_f.clamp(0.0, 100.0)
          feature.groups = (params[:groups] || []).reject(&:empty?).map(&:to_sym)
          if params[:users]
            feature.users = params[:users].split(',').map(&:strip).uniq.sort
          end
          feature.data.update(description: params[:description])
          # Handle team selection - use new_team if "Add new team" was selected
          team = params[:team] == '__new__' ? params[:new_team] : params[:team]
          feature.data.update(team: team.to_s.strip)
          feature.data.update(consumer_cache_break: params[:consumer_cache_break])
          feature.data.update(updated_at: Time.now.to_i)
        end
      end

      redirect feature_path(params[:feature_name])
    end

    post '/features/:feature_name/activate-percentage' do
      rollout = config.get(:instance)
      actor = config.get(:actor, scope: self)

      with_rollout_context(rollout, actor: actor) do
        rollout.with_feature(params[:feature_name]) do |feature|
          feature.percentage = params[:percentage].to_f.clamp(0.0, 100.0)
          feature.data.update(updated_at: Time.now.to_i)
        end
      end

      redirect index_path
    end

    post '/features/:feature_name/delete' do
      @rollout = config.get(:instance)
      @rollout.delete(params[:feature_name])

      redirect index_path
    end
  end
end
