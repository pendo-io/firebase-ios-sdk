Pod::Spec.new do |s|
  s.name             = 'PendoCrashReporter'
  s.version          = '12.11.0'
  s.summary          = 'Pendo standalone crash reporting engine for iOS.'
  s.description      = 'Pendo internal crash reporter stripped from Firebase Crashlytics.'
  s.homepage         = 'https://github.com/pendo-io/firebase-ios-sdk'
  s.license          = { :type => 'Apache-2.0', :file => 'Crashlytics/LICENSE' }
  s.authors          = 'Google, Inc.', 'Pendo.io'
  s.source           = {
    :git => 'https://github.com/pendo-io/firebase-ios-sdk.git',
    :tag => 'pendo-' + s.version.to_s
  }

  ios_deployment_target = '11.0'

  s.swift_version = '5.9'

  s.ios.deployment_target = ios_deployment_target

  s.cocoapods_version = '>= 1.12.0'
  s.prefix_header_file = 'Crashlytics/Crashlytics/PNDCrashReporter-prefix.pch'

  s.source_files = [
    'Crashlytics/Crashlytics/**/*.{c,h,m,mm,swift}',
    'Crashlytics/Shared/**/*.{c,h,m,mm}',
    'Crashlytics/third_party/**/*.{c,h,m,mm}',
  ]

  s.public_header_files = [
    'Crashlytics/Crashlytics/Public/FirebaseCrashlytics/PendoCrashReporter.h'
  ]

  s.preserve_paths = [
    'Crashlytics/README.md',
    'run',
    'upload-symbols',
    'CrashlyticsInputFiles.xcfilelist',
  ]

  s.libraries = 'c++', 'z'
  s.ios.frameworks = 'Security', 'SystemConfiguration'

  s.ios.pod_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' =>
      'CLS_SDK_NAME="Crashlytics iOS SDK"',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}"',
  }

  s.test_spec 'unit' do |unit_tests|
    unit_tests.scheme = { :code_coverage => true }
    unit_tests.platforms = {
      :ios => ios_deployment_target
    }
    unit_tests.source_files = 'Crashlytics/UnitTests/*.[mh]',
                              'Crashlytics/UnitTests/*/*.[mh]',
                              'Crashlytics/UnitTestsSwift/*.swift'
    unit_tests.resources = 'Crashlytics/UnitTests/Data/*',
                           'Crashlytics/UnitTests/*.clsrecord',
                           'Crashlytics/UnitTests/FIRCLSMachO/machO_data/*'
    unit_tests.requires_app_host = true
  end
end
