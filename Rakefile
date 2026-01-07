require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

desc "Build Tailwind CSS (minified)"
task :tailwind do
  sh "./tailwindcss -i lib/rollout/ui/public/css/input.css -o lib/rollout/ui/public/css/tailwind.min.css --minify"
end

desc "Watch Tailwind CSS for development"
task :tailwind_watch do
  sh "./tailwindcss -i lib/rollout/ui/public/css/input.css -o lib/rollout/ui/public/css/tailwind.min.css --watch"
end
