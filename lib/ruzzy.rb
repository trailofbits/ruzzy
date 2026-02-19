# frozen_string_literal: true

require 'pathname'

# A coverage-guided fuzzer for pure Ruby code and Ruby C extensions
module Ruzzy
  require 'cruzzy/cruzzy'

  DEFAULT_ARGS = [$PROGRAM_NAME] + ARGV
  EXT_PATH = Pathname.new(__FILE__).parent.parent / 'ext' / 'cruzzy'
  ASAN_PATH = (EXT_PATH / 'asan_with_fuzzer.so').to_s
  UBSAN_PATH = (EXT_PATH / 'ubsan_with_fuzzer.so').to_s

  def fuzz(test_one_input, args = DEFAULT_ARGS)
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

# Hook Integer operations for tracing in SantizerCoverage
class Integer
  alias ruzzy_eeql ==
  alias ruzzy_eeeql ===
  alias ruzzy_eql? eql?
  alias ruzzy_spc <=>
  alias ruzzy_lt <
  alias ruzzy_le <=
  alias ruzzy_gt >
  alias ruzzy_ge >=
  alias ruzzy_divo /
  alias ruzzy_div div
  alias ruzzy_divmod divmod

  def ==(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_eeql(other)
  end

  def ===(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_eeeql(other)
  end

  def eql?(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_eql?(other)
  end

  def <=>(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_spc(other)
  end

  def <(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_lt(other)
  end

  def <=(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_le(other)
  end

  def >(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_gt(other)
  end

  def >=(other)
    Ruzzy.c_trace_cmp8(self, other)
    ruzzy_ge(other)
  end

  def /(other)
    Ruzzy.c_trace_div8(other)
    ruzzy_divo(other)
  end

  def div(other)
    Ruzzy.c_trace_div8(other)
    ruzzy_div(other)
  end

  def divmod(other)
    Ruzzy.c_trace_div8(other)
    ruzzy_divmod(other)
  end
end
