Gem::Specification.new do |s|
  s.name        = "ruzzy"
  s.version     = "0.5.0"
  s.summary     = "A Ruby C extension fuzzer"
  s.authors     = ["Trail of Bits"]
  s.email       = "support@trailofbits.com"
  s.files       = Dir["lib/**/*"]
  s.homepage    = "https://rubygems.org/gems/ruzzy"
  s.license     = "AGPL-3.0"
  s.extensions  = %w[ext/cruzzy/extconf.rb]

  s.add_runtime_dependency "rake", '~> 13.0'
  s.add_runtime_dependency "rake-compiler", '~> 1.2'
end
