require 'xcodeproj'
project = Xcodeproj::Project.new('CrashlyticsSample.xcodeproj')
app_target = project.new_target(:application, 'CrashlyticsSample', :ios, '15.0')
app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.example.CrashlyticsSample'
  config.build_settings['INFOPLIST_FILE'] = 'Info.plist'
end

main_m = project.main_group.new_file('main.m')
app_del_h = project.main_group.new_file('AppDelegate.h')
app_del_m = project.main_group.new_file('AppDelegate.m')
crash_help_h = project.main_group.new_file('CrashHelpers.h')
crash_help_mm = project.main_group.new_file('CrashHelpers.mm')
info_plist = project.main_group.new_file('Info.plist')

app_target.add_file_references([main_m, app_del_m, crash_help_mm])
project.save