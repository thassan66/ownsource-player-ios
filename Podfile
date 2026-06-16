platform :ios, '16.0'
install! 'cocoapods', warn_for_unused_master_specs_repo: false
use_frameworks!

target 'OwnSourcePlayer' do
  pod 'MobileVLCKit', '3.7.3'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end
end

post_integrate do |_installer|
  project = Xcodeproj::Project.open(File.join(__dir__, 'OwnSourcePlayer.xcodeproj'))
  target = project.targets.find { |item| item.name == 'OwnSourcePlayer' }

  if target
    target.frameworks_build_phase.files.dup.each do |build_file|
      next unless build_file.display_name == 'Pods_OwnSourcePlayer.framework'

      build_file.remove_from_project
    end
  end

  project.files
    .select { |file| file.display_name == 'Pods_OwnSourcePlayer.framework' }
    .each(&:remove_from_project)

  project.save
end
