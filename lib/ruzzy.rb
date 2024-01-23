module Ruzzy
  require "cruzzy/cruzzy"

  # $0 is the program name
  DEFAULT_ARGS = [$0] + ARGV

  def fuzz(test_one_input, args = DEFAULT_ARGS)
    self.c_fuzz(test_one_input, args)
  end

  module_function :fuzz
end
