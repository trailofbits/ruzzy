# frozen_string_literal: true

require 'rake/testtask'
require 'rake/extensiontask'

Rake::TestTask.new do |t|
  require 'ruzzy'

  # This is required for tests that use cruzzy functionality
  ENV['LD_PRELOAD'] = Ruzzy.ext_path + '/' + 'asan_with_fuzzer.so'

  t.verbose = true
end

Rake::ExtensionTask.new 'cruzzy' do |ext|
  ext.lib_dir = 'lib/cruzzy'
end

Rake::ExtensionTask.new 'dummy' do |ext|
  ext.lib_dir = 'lib/dummy'
end
