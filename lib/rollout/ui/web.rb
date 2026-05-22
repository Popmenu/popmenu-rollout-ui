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
      if json_request?
        json(
          filtered_features.map do |feature|
            feature_to_hash(feature)
          end
        )
      else
        erb :'features/index'
      end
    end

    get '/features/new' do
      erb :'features/new'
    end

    post '/features/new' do
      halt 400, 'Invalid feature name format' unless params[:name].is_a?(String)

      # Validate required fields
      if params[:name].to_s.strip.empty?
        redirect "#{new_feature_path}?error=#{CGI.escape('Feature name is required')}&team=#{CGI.escape(params[:team].to_s)}"
      end

      team = extract_team_from_params
      validate_team!(team, "#{new_feature_path}?name=#{CGI.escape(params[:name].to_s)}")

      actor = config.get(:actor, scope: self)

      with_rollout_context(rollout, actor: actor) do
        rollout.with_feature(params[:name]) do |feature|
          feature.data.update(team: team, updated_at: Time.now.to_i)
        end
      end

      redirect feature_path(params[:name])
    end

    get '/features/:feature_name' do
      @feature = rollout.get(params[:feature_name])

      if json_request?
        json(feature_to_hash(@feature))
      else
        erb :'features/show'
      end
    end

    post '/features/:feature_name' do
      actor = config.get(:actor, scope: self)
      feature_data = rollout.get(params[:feature_name]).data
      if feature_data['updated_at'] && params[:last_updated_at].to_s != feature_data['updated_at'].to_s
        redirect "#{feature_path(params[:feature_name])}?error=#{CGI.escape('Rollout version outdated. Review changes below and try again.')}"
      end

      team = extract_team_from_params
      validate_team!(team, feature_path(params[:feature_name]))

      with_rollout_context(rollout, actor: actor) do
        rollout.with_feature(params[:feature_name]) do |feature|
          feature.percentage = params[:percentage].to_f.clamp(0.0, 100.0)
          feature.groups = (params[:groups] || []).reject(&:empty?).map(&:to_sym)
          if params[:users]
            feature.users = params[:users].split(',').map(&:strip).uniq.sort
          end
          feature.data.update(
            description: params[:description],
            team: team,
            consumer_cache_break: params[:consumer_cache_break],
            updated_at: Time.now.to_i
          )
        end
      end

      redirect "#{feature_path(params[:feature_name])}?success=#{CGI.escape('Feature updated successfully')}"
    end

    post '/features/:feature_name/activate-percentage' do
      actor = config.get(:actor, scope: self)
      feature_name = params[:feature_name]
      percentage = params[:percentage].to_f.clamp(0.0, 100.0)

      with_rollout_context(rollout, actor: actor) do
        rollout.with_feature(feature_name) do |feature|
          feature.percentage = percentage
          feature.data.update(updated_at: Time.now.to_i)
        end
      end

      redirect "#{index_path}?success=#{CGI.escape("'#{feature_name}' updated to #{percentage}%")}"
    end

    post '/features/:feature_name/active-users-export' do
      halt 404 unless config.defined?(:active_users_exporter)

      feature_name = params[:feature_name]
      config.get(:active_users_exporter, feature_name, current_user)

      redirect "#{feature_path(feature_name)}?success=#{CGI.escape("Export started for '#{feature_name}'. You will receive an email when it is ready.")}"
    end

    post '/features/:feature_name/delete' do
      feature_name = params[:feature_name]
      rollout.delete(feature_name)

      redirect "#{index_path}?success=#{CGI.escape("Feature '#{feature_name}' was successfully deleted")}"
    end
  end
end
