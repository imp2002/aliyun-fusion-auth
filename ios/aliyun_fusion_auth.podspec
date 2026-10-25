Pod::Spec.new do |s|
  s.name             = 'aliyun_fusion_auth'
  s.version          = '0.1.8'
  s.summary          = 'Flutter bridge for Aliyun fusion phone authentication.'
  s.homepage         = 'https://pub.dev/packages/aliyun_fusion_auth'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = 'aliyun_fusion_auth contributors'
  # Flutter installs this pod from the package directory. No remote source is required.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/AliyunFusionAuthPlugin.h'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.requires_arc     = true
  s.static_framework = true
  s.vendored_frameworks = 'Frameworks/AlicomFusionAuth.xcframework'
  # The vendor looks up these bundles in the application's main bundle.
  s.resources        = 'Resources/*.bundle'
  s.frameworks       = 'UIKit', 'SafariServices', 'Network', 'CoreTelephony', 'SystemConfiguration', 'Security', 'WebKit'
  s.libraries        = 'sqlite3'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'OTHER_LDFLAGS' => '$(inherited) -ObjC' }
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -ObjC' }
end
