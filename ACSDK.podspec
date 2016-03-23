Pod::Spec.new do |s|
  s.name         = "ACSDK"
  s.version      = "3.1.0-beta1"
  s.summary      = "The Allychat Framework."
  s.license      = { :type => 'MIT' }
  s.homepage     = 'https://github.com/allychat/ios-sdk'
  s.author       = { "Alexandr Turyev" => "ekklesiarhia@gmail.com"}
  s.platform     = :ios, "7.0"
  s.source       = { :git => "https://github.com/allychat/ios-sdk.git", :tag => "3.1.0-beta1" }
  s.framework    = "ACSDK"
  s.requires_arc = true
  s.frameworks   = "Security", "CFNetwork"
  s.library      = "icucore"
  s.vendored_framework = 'ACSDK.framework'

end
