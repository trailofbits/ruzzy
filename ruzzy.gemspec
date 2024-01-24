# frozen_string_literal: true

require 'rake'

Gem::Specification.new do |s|
  s.name                  = 'ruzzy'
  s.version               = '0.5.0'
  s.summary               = 'A Ruby C extension fuzzer'
  s.authors               = ['Trail of Bits']
  s.email                 = 'support@trailofbits.com'
  s.files                 = FileList['lib/**/*.rb', 'ext/**/*.{rb,c,h}']
  s.homepage              = 'https://rubygems.org/gems/ruzzy'
  s.license               = 'AGPL-3.0'
  s.extensions            = %w[ext/cruzzy/extconf.rb]
  s.required_ruby_version = '>= 3.1.0'

  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'rake-compiler', '~> 1.2'
  s.add_development_dependency 'rubocop', '~> 1.60'
end
