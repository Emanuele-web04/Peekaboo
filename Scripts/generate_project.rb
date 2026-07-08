#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Peakaboo.xcodeproj')

FileUtils.rm_rf(PROJECT_PATH) if File.exist?(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH, false, 77)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2660'
project.root_object.attributes['LastUpgradeCheck'] = '2660'

app = project.new_target(:application, 'Peakaboo', :osx, '14.0')
unit_tests = project.new_target(:unit_test_bundle, 'PeakabooTests', :osx, '14.0')
ui_tests = project.new_target(:ui_test_bundle, 'PeakabooUITests', :osx, '14.0')
unit_tests.add_dependency(app)
ui_tests.add_dependency(app)

def add_swift_sources(project, target, group_name, directory)
  group = project.main_group.new_group(group_name, group_name)
  Dir.glob(File.join(ROOT, directory, '**', '*.swift')).sort.each do |path|
    relative = path.delete_prefix("#{ROOT}/")
    reference = group.new_file(relative.delete_prefix("#{group_name}/"))
    target.source_build_phase.add_file_reference(reference)
  end
  group
end

app_group = add_swift_sources(project, app, 'Peakaboo', 'Peakaboo')
tests_group = add_swift_sources(project, unit_tests, 'PeakabooTests', 'PeakabooTests')
ui_tests_group = add_swift_sources(project, ui_tests, 'PeakabooUITests', 'PeakabooUITests')

assets = app_group.new_file('Resources/Assets.xcassets')
app.resources_build_phase.add_file_reference(assets)
app_group.new_file('Peakaboo.entitlements')

project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
end

app.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.emanueledipietro.Peakaboo'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'Peakaboo'
  settings['INFOPLIST_KEY_LSApplicationCategoryType'] = 'public.app-category.productivity'
  settings['INFOPLIST_KEY_LSUIElement'] = 'YES'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'Peakaboo/Peakaboo.entitlements'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['ENABLE_APP_SANDBOX'] = 'YES'
  settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  settings['SWIFT_VERSION'] = '5.0'
  settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  settings['MARKETING_VERSION'] = '1.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
end

unit_tests.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.emanueledipietro.PeakabooTests'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
  settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Peakaboo.app/Contents/MacOS/Peakaboo'
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end

ui_tests.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.emanueledipietro.PeakabooUITests'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
  settings['TEST_TARGET_NAME'] = 'Peakaboo'
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(unit_tests)
scheme.add_test_target(ui_tests)
scheme.save_as(PROJECT_PATH, 'Peakaboo', true)

project.save
puts "Generated #{PROJECT_PATH}"
