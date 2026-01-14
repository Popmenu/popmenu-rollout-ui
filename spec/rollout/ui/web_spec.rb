require 'spec_helper'

ENV['APP_ENV'] = 'test'

RSpec.describe 'Web UI' do
  include Rack::Test::Methods

  def app
    Rollout::UI::Web
  end

  around(:example) do |example|
    ROLLOUT.features.each { |feature| ROLLOUT.delete(feature) }
    
    example.run
    
    ROLLOUT.features.each { |feature| ROLLOUT.delete(feature) }
  end
  

  describe 'GET / (index)' do
    it "renders index html" do
      get '/'

      expect(last_response).to be_ok
      expect(last_response.body).to include('Rollout UI')
    end

    it "includes feature count in html" do
      ROLLOUT.activate(:index_test_feature)
      ROLLOUT.activate(:index_test_feature_2)

      get '/'

      expect(last_response).to be_ok
      expect(last_response.body).to include('2 total features')
    end

    it "renders index json" do
      ROLLOUT.activate(:index_json_test_feature)
      header 'Accept', 'application/json'

      get '/'

      expect(last_response).to be_ok
      expect(last_response.headers).to include('Content-Type' => 'application/json')
      response = JSON.parse(last_response.body)
      feature = response.find { |f| f['name'] == 'index_json_test_feature' }
      expect(feature).not_to be_nil
      expect(feature['percentage']).to eq(100.0)
      expect(feature['groups']).to eq([])
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

      header 'Accept', 'application/json'
      get '/?user=fake_user'
      expect(last_response).to be_ok
      expect(last_response.headers).to include('Content-Type' => 'application/json')
      response = JSON.parse(last_response.body)
      feature = response.find { |f| f['name'] == 'fake_test_feature_for_rollout_ui_webspec' }
      expect(feature).not_to be_nil
      expect(feature['groups']).to eq(['fake_group'])
      expect(feature['percentage']).to eq(0.0)

      header 'Accept', 'application/json'
      get '/?group=fake_group'
      expect(last_response).to be_ok
      expect(last_response.headers).to include('Content-Type' => 'application/json')
      response = JSON.parse(last_response.body)
      feature = response.find { |f| f['name'] == 'fake_test_feature_for_rollout_ui_webspec' }
      expect(feature).not_to be_nil

      ROLLOUT.deactivate_user(:fake_test_feature_for_rollout_ui_webspec, 'fake_user')
      ROLLOUT.deactivate_group(:fake_test_feature_for_rollout_ui_webspec, :fake_group)
    end

    it "sorts features alphabetically case-insensitive" do
      ROLLOUT.activate(:zebra_feature)
      ROLLOUT.activate(:Apple_feature)
      ROLLOUT.activate(:banana_feature)

      header 'Accept', 'application/json'
      get '/'

      response = JSON.parse(last_response.body)
      feature_names = response.map { |f| f['name'] }
      
      expect(feature_names.index('Apple_feature')).to be < feature_names.index('banana_feature')
      expect(feature_names.index('banana_feature')).to be < feature_names.index('zebra_feature')
    end
  end

  describe 'GET /features/new' do
    it "renders new feature form" do
      get '/features/new'

      expect(last_response).to be_ok
      expect(last_response.body).to include('New Feature')
      expect(last_response.body).to include('Create Feature')
    end

    it "displays existing teams in dropdown" do
      ROLLOUT.activate(:team_dropdown_test)
      ROLLOUT.with_feature(:team_dropdown_test) do |feature|
        feature.data.update(team: 'ExistingTeam')
      end

      get '/features/new'

      expect(last_response).to be_ok
      expect(last_response.body).to include('ExistingTeam')
    end

    it "preserves name and team params on validation errors" do
      get '/features/new?name=my_feature&team=TestTeam'

      expect(last_response).to be_ok
      expect(last_response.body).to include('my_feature')
    end
  end

  describe 'GET /features/:feature_name (show)' do
    before do
      ROLLOUT.activate(:show_test_feature)
      ROLLOUT.with_feature(:show_test_feature) do |feature|
        feature.data.update(team: 'ShowTeam', description: 'Test description')
      end
    end

    it "renders show html" do
      get '/features/show_test_feature'

      expect(last_response).to be_ok
      expect(last_response.body).to include('show_test_feature')
      expect(last_response.body).to include('Test description')
    end

    it "displays feature configuration options" do
      get '/features/show_test_feature'

      expect(last_response.body).to include('Percentage')
      expect(last_response.body).to include('Groups')
      expect(last_response.body).to include('Users')
      expect(last_response.body).to include('Description')
    end

    it "renders show json" do
      header 'Accept', 'application/json'
   
      get '/features/show_test_feature'
   
      expect(last_response).to be_ok
      expect(last_response.headers).to include('Content-Type' => 'application/json')
      response = JSON.parse(last_response.body)
      
      expect(response['name']).to eq('show_test_feature')
      expect(response['percentage']).to eq(100.0)
      expect(response['data']['team']).to eq('ShowTeam')
      expect(response['data']['description']).to eq('Test description')
    end

    it "renders json with team at top level" do
      header 'Accept', 'application/json'
      
      get '/features/show_test_feature'
      
      response = JSON.parse(last_response.body)
      expect(response['team']).to eq('ShowTeam')
    end

    it "renders show page for nonexistent feature" do
      get '/features/nonexistent_feature'

      expect(last_response).to be_ok
      expect(last_response.body).to include('nonexistent_feature')
    end

    it "shows groups when feature has groups" do
      ROLLOUT.define_group(:test_group) { |user| true }
      ROLLOUT.activate_group(:show_test_feature, :test_group)

      get '/features/show_test_feature'

      expect(last_response.body).to include('test_group')
    end

    it "shows users when feature has users" do
      ROLLOUT.activate_user(:show_test_feature, 'user123')

      get '/features/show_test_feature'

      expect(last_response.body).to include('user123')
    end
  end

  describe 'POST /features/new (create feature)' do
    it "requires a feature name" do
      post '/features/new', name: '', team: 'Engineering'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('error=Feature+name+is+required')
    end

    it "preserves team when name is missing" do
      post '/features/new', name: '', team: 'Engineering'

      expect(last_response.location).to include('team=Engineering')
    end

    it "requires a team name" do
      post '/features/new', name: 'test_feature', team: ''

      expect(last_response).to be_redirect
      expect(last_response.location).to include('error=Team+is+required')
    end

    it "preserves feature name when team is missing" do
      post '/features/new', name: 'my_new_feature', team: ''

      expect(last_response.location).to include('name=my_new_feature')
    end

    it "requires team name to be at least 2 characters" do
      post '/features/new', name: 'test_feature', team: 'A'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('error=Team+name+must+be+at+least+2+characters')
    end

    it "creates feature with valid team name" do
      post '/features/new', name: 'test_feature_with_team', team: 'Engineering'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/features/test_feature_with_team')

      feature = ROLLOUT.get(:test_feature_with_team)
      expect(feature.data['team']).to eq 'Engineering'
    end

    it "creates feature with new team option" do
      post '/features/new', name: 'test_feature_new_team', team: '__new__', new_team: 'Platform'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/features/test_feature_new_team')

      feature = ROLLOUT.get(:test_feature_new_team)
      expect(feature.data['team']).to eq 'Platform'
    end

    it "sets updated_at timestamp on creation" do
      post '/features/new', name: 'timestamp_test_feature', team: 'Engineering'

      feature = ROLLOUT.get(:timestamp_test_feature)
      expect(feature.data['updated_at']).to be_a(Integer)
      expect(feature.data['updated_at']).to be > 0
    end

    it "strips whitespace from team name" do
      post '/features/new', name: 'whitespace_team_feature', team: '  Engineering  '

      feature = ROLLOUT.get(:whitespace_team_feature)
      expect(feature.data['team']).to eq 'Engineering'
    end
  end

  describe 'POST /features/:feature_name (edit feature)' do
    let(:updated_at) { Time.now.to_i }

    before do
      ROLLOUT.activate(:edit_test_feature)
      ROLLOUT.with_feature(:edit_test_feature) do |feature|
        feature.data.update(team: 'InitialTeam', updated_at: updated_at)
      end
    end

    it "requires a team name" do
      post '/features/edit_test_feature', team: '', percentage: '50', last_updated_at: updated_at.to_s

      expect(last_response).to be_redirect
      expect(last_response.location).to include('error=Team+is+required')
    end

    it "requires team name to be at least 2 characters" do
      post '/features/edit_test_feature', team: 'A', percentage: '50', last_updated_at: updated_at.to_s

      expect(last_response).to be_redirect
      expect(last_response.location).to include('error=Team+name+must+be+at+least+2+characters')
    end

    it "updates feature with valid team name" do
      post '/features/edit_test_feature', team: 'NewTeam', percentage: '75', last_updated_at: updated_at.to_s

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/features/edit_test_feature')

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.data['team']).to eq 'NewTeam'
      expect(feature.percentage).to eq 75.0
    end

    it "updates feature with new team option" do
      post '/features/edit_test_feature', team: '__new__', new_team: 'DataScience', percentage: '100', last_updated_at: updated_at.to_s

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/features/edit_test_feature')

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.data['team']).to eq 'DataScience'
    end

    it "updates description" do
      post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', description: 'New description', last_updated_at: updated_at.to_s

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.data['description']).to eq 'New description'
    end

    it "updates groups" do
      ROLLOUT.define_group(:beta) { |user| true }
      ROLLOUT.define_group(:alpha) { |user| true }

      post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', groups: ['beta', 'alpha'], last_updated_at: updated_at.to_s

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.groups).to contain_exactly(:beta, :alpha)
    end

    it "clears groups when empty array passed" do
      ROLLOUT.define_group(:beta) { |user| true }
      ROLLOUT.activate_group(:edit_test_feature, :beta)

      post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', groups: [''], last_updated_at: updated_at.to_s

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.groups).to be_empty
    end

    it "updates users" do
      post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', users: 'user1, user2, user3', last_updated_at: updated_at.to_s

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.users).to contain_exactly('user1', 'user2', 'user3')
    end

    it "deduplicates and sorts users" do
      post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', users: 'user3, user1, user3, user2', last_updated_at: updated_at.to_s

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.users).to eq(['user1', 'user2', 'user3'])
    end

    it "clamps percentage to 0-100 range" do
      current_updated_at = ROLLOUT.get(:edit_test_feature).data['updated_at']
      post '/features/edit_test_feature', team: 'NewTeam', percentage: '150', last_updated_at: current_updated_at.to_s
      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.percentage).to eq 100.0

      current_updated_at = feature.data['updated_at']
      post '/features/edit_test_feature', team: 'NewTeam', percentage: '-50', last_updated_at: current_updated_at.to_s
      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.percentage).to eq 0.0
    end

    it "updates consumer_cache_break setting" do
      post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', consumer_cache_break: 'true', last_updated_at: updated_at.to_s

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.data['consumer_cache_break']).to eq 'true'
    end

    it "updates updated_at timestamp" do
      original_updated_at = ROLLOUT.get(:edit_test_feature).data['updated_at']
      sleep 0.01 # Small delay to ensure timestamp differs

      post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', last_updated_at: original_updated_at.to_s

      feature = ROLLOUT.get(:edit_test_feature)
      expect(feature.data['updated_at']).to be >= original_updated_at
    end

    it "shows success message on successful update" do
      post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', last_updated_at: updated_at.to_s

      expect(last_response.location).to include('success=Feature+updated+successfully')
    end

    describe 'optimistic locking' do
      it "rejects update when last_updated_at does not match" do
        old_timestamp = Time.now.to_i - 1000

        post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', last_updated_at: old_timestamp.to_s

        expect(last_response).to be_redirect
        expect(last_response.location).to include('error=Rollout+version+outdated')
      end

      it "allows update when last_updated_at matches" do
        current_timestamp = ROLLOUT.get(:edit_test_feature).data['updated_at']

        post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', last_updated_at: current_timestamp.to_s

        expect(last_response).to be_redirect
        expect(last_response.location).not_to include('error=')
      end

      it "allows update when feature has no updated_at" do
        ROLLOUT.activate(:edit_test_feature)
        ROLLOUT.with_feature(:edit_test_feature) do |feature|
          feature.data.delete('updated_at')
        end

        post '/features/edit_test_feature', team: 'NewTeam', percentage: '50'

        expect(last_response).to be_redirect
        expect(last_response.location).not_to include('error=Rollout version outdated')
      end
    end
  end

  describe 'POST /features/:feature_name/activate-percentage' do
    before do
      ROLLOUT.activate(:percentage_test_feature)
      ROLLOUT.with_feature(:percentage_test_feature) do |feature|
        feature.data.update(team: 'TestTeam')
      end
    end

    it "updates feature percentage" do
      post '/features/percentage_test_feature/activate-percentage', percentage: '75'

      feature = ROLLOUT.get(:percentage_test_feature)
      expect(feature.percentage).to eq 75.0
    end

    it "redirects to index with success message" do
      post '/features/percentage_test_feature/activate-percentage', percentage: '50'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('success=')
      expect(last_response.location).to include('percentage_test_feature')
      expect(last_response.location).to include('50')
    end

    it "clamps percentage to 0-100 range" do
      post '/features/percentage_test_feature/activate-percentage', percentage: '200'
      feature = ROLLOUT.get(:percentage_test_feature)
      expect(feature.percentage).to eq 100.0

      post '/features/percentage_test_feature/activate-percentage', percentage: '-10'
      feature = ROLLOUT.get(:percentage_test_feature)
      expect(feature.percentage).to eq 0.0
    end

    it "accepts decimal percentages" do
      post '/features/percentage_test_feature/activate-percentage', percentage: '33.3'

      feature = ROLLOUT.get(:percentage_test_feature)
      expect(feature.percentage).to eq 33.3
    end

    it "updates updated_at timestamp" do
      original = ROLLOUT.get(:percentage_test_feature).data['updated_at']

      post '/features/percentage_test_feature/activate-percentage', percentage: '50'

      feature = ROLLOUT.get(:percentage_test_feature)
      expect(feature.data['updated_at']).to be >= (original || 0)
    end
  end

  describe 'POST /features/:feature_name/delete' do
    before do
      ROLLOUT.activate(:delete_test_feature)
      ROLLOUT.with_feature(:delete_test_feature) do |feature|
        feature.data.update(team: 'TestTeam')
      end
    end

    it "deletes the feature" do
      expect(ROLLOUT.features).to include(:delete_test_feature)

      post '/features/delete_test_feature/delete'

      expect(ROLLOUT.features).not_to include(:delete_test_feature)
    end

    it "redirects to index with success message" do
      post '/features/delete_test_feature/delete'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('/')
      expect(last_response.location).to include('success=')
      expect(last_response.location).to include('delete_test_feature')
      expect(last_response.location).to include('deleted')
    end

    it "handles deleting nonexistent feature gracefully" do
      post '/features/nonexistent_feature_xyz/delete'

      expect(last_response).to be_redirect
      expect(last_response.location).to include('success=')
    end
  end

  describe 'static assets' do
    it "serves CSS files" do
      get '/css/tailwind.min.css'

      expect(last_response).to be_ok
      expect(last_response.content_type).to include('text/css')
    end
  end

  describe 'content type handling' do
    it "returns HTML for default requests" do
      get '/'

      expect(last_response.content_type).to include('text/html')
    end

    it "returns JSON when Accept header is application/json" do
      header 'Accept', 'application/json'
      get '/'

      expect(last_response.content_type).to include('application/json')
    end
  end

  describe 'edge cases' do
    it "handles feature names with special characters" do
      post '/features/new', name: 'feature_with_numbers_123', team: 'Engineering'

      expect(last_response).to be_redirect
      expect(ROLLOUT.features).to include(:feature_with_numbers_123)
    end

    it "handles empty users string" do
      ROLLOUT.activate(:empty_users_test)
      ROLLOUT.with_feature(:empty_users_test) do |feature|
        feature.data.update(team: 'TestTeam')
      end

      post '/features/empty_users_test', team: 'TestTeam', percentage: '50', users: ''

      feature = ROLLOUT.get(:empty_users_test)
      expect(feature.users).to be_empty
    end

    it "handles percentage as string" do
      ROLLOUT.activate(:string_percentage_test)
      ROLLOUT.with_feature(:string_percentage_test) do |feature|
        feature.data.update(team: 'TestTeam')
      end

      post '/features/string_percentage_test', team: 'TestTeam', percentage: '45.5'

      feature = ROLLOUT.get(:string_percentage_test)
      expect(feature.percentage).to eq 45.5
    end
  end
end