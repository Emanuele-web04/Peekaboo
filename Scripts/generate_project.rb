#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'
require 'fileutils'
require 'optparse'
require 'securerandom'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
DEFAULT_PROJECT_PATH = File.join(ROOT, 'Peekaboo.xcodeproj')
options = { project_path: DEFAULT_PROJECT_PATH }

OptionParser.new do |parser|
  parser.banner = 'Usage: ruby Scripts/generate_project.rb [options]'
  parser.on('--output PATH', 'Write the generated project to PATH') do |path|
    options[:project_path] = File.expand_path(path)
  end
  parser.on('-h', '--help', 'Show this help without changing the project') do
    puts parser
    exit
  end
end.parse!

project_path = options.fetch(:project_path)
FileUtils.mkdir_p(File.dirname(project_path))
staging_directory = Dir.mktmpdir('.peekaboo-project-', File.dirname(project_path))
at_exit { FileUtils.rm_rf(staging_directory) if File.exist?(staging_directory) }
staged_project_path = File.join(staging_directory, File.basename(project_path))
# xcodeproj 1.27 can emit Xcode 16 projects but does not expose Apple's
# compatibility object version 71 as a constructor option. Generate using its
# supported format, then normalize the serialized project below.
project = Xcodeproj::Project.new(staged_project_path, false, 77)
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
  settings['DEVELOPMENT_TEAM'] = 'HR24WHR326'
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

# xcodeproj includes the current random project/target UUIDs in proxy paths when
# predictabilizing target dependencies. Stable placeholders remove that random
# input; the real deterministic UUIDs are restored immediately afterwards.
target_proxies = project.objects.grep(Xcodeproj::Project::Object::PBXContainerItemProxy)
target_proxies.each do |proxy|
  proxy.container_portal = 'PROJECT'
  proxy.remote_global_id_string = 'APP_TARGET'
end
project.predictabilize_uuids
target_proxies.each do |proxy|
  proxy.container_portal = project.root_object.uuid
  proxy.remote_global_id_string = app.uuid
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(unit_tests)
scheme.add_test_target(ui_tests)
scheme.save_as(staged_project_path, 'Peekaboo', true)

project.save

project_file = File.join(staged_project_path, 'project.pbxproj')
project_contents = File.read(project_file)
project_contents.sub!("\tobjectVersion = 77;", "\tobjectVersion = 71;")
project_contents.gsub!(/^\s*minimizedProjectReferenceProxies = 0;\n/, '')
project_contents.gsub!(/^\s*preferredProjectObjectVersion = 77;\n/, '')
File.write(project_file, project_contents)

Xcodeproj::Project.open(staged_project_path)

backup_path = "#{project_path}.backup-#{Process.pid}-#{SecureRandom.hex(4)}"
FileUtils.mv(project_path, backup_path) if File.exist?(project_path)
begin
  FileUtils.mv(staged_project_path, project_path)
rescue StandardError
  FileUtils.mv(backup_path, project_path) if File.exist?(backup_path) && !File.exist?(project_path)
  raise
ensure
  FileUtils.rm_rf(backup_path) if File.exist?(project_path)
  FileUtils.rm_rf(staging_directory)
end

puts "Generated #{project_path}"
