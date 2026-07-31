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

  describe 'permanent flag rendering' do
    # The accordion header for a single team, from its data-team attribute to the
    # end of the header button.
    def team_header(team_name)
      last_response.body[/data-team="#{team_name}".*?<\/button>/m]
    end

    # index.erb renders list view and team view into the same page, so split on
    # the team view container to assert against each view separately.
    def views
      last_response.body.split('id="team-view"')
    end

    def badge_count(html)
      html.scan('>Permanent</span>').length
    end

    def create_feature(name, team:, percentage:, permanent: false)
      ROLLOUT.activate_percentage(name, percentage)
      ROLLOUT.with_feature(name) do |feature|
        feature.data.update(team: team, permanent: permanent ? 'true' : 'false')
      end
    end

    describe 'name badge' do
      before do
        create_feature(:badge_permanent_feature, team: 'BadgeTeam', percentage: 100, permanent: true)
        create_feature(:badge_normal_feature, team: 'BadgeTeam', percentage: 100)
      end

      it "shows the badge in team view for permanent flags only" do
        get '/'

        _list_html, team_html = views
        expect(badge_count(team_html)).to eq 1
      end

      it "shows the badge in list view for permanent flags only" do
        get '/'

        list_html, _team_html = views
        expect(badge_count(list_html)).to eq 1
      end

      it "shows no badge when no flags are permanent" do
        ROLLOUT.delete(:badge_permanent_feature)

        get '/'

        expect(badge_count(last_response.body)).to eq 0
      end
    end

    describe 'team header metrics' do
      it "excludes permanent flags from the feature count and fully activated ratio" do
        create_feature(:mixed_permanent_feature, team: 'MixedTeam', percentage: 100, permanent: true)
        create_feature(:mixed_full_feature, team: 'MixedTeam', percentage: 100)
        create_feature(:mixed_partial_feature, team: 'MixedTeam', percentage: 50)

        get '/'

        header = team_header('MixedTeam')
        expect(header).to include('1 permanent')
        expect(header).to include('2 non-permanent · 1 fully activated')
        expect(header.index('2 non-permanent')).to be < header.index('1 permanent')
      end

      it "omits the fully activated metric for a team of only permanent flags" do
        create_feature(:only_permanent_feature, team: 'PermanentTeam', percentage: 100, permanent: true)
        create_feature(:only_permanent_feature_2, team: 'PermanentTeam', percentage: 50, permanent: true)

        get '/'

        header = team_header('PermanentTeam')
        expect(header).to include('2 permanent')
        expect(header).to include('0 non-permanent')
        expect(header).not_to include('fully activated')
      end

      it "shows a zero permanent count for teams without permanent flags" do
        create_feature(:normal_only_feature, team: 'NormalTeam', percentage: 100)

        get '/'

        header = team_header('NormalTeam')
        expect(header).to include('0 permanent')
        expect(header).to include('1 non-permanent · 1 fully activated')
      end

      it "keeps permanent flags in the tables and the page total" do
        create_feature(:table_permanent_feature, team: 'TableTeam', percentage: 100, permanent: true)
        create_feature(:table_normal_feature, team: 'TableTeam', percentage: 100)

        get '/'

        expect(last_response.body).to include('2 total features')
        list_html, team_html = views
        expect(list_html).to include('table_permanent_feature')
        expect(team_html).to include('table_permanent_feature')
      end
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

    describe 'permanent toggle' do
      def permanent_input
        last_response.body[/<input[^>]*id="permanent"[^>]*>/m]
      end

      it "renders the toggle unchecked for a non-permanent feature" do
        get '/features/show_test_feature'

        expect(last_response.body).to include('Permanent')
        expect(permanent_input).not_to include('checked')
      end

      it "renders the toggle checked for a permanent feature" do
        ROLLOUT.with_feature(:show_test_feature) do |feature|
          feature.data.update(permanent: 'true')
        end

        get '/features/show_test_feature'

        expect(permanent_input).to include('checked')
      end
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

    describe 'permanent flag' do
      it "saves permanent when a description is provided" do
        post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', permanent: 'true',
             description: 'Kill switch we keep forever', last_updated_at: updated_at.to_s

        expect(last_response.location).to include('success=Feature+updated+successfully')
        feature = ROLLOUT.get(:edit_test_feature)
        expect(feature.data['permanent']).to eq 'true'
      end

      it "clears permanent when the toggle is off" do
        ROLLOUT.with_feature(:edit_test_feature) do |feature|
          feature.data.update(permanent: 'true', description: 'Kill switch')
        end
        current_updated_at = ROLLOUT.get(:edit_test_feature).data['updated_at']

        post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', permanent: 'false',
             description: 'Kill switch', last_updated_at: current_updated_at.to_s

        feature = ROLLOUT.get(:edit_test_feature)
        expect(feature.data['permanent']).to eq 'false'
      end

      it "rejects permanent with a blank description and leaves the flag unchanged" do
        post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', permanent: 'true',
             description: '', last_updated_at: updated_at.to_s

        expect(last_response).to be_redirect
        expect(last_response.location).to include('error=A+description+is+required+for+permanent+flags')

        feature = ROLLOUT.get(:edit_test_feature)
        expect(feature.data['permanent']).to be_nil
        expect(feature.data['team']).to eq 'InitialTeam'
        expect(feature.data['description']).to be_nil
        expect(feature.data['updated_at']).to eq updated_at
        expect(feature.percentage).to eq 100.0
      end

      it "rejects permanent with a whitespace-only description and leaves the flag unchanged" do
        post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', permanent: 'true',
             description: "   \t ", last_updated_at: updated_at.to_s

        expect(last_response).to be_redirect
        expect(last_response.location).to include('error=A+description+is+required+for+permanent+flags')

        feature = ROLLOUT.get(:edit_test_feature)
        expect(feature.data['permanent']).to be_nil
        expect(feature.data['team']).to eq 'InitialTeam'
        expect(feature.data['updated_at']).to eq updated_at
        expect(feature.percentage).to eq 100.0
      end

      it "allows a blank description when permanent is off" do
        post '/features/edit_test_feature', team: 'NewTeam', percentage: '50', permanent: 'false',
             description: '', last_updated_at: updated_at.to_s

        expect(last_response.location).to include('success=Feature+updated+successfully')
        feature = ROLLOUT.get(:edit_test_feature)
        expect(feature.data['permanent']).to eq 'false'
      end

      it "still requires a team when permanent is enabled" do
        post '/features/edit_test_feature', team: '', percentage: '50', permanent: 'true',
             description: 'Kill switch', last_updated_at: updated_at.to_s

        expect(last_response).to be_redirect
        expect(last_response.location).to include('error=Team+is+required')

        feature = ROLLOUT.get(:edit_test_feature)
        expect(feature.data['permanent']).to be_nil
      end
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

  describe 'environment label in layout' do
    after do
      Rollout::UI.config.reset!(:environment_label)
    end

    it "renders default title and header when no environment_label is configured" do
      get '/'

      expect(last_response).to be_ok
      expect(last_response.body).to include('<title>Rollout UI</title>')
      expect(last_response.body).to match(/<a[^>]*>Rollout UI<\/a>/)
      expect(last_response.body).not_to include('Rollout - ')
    end

    it "renders environment label in title and header when configured" do
      Rollout::UI.configure do
        environment_label { 'Staging' }
      end

      get '/'

      expect(last_response).to be_ok
      expect(last_response.body).to include('<title>Rollout - Staging</title>')
      expect(last_response.body).to match(/<a[^>]*>Rollout - Staging<\/a>/)
      expect(last_response.body).not_to include('text-red-600')
    end

    it "renders production environments in red with a danger emoji in the tab" do
      Rollout::UI.configure do
        environment_label { 'Production' }
      end

      get '/'

      expect(last_response).to be_ok
      expect(last_response.body).to include('<title>🔴 Rollout - Production</title>')
      expect(last_response.body).to include('text-red-600')
    end

    it "treats any label containing 'prod' as production (case-insensitive)" do
      Rollout::UI.configure do
        environment_label { 'preprod' }
      end

      get '/'

      expect(last_response.body).to include('<title>🔴 Rollout - preprod</title>')
      expect(last_response.body).to include('text-red-600')
    end
  end

  describe 'active users export' do
    before do
      ROLLOUT.activate(:export_test_feature)
      ROLLOUT.with_feature(:export_test_feature) do |feature|
        feature.data.update(team: 'TestTeam')
      end
    end

    after do
      Rollout::UI.config.reset!(:active_users_exporter)
      Rollout::UI.config.reset!(:active_users_export_label)
    end

    context 'when no exporter is configured' do
      it "does not render the export button on the show page" do
        get '/features/export_test_feature'

        expect(last_response).to be_ok
        expect(last_response.body).not_to include('active-users-export')
      end

      it "returns 404 for the export route" do
        post '/features/export_test_feature/active-users-export'

        expect(last_response.status).to eq 404
      end
    end

    context 'when an exporter is configured' do
      it "renders the export button on the show page with the default label" do
        Rollout::UI.configure do
          active_users_exporter { |_feature_name, _current_user| }
        end

        get '/features/export_test_feature'

        expect(last_response).to be_ok
        expect(last_response.body).to include('/features/export_test_feature/active-users-export')
        expect(last_response.body).to include('Export Active Users')
      end

      it "renders the configured export label" do
        Rollout::UI.configure do
          active_users_exporter { |_feature_name, _current_user| }
          active_users_export_label { 'Export Active Restaurants' }
        end

        get '/features/export_test_feature'

        expect(last_response.body).to include('Export Active Restaurants')
      end

      it "calls the exporter with the feature name and current user and redirects with success" do
        captured = {}
        Rollout::UI.configure do
          active_users_exporter do |feature_name, current_user|
            captured[:feature_name] = feature_name
            captured[:current_user] = current_user
          end
        end

        post '/features/export_test_feature/active-users-export'

        expect(captured[:feature_name]).to eq('export_test_feature')
        expect(captured).to have_key(:current_user)
        expect(last_response).to be_redirect
        expect(last_response.location).to include('/features/export_test_feature')
        expect(last_response.location).to include('success=')
        expect(last_response.location).to include('export_test_feature')
      end

      it "URL-encodes feature names with special characters in the button action" do
        Rollout::UI.configure do
          active_users_exporter { |_feature_name, _current_user| }
        end
        ROLLOUT.activate(:'feature with spaces')
        ROLLOUT.with_feature(:'feature with spaces') do |feature|
          feature.data.update(team: 'TestTeam')
        end

        get '/features/feature%20with%20spaces'

        expect(last_response.body).to include('/features/feature%20with%20spaces/active-users-export')
      end
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

  describe 'parameter validation security' do
    describe 'POST /features/new' do
      it "blocks hash parameters with 400 error" do
        post '/features/new', 'name[nest][nested]' => 'value', 'name[another]' => 'data', team: 'TestTeam'

        expect(last_response.status).to eq 400
        expect(last_response.body).to include('Invalid feature name format')
      end

      it "blocks array parameters with 400 error" do
        post '/features/new', 'name[]' => ['item1', 'item2'], team: 'TestTeam'

        expect(last_response.status).to eq 400
        expect(last_response.body).to include('Invalid feature name format')
      end

      it "still allows valid string parameters" do
        post '/features/new', name: 'valid_feature_name', team: 'TestTeam'

        expect(last_response).to be_redirect
        expect(last_response.location).to include('/features/valid_feature_name')
      end
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
