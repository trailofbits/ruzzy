# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name                  = 'ruzzy'
  s.version               = '0.7.0'
  s.summary               = 'A coverage-guided fuzzer for pure Ruby code and Ruby C extensions'
  s.authors               = ['Trail of Bits']
  s.email                 = 'support@trailofbits.com'
  s.files                 = Dir['lib/**/*.rb'] + Dir['ext/**/*.{rb,c,h}']
  s.homepage              = 'https://rubygems.org/gems/ruzzy'
  s.license               = 'AGPL-3.0-only'
  s.extensions            = %w[ext/cruzzy/extconf.rb ext/dummy/extconf.rb]
  s.required_ruby_version = '>= 3.0.0'

  s.add_development_dependency 'rake', '~> 13.0'
  s.add_development_dependency 'rake-compiler', '~> 1.2'
  s.add_development_dependency 'rake-release', '~> 1.3'
  s.add_development_dependency 'rubocop', '~> 1.60'
end
