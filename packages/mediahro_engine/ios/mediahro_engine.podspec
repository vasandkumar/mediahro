#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint mediahro_engine.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'mediahro_engine'
  s.version          = '0.0.1'
  s.summary          = 'Mediahro engine: libmpv playback and render bridge.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'mediahro_engine/Sources/mediahro_engine/**/*.swift'
  # libmpv xcframeworks staged by tool/stage_native.py (LGPL, dynamic).
  s.frameworks = 'OpenGLES', 'CoreVideo', 'IOSurface', 'AVFoundation'
  s.vendored_frameworks = 'mediahro_engine/Frameworks/*.xcframework'
  s.resource_bundles = {'mediahro_engine_privacy' => ['mediahro_engine/Sources/mediahro_engine/PrivacyInfo.xcprivacy']}
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
end
