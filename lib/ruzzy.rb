# frozen_string_literal: true

require 'pathname'

# A Ruby C extension fuzzer
module Ruzzy
  require 'cruzzy/cruzzy'

  DEFAULT_ARGS = [$PROGRAM_NAME] + ARGV

  def fuzz(test_one_input, args = DEFAULT_ARGS)
    c_fuzz(test_one_input, args)
  end

  def dummy
    fuzz(->(data) { Ruzzy.dummy_test_one_input(data) } )
  end

  def ext_path
    (Pathname.new(__FILE__).parent.parent + 'ext' + 'cruzzy').to_s
  end

  def dummy_test_one_input(data)
    # This 'require' depends on LD_PRELOAD, so it's placed inside the function
    # scope. This allows us to run ext_path for LD_PRELOAD and not have a
    # circular dependency.
    require 'dummy/dummy'

    c_dummy_test_one_input(data)
  end

  module_function :fuzz
  module_function :dummy
  module_function :ext_path
  module_function :dummy_test_one_input
end
