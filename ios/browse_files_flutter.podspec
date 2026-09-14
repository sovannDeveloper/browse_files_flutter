#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint browse_files_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'browse_files_flutter'
  s.version          = '0.1.0'
  s.summary          = 'A Telegram-style attachment sheet: system pickers and camera, no library permission.'
  s.description      = <<-DESC
Photos, videos, documents and camera captures through the system pickers, copied into the app
cache. No photo library permission is requested.
                       DESC
  s.homepage         = 'https://github.com/kedtec/browse_files_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'KEDTEC' => 'dev@kedtec.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks = 'AVFoundation', 'ImageIO', 'PhotosUI', 'UniformTypeIdentifiers'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'browse_files_flutter_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
