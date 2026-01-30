Pod::Spec.new do |s|
  s.name             = 'story_editor_pro'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter story editor plugin with native camera support.'
  s.description      = <<-DESC
A Flutter story editor plugin with native camera support for iOS and Android.
                       DESC
  s.homepage         = 'https://github.com/example/story_editor_pro'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'
end
