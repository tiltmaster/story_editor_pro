require 'xcodeproj'
require 'pathname'

host = File.expand_path(ARGV.fetch(0))
project = Xcodeproj::Project.open(File.join(host, 'ios/Runner.xcodeproj'))
project.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0' }
project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    if target.name == 'RunnerTests'
      # Hostless tests load MediaPipe's static registries only once.
      config.build_settings.delete('TEST_HOST')
      config.build_settings.delete('BUNDLE_LOADER')
    end
  end
end
tests = project.targets.find { |t| t.name == 'RunnerTests' }
abort 'Generated host is missing RunnerTests' unless tests
sources = Dir.glob(File.expand_path('../../ios/Tests/**/*.swift', __dir__)).sort
abort 'No native XCTest sources found' if sources.empty?
sources.each do |source|
  reference = project.main_group.new_file(Pathname(source).relative_path_from(Pathname(File.join(host, 'ios'))).to_s)
  tests.source_build_phase.add_file_reference(reference)
end
project.save
