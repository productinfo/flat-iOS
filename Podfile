platform :ios, '13.0'
target 'Flat' do
  use_frameworks!

  pod 'LookinServer', :configurations => ['Flat_Debug']
  
  pod 'RxSwift'
  pod 'RxCocoa'
  pod 'NSObject+Rx'
  pod 'RxDataSources'
  
  pod 'AcknowList'
  pod 'CropViewController'
  pod 'Siren'
  pod 'IQKeyboardManagerSwift'
  pod 'Zip'
  pod 'lottie-ios'
  pod 'libPhoneNumber-iOS'
  pod 'ScreenCorners'
  
  pod 'AgoraRtm_iOS'
  pod 'AgoraRtcEngine_iOS', '4.1.0'
  pod 'Fastboard/fpa', '2.0.0-alpha.13'
  pod 'Whiteboard', '2.17.0-alpha.20'
  pod 'Whiteboard/SyncPlayer', '2.17.0-alpha.20'
  pod 'SyncPlayer', '0.3.3'
  pod 'ViewDragger', '1.1.0'
  
  pod 'MBProgressHUD', '~> 1.2.0'
  pod 'Kingfisher'
  pod 'Hero'
  pod 'SnapKit'
  pod 'DZNEmptyDataSet'
  
  pod 'Logging'
  pod 'SwiftyBeaver'
  pod 'AliyunLogProducer/Core'
  pod 'AliyunLogProducer/Bricks'
  
  pod 'WechatOpenSDK'
  pod 'FirebaseCrashlytics'
  pod 'Firebase/AnalyticsWithoutAdIdSupport'
  
  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
      end
    end
    
    installer.pods_project.targets.each do |target|
      if target.respond_to?(:product_type) and target.product_type == "com.apple.product-type.bundle"
        target.build_configurations.each do |config|
          config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        end
      end
    end
    
    installer.pods_project.build_configurations.each do |config|
      config.build_settings["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] = "arm64"
      if config.name.include?("Debug")
        config.build_settings["ONLY_ACTIVE_ARCH"] = "YES"
      end
    end
  end
end

