module Ruzzy
  require "cruzzy/cruzzy"

  def fuzz(test_one_input)
    args = [$0] + ARGV
    self.c_fuzz(args, test_one_input)
  end

  module_function :fuzz
end
