# frozen_string_literal: true

require 'pathname'

# A Ruby C extension fuzzer
module Ruzzy
  require 'cruzzy/cruzzy'

  DEFAULT_ARGS = [$PROGRAM_NAME] + ARGV
  EXT_PATH = Pathname.new(__FILE__).parent.parent / 'ext' / 'cruzzy'
  ASAN_PATH = (EXT_PATH / 'asan_with_fuzzer.so').to_s

  def fuzz(test_one_input, args = DEFAULT_ARGS)
    c_fuzz(test_one_input, args)
  end

  def dummy
    fuzz(->(data) { Ruzzy.dummy_test_one_input(data) })
  end

  def dummy_test_one_input(data)
    # This 'require' depends on LD_PRELOAD, so it's placed inside the function
    # scope. This allows us to access EXT_PATH for LD_PRELOAD and not have a
    # circular dependency.
    require 'dummy/dummy'

    c_dummy_test_one_input(data)
  end

  module_function :fuzz
  module_function :dummy
  module_function :dummy_test_one_input
end
