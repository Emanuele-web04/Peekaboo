#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'rbconfig'
require 'tmpdir'

GENERATOR = File.join(__dir__, 'generate_project.rb')

def generate(destination)
  success = system(
    RbConfig.ruby,
    GENERATOR,
    '--output',
    destination,
    out: File::NULL,
    err: File::NULL
  )
  abort 'Project generation failed' unless success
end

def digest(project_path)
  files = [
    File.join(project_path, 'project.pbxproj'),
    File.join(project_path, 'xcshareddata/xcschemes/Peekaboo.xcscheme'),
    File.join(project_path, 'xcshareddata/xcschemes/PeekabooMobile.xcscheme')
  ]
  Digest::SHA256.hexdigest(files.map { |path| File.binread(path) }.join)
end

Dir.mktmpdir('peekaboo-project-check') do |directory|
  project_path = File.join(directory, 'generated', 'Peekaboo.xcodeproj')
  generate(project_path)
  first_digest = digest(project_path)
  generate(project_path)
  abort 'Project generation is not repeatable' unless digest(project_path) == first_digest
end

puts 'Project generation is repeatable'
