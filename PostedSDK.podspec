Pod::Spec.new do |s|
  s.name             = 'PostedSDK'
  s.version          = '3.0.0'
  s.summary          = 'PostedSDK — CPI tracking and deep link attribution for native iOS apps.'

  s.description      = <<-DESC
    PostedSDK provides seamless handling of deferred links, deep links, and CPI
    attribution in native iOS applications, including link resolution, runtime
    handling, and analytics.
  DESC

  # TODO(B7): GitHub org/repo rename (*-detour -> posted-sdk-*) is board-gated (G1);
  # metadata is staged against the target repo name now, finalize on rename.
  s.homepage         = 'https://github.com/posted-attribution/posted-sdk-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Software Mansion' => 'yuriy@postedapp.com' }
  s.source           = {
    :git => 'https://github.com/posted-attribution/posted-sdk-ios.git',
    :tag => s.version.to_s
  }
  s.social_media_url = 'https://github.com/posted-attribution/posted-sdk-ios'

  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.5'

  s.source_files = 'Sources/PostedSDK/**/*.swift'
end
