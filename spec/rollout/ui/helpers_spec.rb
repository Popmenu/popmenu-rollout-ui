require 'spec_helper'

RSpec.describe Rollout::UI::Helpers do
  # Create a test class that includes the helpers module
  let(:helper_class) do
    Class.new do
      include Rollout::UI::Helpers
      
      attr_accessor :request, :params
      
      def initialize
        @params = {}
      end
      
      def redirect(path)
        throw :redirect, path
      end
    end
  end
  
  let(:helper) { helper_class.new }
  let(:request) { double('request', script_name: '/rollout') }
  
  before do
    helper.request = request
  end

  describe 'path helpers' do
    describe '#stylesheet_path' do
      it 'returns path to stylesheet with script name prefix' do
        expect(helper.stylesheet_path('tailwind.min')).to eq('/rollout/css/tailwind.min.css')
      end
    end

    describe '#index_path' do
      it 'returns the index path with script name prefix' do
        expect(helper.index_path).to eq('/rollout/')
      end
    end

    describe '#new_feature_path' do
      it 'returns the new feature path with script name prefix' do
        expect(helper.new_feature_path).to eq('/rollout/features/new')
      end
    end

    describe '#feature_path' do
      it 'returns the feature path for a given feature name' do
        expect(helper.feature_path('my_feature')).to eq('/rollout/features/my_feature')
      end

      it 'URL-encodes feature names with special characters' do
        expect(helper.feature_path('feature with spaces')).to eq('/rollout/features/feature%20with%20spaces')
        expect(helper.feature_path('feature/with/slashes')).to eq('/rollout/features/feature%2Fwith%2Fslashes')
        expect(helper.feature_path('feature&special')).to eq('/rollout/features/feature%26special')
      end
    end

    describe '#delete_feature_path' do
      it 'returns the delete feature path for a given feature name' do
        expect(helper.delete_feature_path('my_feature')).to eq('/rollout/features/my_feature/delete')
      end

      it 'URL-encodes feature names with special characters' do
        expect(helper.delete_feature_path('feature with spaces')).to eq('/rollout/features/feature%20with%20spaces/delete')
        expect(helper.delete_feature_path('feature&special')).to eq('/rollout/features/feature%26special/delete')
      end
    end

    describe '#activate_percentage_feature_path' do
      it 'returns the activate percentage path with percentage query param' do
        expect(helper.activate_percentage_feature_path('my_feature', 50)).to eq('/rollout/features/my_feature/activate-percentage?percentage=50.0')
      end

      it 'converts percentage to float' do
        expect(helper.activate_percentage_feature_path('my_feature', '75')).to eq('/rollout/features/my_feature/activate-percentage?percentage=75.0')
      end

      it 'URL-encodes feature names with special characters' do
        expect(helper.activate_percentage_feature_path('feature with spaces', 50)).to eq('/rollout/features/feature%20with%20spaces/activate-percentage?percentage=50.0')
        expect(helper.activate_percentage_feature_path('feature&special', 50)).to eq('/rollout/features/feature%26special/activate-percentage?percentage=50.0')
      end
    end
  end

  describe '#config' do
    it 'returns the Rollout::UI config' do
      expect(helper.config).to eq(Rollout::UI.config)
    end
  end

  describe '#rollout' do
    it 'returns the rollout instance from config' do
      expect(helper.rollout).to eq(ROLLOUT)
    end

    it 'memoizes the result' do
      first_call = helper.rollout
      second_call = helper.rollout
      
      expect(first_call).to equal(second_call)
    end
  end

  describe '#has_logging?' do
    it 'returns true when rollout responds to logging' do
      logging_rollout = double('rollout', logging: double('logging'))
      helper.instance_variable_set(:@rollout, logging_rollout)
      
      expect(helper.has_logging?).to be true
    end

    it 'returns false when rollout does not respond to logging' do
      expect(helper.has_logging?).to be false
    end
  end

  describe '#with_rollout_context' do
    it 'yields without context when rollout does not support logging' do
      rollout = ROLLOUT
      yielded = false
      
      helper.with_rollout_context(rollout, actor: 'test') { yielded = true }
      
      expect(yielded).to be true
    end

    it 'calls logging.with_context when rollout supports logging' do
      logging = double('logging')
      rollout = double('rollout', logging: logging)
      
      expect(logging).to receive(:with_context).with({ actor: 'test' }).and_yield
      
      yielded = false
      helper.with_rollout_context(rollout, actor: 'test') { yielded = true }
      
      expect(yielded).to be true
    end
  end

  describe '#feature_count_badge_classes' do
    it 'returns green classes for count 0-14' do
      expect(helper.feature_count_badge_classes(0)).to eq('bg-emerald-100 text-emerald-600')
      expect(helper.feature_count_badge_classes(14)).to eq('bg-emerald-100 text-emerald-600')
    end

    it 'returns yellow classes for count 15-29' do
      expect(helper.feature_count_badge_classes(15)).to eq('bg-yellow-100 text-yellow-700')
      expect(helper.feature_count_badge_classes(29)).to eq('bg-yellow-100 text-yellow-700')
    end

    it 'returns orange classes for count 30-44' do
      expect(helper.feature_count_badge_classes(30)).to eq('bg-orange-100 text-orange-600')
      expect(helper.feature_count_badge_classes(44)).to eq('bg-orange-100 text-orange-600')
    end

    it 'returns red classes for count 45+' do
      expect(helper.feature_count_badge_classes(45)).to eq('bg-red-100 text-red-600')
      expect(helper.feature_count_badge_classes(100)).to eq('bg-red-100 text-red-600')
    end
  end

  describe '#time_ago' do
    it 'returns empty string for nil time' do
      expect(helper.time_ago(nil)).to eq('')
    end

    it 'returns "just now" for current time' do
      expect(helper.time_ago(Time.now)).to eq('just now')
    end

    it 'returns "a second ago" for 1 second ago' do
      expect(helper.time_ago(Time.now - 1)).to eq('a second ago')
    end

    it 'returns seconds ago for 2-59 seconds' do
      expect(helper.time_ago(Time.now - 30)).to eq('30 seconds ago')
    end

    it 'returns "a minute ago" for 60-119 seconds' do
      expect(helper.time_ago(Time.now - 90)).to eq('a minute ago')
    end

    it 'returns minutes ago for 2-59 minutes' do
      expect(helper.time_ago(Time.now - 300)).to eq('5 minutes ago')
    end

    it 'returns "an hour ago" for around 1 hour' do
      expect(helper.time_ago(Time.now - 3600)).to eq('an hour ago')
    end

    it 'returns hours ago for 2-23 hours' do
      expect(helper.time_ago(Time.now - 7200)).to eq('2 hours ago')
    end

    it 'returns "a day ago" for around 1 day' do
      expect(helper.time_ago(Time.now - 86400)).to eq('a day ago')
    end

    it 'returns days ago for 2-6 days' do
      expect(helper.time_ago(Time.now - 259200)).to eq('3 days ago')
    end

    it 'returns "a week ago" for around 1 week' do
      expect(helper.time_ago(Time.now - 604800)).to eq('a week ago')
    end

    it 'returns weeks ago for 2+ weeks' do
      expect(helper.time_ago(Time.now - 1209600)).to eq('2 weeks ago')
    end
  end

  describe '#format_change_key' do
    it 'removes "data." prefix from key' do
      expect(helper.format_change_key('data.team')).to eq('team')
      expect(helper.format_change_key('data.description')).to eq('description')
    end

    it 'leaves keys without "data." prefix unchanged' do
      expect(helper.format_change_key('percentage')).to eq('percentage')
    end

    it 'converts symbols to strings' do
      expect(helper.format_change_key(:percentage)).to eq('percentage')
    end
  end

  describe '#format_change_value' do
    it 'formats arrays with brackets and commas' do
      expect(helper.format_change_value(['a', 'b', 'c'])).to eq('[a, b, c]')
    end

    it 'formats strings with quotes' do
      expect(helper.format_change_value('test')).to eq("'test'")
    end

    it 'formats nil with quotes' do
      expect(helper.format_change_value(nil)).to eq("''")
    end

    it 'returns numbers as-is' do
      expect(helper.format_change_value(50)).to eq(50)
      expect(helper.format_change_value(100.0)).to eq(100.0)
    end
  end

  describe '#json_request?' do
    it 'returns true when Accept header is application/json' do
      allow(request).to receive(:env).and_return({ 'HTTP_ACCEPT' => 'application/json' })
      
      expect(helper.json_request?).to be true
    end

    it 'returns false when Accept header is not application/json' do
      allow(request).to receive(:env).and_return({ 'HTTP_ACCEPT' => 'text/html' })
      
      expect(helper.json_request?).to be false
    end

    it 'returns false when Accept header is missing' do
      allow(request).to receive(:env).and_return({})
      
      expect(helper.json_request?).to be false
    end
  end

  describe '#extract_team_from_params' do
    it 'returns team param when not __new__' do
      helper.params = { team: 'Engineering' }
      
      expect(helper.extract_team_from_params).to eq('Engineering')
    end

    it 'returns new_team param when team is __new__' do
      helper.params = { team: '__new__', new_team: 'Platform' }
      
      expect(helper.extract_team_from_params).to eq('Platform')
    end

    it 'strips whitespace from result' do
      helper.params = { team: '  Engineering  ' }
      
      expect(helper.extract_team_from_params).to eq('Engineering')
    end

    it 'handles nil team gracefully' do
      helper.params = { team: nil }
      
      expect(helper.extract_team_from_params).to eq('')
    end
  end

  describe '#validate_team!' do
    it 'redirects with error when team is empty' do
      result = catch(:redirect) { helper.validate_team!('', '/features/test') }

      expect(result).to eq('/features/test?error=Team+is+required')
    end

    it 'redirects with error when team is less than 2 characters' do
      result = catch(:redirect) { helper.validate_team!('A', '/features/test') }

      expect(result).to eq('/features/test?error=Team+name+must+be+at+least+2+characters')
    end

    it 'returns the team when valid' do
      expect(helper.validate_team!('Engineering', '/features/test')).to eq('Engineering')
    end

    it 'accepts team with exactly 2 characters' do
      expect(helper.validate_team!('AB', '/features/test')).to eq('AB')
    end

    it 'properly encodes error messages' do
      result = catch(:redirect) { helper.validate_team!('', '/features/test') }
      expect(result).not_to include('error=Team is required')
      expect(result).to include('error=Team+is+required')
    end
  end

  describe '#team_names' do
    before do
      ROLLOUT.activate(:teams_test_feature1)
      ROLLOUT.with_feature(:teams_test_feature1) do |feature|
        feature.data.update(team: 'Engineering')
      end
      
      ROLLOUT.activate(:teams_test_feature2)
      ROLLOUT.with_feature(:teams_test_feature2) do |feature|
        feature.data.update(team: 'Platform')
      end
      
      ROLLOUT.activate(:teams_test_feature3)
      ROLLOUT.with_feature(:teams_test_feature3) do |feature|
        feature.data.update(team: 'Engineering') # duplicate team
      end
      
      ROLLOUT.activate(:teams_test_feature4)
      # No team set - should be excluded
    end

    after do
      ROLLOUT.delete(:teams_test_feature1)
      ROLLOUT.delete(:teams_test_feature2)
      ROLLOUT.delete(:teams_test_feature3)
      ROLLOUT.delete(:teams_test_feature4)
    end

    it 'returns unique team names' do
      result = helper.team_names
      
      expect(result).to contain_exactly('Engineering', 'Platform')
    end

    it 'returns team names sorted alphabetically' do
      result = helper.team_names
      
      expect(result).to eq(['Engineering', 'Platform'])
    end

    it 'excludes features without teams' do
      result = helper.team_names
      
      expect(result).not_to include(nil)
      expect(result).not_to include('')
    end

    it 'excludes empty string teams' do
      ROLLOUT.with_feature(:teams_test_feature4) do |feature|
        feature.data.update(team: '')
      end
      
      result = helper.team_names
      
      expect(result).not_to include('')
    end

    it 'memoizes the result' do
      first_call = helper.team_names
      second_call = helper.team_names
      
      expect(first_call).to equal(second_call)
    end
  end

  describe '#filtered_features' do
    before do
      ROLLOUT.activate(:filter_test_feature1)
      ROLLOUT.activate_user(:filter_test_feature1, 'user1')
      ROLLOUT.activate_group(:filter_test_feature1, :admins)
      
      ROLLOUT.activate(:filter_test_feature2)
      ROLLOUT.activate_user(:filter_test_feature2, 'user2')
      ROLLOUT.activate_group(:filter_test_feature2, :beta)
    end
    
    after do
      ROLLOUT.delete(:filter_test_feature1)
      ROLLOUT.delete(:filter_test_feature2)
    end

    it 'returns all features when no filters applied' do
      helper.params = {}
      
      result = helper.filtered_features
      
      expect(result.map(&:name)).to contain_exactly(:filter_test_feature1, :filter_test_feature2)
    end

    it 'filters by user param' do
      helper.params = { user: 'user1' }
      
      result = helper.filtered_features
      
      expect(result.map(&:name)).to contain_exactly(:filter_test_feature1)
    end

    it 'filters by group param' do
      helper.params = { group: 'admins' }
      
      result = helper.filtered_features
      
      expect(result.map(&:name)).to contain_exactly(:filter_test_feature1)
    end

    it 'filters by both user and group' do
      helper.params = { user: 'user1', group: 'admins' }
      
      result = helper.filtered_features
      
      expect(result.map(&:name)).to contain_exactly(:filter_test_feature1)
    end

    it 'returns empty when no features match' do
      helper.params = { user: 'nonexistent' }
      
      result = helper.filtered_features
      
      expect(result).to be_empty
    end
  end

  describe '#feature_to_hash' do
    let(:rollout) { ROLLOUT }
    
    before do
      rollout.activate(:hash_test_feature)
      rollout.with_feature(:hash_test_feature) do |feature|
        feature.data.update(team: 'TestTeam', description: 'Test description')
      end
      rollout.activate_group(:hash_test_feature, :admins)
    end
    
    after do
      rollout.delete(:hash_test_feature)
    end

    it 'returns a hash with expected keys' do
      feature = rollout.get(:hash_test_feature)
      
      result = helper.feature_to_hash(feature)
      
      expect(result).to include(
        name: :hash_test_feature,
        percentage: 100.0,
        groups: [:admins],
        team: 'TestTeam'
      )
      expect(result[:data]).to include('team' => 'TestTeam', 'description' => 'Test description')
    end
  end

  describe '#consumer_cache_break?' do
    it 'returns true when consumer_cache_break data is "true"' do
      feature = double('feature', data: { 'consumer_cache_break' => 'true' })
      
      expect(helper.consumer_cache_break?(feature)).to be true
    end

    it 'returns false when consumer_cache_break data is not "true"' do
      feature = double('feature', data: { 'consumer_cache_break' => 'false' })
      
      expect(helper.consumer_cache_break?(feature)).to be false
    end

    it 'returns false when consumer_cache_break data is nil' do
      feature = double('feature', data: {})
      
      expect(helper.consumer_cache_break?(feature)).to be false
    end
  end

  describe '#confirmation_message' do
    it 'includes cache warning when consumer_cache_break is enabled' do
      feature = double('feature', name: 'my_feature', data: { 'consumer_cache_break' => 'true' })
      
      message = helper.confirmation_message(feature, 50)
      
      expect(message).to include('20 minutes')
      expect(message).to include('my_feature')
      expect(message).to include('50%')
    end

    it 'returns simple message when consumer_cache_break is disabled' do
      feature = double('feature', name: 'my_feature', data: {})
      
      message = helper.confirmation_message(feature, 50)
      
      expect(message).not_to include('20 minutes')
      expect(message).to include('my_feature')
      expect(message).to include('50%')
    end
  end

  describe '#get_high_percent_activate' do
    it 'returns 100 when consumer_cache_break is disabled' do
      feature = double('feature', data: {})
      
      expect(helper.get_high_percent_activate(feature)).to eq(100)
    end

    it 'returns percentage + 20 when consumer_cache_break is enabled' do
      feature = double('feature', percentage: 50.0, data: { 'consumer_cache_break' => 'true' })
      
      expect(helper.get_high_percent_activate(feature)).to eq(70.0)
    end

    it 'caps at 100 when consumer_cache_break is enabled' do
      feature = double('feature', percentage: 90.0, data: { 'consumer_cache_break' => 'true' })
      
      expect(helper.get_high_percent_activate(feature)).to eq(100)
    end
  end

  describe '#get_low_percent_activate' do
    it 'returns 0 when consumer_cache_break is disabled' do
      feature = double('feature', data: {})
      
      expect(helper.get_low_percent_activate(feature)).to eq(0)
    end

    it 'returns percentage - 20 when consumer_cache_break is enabled' do
      feature = double('feature', percentage: 50.0, data: { 'consumer_cache_break' => 'true' })
      
      expect(helper.get_low_percent_activate(feature)).to eq(30.0)
    end

    it 'floors at 0 when consumer_cache_break is enabled' do
      feature = double('feature', percentage: 10.0, data: { 'consumer_cache_break' => 'true' })
      
      expect(helper.get_low_percent_activate(feature)).to eq(0)
    end
  end

  describe '#team_badge_colors' do
    it 'returns slate colors for empty team name' do
      expect(helper.team_badge_colors('')).to eq('bg-slate-100 text-slate-600')
      expect(helper.team_badge_colors(nil)).to eq('bg-slate-100 text-slate-600')
      expect(helper.team_badge_colors('   ')).to eq('bg-slate-100 text-slate-600')
    end

    it 'returns consistent colors for the same team name' do
      color1 = helper.team_badge_colors('Engineering')
      color2 = helper.team_badge_colors('Engineering')
      
      expect(color1).to eq(color2)
    end

    it 'is case insensitive' do
      color1 = helper.team_badge_colors('Engineering')
      color2 = helper.team_badge_colors('ENGINEERING')
      
      expect(color1).to eq(color2)
    end

    it 'returns a valid Tailwind color class' do
      color = helper.team_badge_colors('Platform')
      
      expect(color).to match(/bg-\w+-100 text-\w+-\d+/)
    end
  end
end
