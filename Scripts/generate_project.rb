#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Peekaboo.xcodeproj')

FileUtils.rm_rf(PROJECT_PATH) if File.exist?(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH, false, 77)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2660'
project.root_object.attributes['LastUpgradeCheck'] = '2660'

app = project.new_target(:application, 'Peekaboo', :osx, '14.0')
unit_tests = project.new_target(:unit_test_bundle, 'PeekabooTests', :osx, '14.0')
ui_tests = project.new_target(:ui_test_bundle, 'PeekabooUITests', :osx, '14.0')
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

app_group = add_swift_sources(project, app, 'Peekaboo', 'Peekaboo')
tests_group = add_swift_sources(project, unit_tests, 'PeekabooTests', 'PeekabooTests')
ui_tests_group = add_swift_sources(project, ui_tests, 'PeekabooUITests', 'PeekabooUITests')

assets = app_group.new_file('Resources/Assets.xcassets')
app.resources_build_phase.add_file_reference(assets)
app_group.new_file('Peekaboo.entitlements')
app_group.new_file('Info.plist')

project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
end

app.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.emanueledipietro.Peekaboo'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] = 'Peekaboo/Info.plist'
  settings['CODE_SIGN_ENTITLEMENTS'] = 'Peekaboo/Peekaboo.entitlements'
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
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.emanueledipietro.PeekabooTests'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
  settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Peekaboo.app/Contents/MacOS/Peekaboo'
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end

ui_tests.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.emanueledipietro.PeekabooUITests'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
  settings['TEST_TARGET_NAME'] = 'Peekaboo'
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(unit_tests)
scheme.add_test_target(ui_tests)
scheme.save_as(PROJECT_PATH, 'Peekaboo', true)

project.save
puts "Generated #{PROJECT_PATH}"
