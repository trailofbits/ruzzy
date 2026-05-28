# frozen_string_literal: true

require 'pathname'
require 'ruzzy/fuzzed_data_provider'

# A coverage-guided fuzzer for pure Ruby code and Ruby C extensions
module Ruzzy
  require 'cruzzy/cruzzy'

  # libFuzzer features like -merge and -fork re-execute argv[0] via system().
  # RUZZY_ARGV0 allows a wrapper script (e.g. entrypoint.sh) to advertise its
  # own path as argv[0], so re-execution goes through the wrapper that sets
  # LD_PRELOAD and other required environment.
  ARGV0 = ENV.fetch('RUZZY_ARGV0', $PROGRAM_NAME)
  DEFAULT_ARGS = [ARGV0] + ARGV
  EXT_PATH = Pathname.new(__FILE__).parent.parent / 'ext' / 'cruzzy'
  DLEXT = RbConfig::CONFIG['host_os'] =~ /darwin/ ? 'dylib' : 'so'
  ASAN_PATH = (EXT_PATH / "asan_with_fuzzer.#{DLEXT}").to_s
  UBSAN_PATH = (EXT_PATH / "ubsan_with_fuzzer.#{DLEXT}").to_s

  def fuzz(test_one_input, args = DEFAULT_ARGS)
    # Include global hooks at runtime so we don't pollute non-fuzzing
    # functionality, e.g. test initialization.
    require 'ruzzy/hooks'

    c_fuzz(test_one_input, args)
  end

  def dummy_test_one_input(data)
    # This 'require' depends on LD_PRELOAD, so it's placed inside the function
    # scope. This allows us to access EXT_PATH for LD_PRELOAD and not have a
    # circular dependency.
    require 'dummy/dummy'

    c_dummy_test_one_input(data)
  end

  def dummy
    # Load the instrumented shared object before calling fuzz so its coverage
    # maps are registered before LLVMFuzzerRunDriver starts. Some fuzzer
    # runtimes (e.g. LibAFL) require coverage maps to exist upfront.
    require 'dummy/dummy'

    fuzz(->(data) { dummy_test_one_input(data) })
  end

  def trace(harness_script)
    # Include global hooks at runtime so we don't pollute non-fuzzing
    # functionality, e.g. test initialization.
    require 'ruzzy/hooks'

    harness_path = Pathname.new(harness_script)

    # Mimic require_relative. If harness script is provided as an absolute path,
    # then use that. If not, then assume the script is in the same directory as
    # as the tracer script, i.e. the caller.
    if !harness_path.absolute?
      caller_path = Pathname.new(caller_locations.first.path)
      harness_path = (caller_path.parent / harness_path).realpath
    end

    c_trace(harness_path.to_s)
  end

  module_function :fuzz
  module_function :dummy_test_one_input
  module_function :dummy
  module_function :trace
end
