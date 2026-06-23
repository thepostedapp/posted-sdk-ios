Pod::Spec.new do |s|
  s.name             = 'PostedSDK'
  s.version          = '2.0.0'
  s.summary          = 'PostedSDK — CPI tracking and deep link attribution for native iOS apps.'

  s.description      = <<-DESC
    PostedSDK provides seamless handling of deferred links, deep links, and CPI
    attribution in native iOS applications, including link resolution, runtime
    handling, and analytics.
  DESC

  s.homepage         = 'https://github.com/software-mansion-labs/ios-detour'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Software Mansion' => 'contact@godetour.dev' }
  s.source           = {
    :git => 'https://github.com/software-mansion-labs/ios-detour.git',
    :tag => s.version.to_s
  }

  s.ios.deployment_target = '13.0'
  s.swift_version         = '5.5'

  s.source_files = 'Sources/PostedSDK/**/*.swift'
end
