Pod::Spec.new do |s|
  s.name             = 'PostedSDK'
  s.version          = '1.0.0'
  s.summary          = 'PostedSDK — install reporting for ad attribution in native iOS apps.'

  s.description      = <<-DESC
    PostedSDK reports app installs to Posted. The backend matches each install to
    the ad click that led to it and reports it back to the ad network as a
    conversion. One call, reportInstall, sent once per install.
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
