# frozen_string_literal: true

# A Ruby C extension fuzzer
module Ruzzy
  require 'cruzzy/cruzzy'
  require 'cruzzy/dummy/dummy'

  DEFAULT_ARGS = [$PROGRAM_NAME] + ARGV

  def fuzz(test_one_input, args = DEFAULT_ARGS)
    c_fuzz(test_one_input, args)
  end

  module_function :fuzz
end
