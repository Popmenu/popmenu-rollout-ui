require 'spec_helper'

ENV['APP_ENV'] = 'test'

RSpec.describe 'Web UI' do
  include Rack::Test::Methods

  def app
    Rollout::UI::Web
  end

  it "renders index html" do
    get '/'

    expect(last_response).to be_ok
    expect(last_response.body).to include('Rollout UI')
  end

  it "renders index json" do
    ROLLOUT.activate(:fake_test_feature_for_rollout_ui_webspec)
    header 'Accept', 'application/json'

    get '/'

    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expected_response = {
      "data"=>{},
      "groups"=>[],
      "name"=>"fake_test_feature_for_rollout_ui_webspec",
      "percentage"=>100.0
    }
    expect(response).to include(expected_response)
    ROLLOUT.delete(:fake_test_feature_for_rollout_ui_webspec)
  end

  it "renders index json filtered by user and group" do
    ROLLOUT.deactivate(:fake_test_feature_for_rollout_ui_webspec)
    ROLLOUT.activate_user(:fake_test_feature_for_rollout_ui_webspec, 'fake_user')
    ROLLOUT.activate_group(:fake_test_feature_for_rollout_ui_webspec, :fake_group)

    header 'Accept', 'application/json'
    get '/?user=different_user'
    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expect(response).to be_empty

    expected_feature = {
      "data" => {},
      "groups" => ["fake_group"],
      "name" => "fake_test_feature_for_rollout_ui_webspec",
      "percentage" => 0.0
    }
    header 'Accept', 'application/json'
    get '/?user=fake_user'
    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expect(response).to include(expected_feature)

    header 'Accept', 'application/json'
    get '/?group=fake_group'
    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expect(response).to include(expected_feature)

    ROLLOUT.deactivate_user(:fake_test_feature_for_rollout_ui_webspec, 'fake_user')
    ROLLOUT.deactivate_group(:fake_test_feature_for_rollout_ui_webspec, :fake_group)
    ROLLOUT.delete(:fake_test_feature_for_rollout_ui_webspec)
  end

  it "renders show html" do
    get '/features/test'

    expect(last_response).to be_ok
    expect(last_response.body).to include('Rollout UI') & include('test')
  end

  it "renders show json" do
    ROLLOUT.activate(:fake_test_feature_for_rollout_ui_webspec)
    header 'Accept', 'application/json'
 
    get '/features/fake_test_feature_for_rollout_ui_webspec'
 
    expect(last_response).to be_ok
    expect(last_response.headers).to include('Content-Type' => 'application/json')
    response = JSON.parse(last_response.body)
    expected_response = {
      "data"=>{},
      "groups"=>[],
      "name"=>"fake_test_feature_for_rollout_ui_webspec",
      "percentage"=>100.0
    }
    expect(expected_response).to eq response

    ROLLOUT.delete(:fake_test_feature_for_rollout_ui_webspec)
  end

  describe "create feature" do
    it "requires a team name" do
      post '/features/new', name: 'test_feature', team: ''

      expect(last_response).to be_redirect
      expect(last_response.location).to include('error=Team is required')
    end

    it "requires team name to be at least 2 characters" do
      post '/features/new', name: 'test_feature', team: 'A'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('error=Team name must be at least 2 characters')
    end

    it "creates feature with valid team name" do
      post '/features/new', name: 'test_feature_with_team', team: 'Engineering'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/features/test_feature_with_team')

      feature = ROLLOUT.get(:test_feature_with_team)
      expect(feature.data['team']).to eq 'Engineering'

      ROLLOUT.delete(:test_feature_with_team)
    end

    it "creates feature with new team option" do
      post '/features/new', name: 'test_feature_new_team', team: '__new__', new_team: 'Platform'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/features/test_feature_new_team')

      feature = ROLLOUT.get(:test_feature_new_team)
      expect(feature.data['team']).to eq 'Platform'

      ROLLOUT.delete(:test_feature_new_team)
    end
  end

  describe "edit feature" do
    before do
      ROLLOUT.activate(:edit_test_feature)
      ROLLOUT.with_feature(:edit_test_feature) do |feature|
        feature.data.update(team: 'InitialTeam')
      end
    end

    after do
      ROLLOUT.delete(:edit_test_feature)
    end

    it "requires a team name" do
      post '/features/edit_test_feature', team: '', percentage: '50'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('error=Team is required')
    end

    it "requires team name to be at least 2 characters" do
      post '/features/edit_test_feature', team: 'A', percentage: '50'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('error=Team name must be at least 2 characters')
    end

    it "updates feature with valid team name" do
      post '/features/edit_test_feature', team: 'NewTeam', percentage: '75'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/features/edit_test_feature')

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.data['team']).to eq 'NewTeam'
      expect(feature.percentage).to eq 75.0
    end

    it "updates feature with new team option" do
      post '/features/edit_test_feature', team: '__new__', new_team: 'DataScience', percentage: '100'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/features/edit_test_feature')

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.data['team']).to eq 'DataScience'
    end
  end
end