Pod::Spec.new do |s|
  s.name             = 'story_editor_pro'
  s.version          = '1.4.0'
  s.summary          = 'A Flutter story editor plugin with native camera support.'
  s.description      = <<-DESC
A Flutter story editor plugin with native camera support for iOS and Android.
                       DESC
  s.homepage         = 'https://github.com/tiltmaster/story_editor_pro'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Ahmet Balkan' => 'https://github.com/ahmetbalkan' }
  s.source           = {
    :git => 'https://github.com/tiltmaster/story_editor_pro.git',
    :tag => s.version.to_s
  }
  s.source_files = 'Classes/**/*'
  # MediaPipe ships as a static XCFramework. Declaring this pod static avoids
  # an invalid dynamic-framework -> static-binary transitive dependency.
  s.static_framework = true
  s.dependency 'Flutter'
  # Apache-2.0 MediaPipe Tasks; the face-landmarker model is shipped as a
  # Flutter asset and resolved at runtime by StoryEditorProPlugin.
  s.dependency 'MediaPipeTasksVision', '0.10.35'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreImage', 'Metal', 'Vision'
  s.resource_bundles = {
    'story_editor_pro_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
  # MediaPipeTasksVision 0.10.35 requires iOS 15.0.
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'

  s.test_spec 'Tests' do |tests|
    tests.source_files = 'Tests/**/*'
    tests.frameworks = 'XCTest'
  end
end
