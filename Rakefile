# frozen_string_literal: true

require 'rake/testtask'
require 'rake/extensiontask'

Rake::TestTask.new do |t|
  t.verbose = true
end

Rake::ExtensionTask.new 'cruzzy' do |ext|
  ext.lib_dir = 'lib/cruzzy'
end

Rake::ExtensionTask.new 'dummy' do |ext|
  ext.lib_dir = 'lib/dummy'
end
