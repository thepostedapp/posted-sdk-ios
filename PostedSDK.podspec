Pod::Spec.new do |s|
  s.name             = 'PostedSDK'
  s.version          = '4.0.0'
  s.summary          = 'PostedSDK — CPI tracking and deep link attribution for native iOS apps.'

  s.description      = <<-DESC
    PostedSDK provides seamless handling of deferred links, deep links, and CPI
    attribution in native iOS applications, including link resolution, runtime
    handling, and analytics.
  DESC

  s.homepage         = 'https://github.com/thepostedapp/posted-sdk-ios'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Posted' => 'yuriy@postedapp.com' }
  s.source           = {
    :git => 'https://github.com/thepostedapp/posted-sdk-ios.git',
    :tag => s.version.to_s
  }
  s.social_media_url = 'https://github.com/thepostedapp/posted-sdk-ios'

  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.5'

  s.source_files = 'Sources/PostedSDK/**/*.swift'
end
