# frozen_string_literal: true

require 'rake/testtask'
require 'rake/extensiontask'

Rake::TestTask.new do |t|
  # This is required for tests that use cruzzy functionality
  ENV['LD_PRELOAD'] = ENV['ASAN_MERGED_LIB']
  t.verbose = true
end

Rake::ExtensionTask.new 'cruzzy' do |ext|
  ext.lib_dir = 'lib/cruzzy'
end
