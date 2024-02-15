# frozen_string_literal: true

require 'English'
require 'tempfile'

require 'ruzzy'
require 'test/unit'

LIBFUZZER_DEFAULT_SUCCESS_EXITCODE = 1
LIBFUZZER_DEFAULT_TIMEOUT_EXITCODE = 70
LIBFUZZER_DEFAULT_ERROR_EXITCODE = 77

# There must be many lines of code between the assertions checking these
# constant strings and their definition. Since the tests are asserting on
# tracebacks, these strings would otherwise be included in the traceback,
# which may cause false positives in the tests. This is obviously not ideal,
# but I can't think of a better and easier solution right now.
EXPECTED_OUTPUT_RETURN = 'TypeError: fuzz target function did not return an integer or nil'
EXPECTED_OUTPUT_SUCCESS = 'ERROR: AddressSanitizer: stack-use-after-return'
EXPECTED_OUTPUT_BRANCH = 'RuntimeError: TEST HARNESS BRANCH'
EXPECTED_OUTPUT_CMP = 'RuntimeError: TEST HARNESS CMP'
EXPECTED_OUTPUT_DIV = 'RuntimeError: TEST HARNESS DIV'

def fork_function(func)
  reader, writer = IO.pipe
  output = nil
  pid = fork

  if pid
    writer.close
    output = reader.read
    Process.wait
    child_status = $CHILD_STATUS
  else
    reader.close
    $stdout.reopen(writer)
    $stderr.reopen(writer)
    func.call
    exit!
  end

  [output, child_status]
end

def run_fuzzer(test_one_input, args = ['ruzzytestprogname'], max_total_time = 30)
  output = nil
  status = nil
  artifact = nil

  # Don't spin the test too long if something goes wrong
  args.append("-max_total_time=#{max_total_time}")

  Tempfile.create do |file|
    args.append("-exact_artifact_path=#{file.path}")
    func = proc { Ruzzy.fuzz(test_one_input, args) }
    output, status = fork_function(func)
    artifact = file.read
  end

  [output, status, artifact]
end

def run_tracer(tracer_script)
  # TODO: capture artifact output and return it for later assertions
  func = proc { Ruzzy.trace(tracer_script) }
  fork_function(func)
end

class RuzzyTest < Test::Unit::TestCase
  def test_c_libfuzzer_is_loaded
    result = Ruzzy.c_libfuzzer_is_loaded

    assert_true(result)
  end

  def test_dummy_test_one_input_proc
    dummy_test_one_input = proc { |data| Ruzzy.dummy_test_one_input(data) }

    result = dummy_test_one_input.call('test')
    expected = 0

    assert_equal(result, expected)
  end

  def test_dummy_test_one_input_lambda
    dummy_test_one_input = ->(data) { Ruzzy.dummy_test_one_input(data) }

    result = dummy_test_one_input.call('test')
    expected = 0

    assert_equal(result, expected)
  end

  def test_dummy_test_one_input_invalid_return
    dummy_test_one_input = lambda do |data|
      Ruzzy.dummy_test_one_input(data)
      'not an integer or nil'
    end

    output, status, artifact = run_fuzzer(dummy_test_one_input)

    assert_include(output, EXPECTED_OUTPUT_RETURN)
    assert_equal(status.exitstatus, LIBFUZZER_DEFAULT_ERROR_EXITCODE)
    assert_empty(artifact)
  end

  def test_dummy_test_one_input_success
    dummy_test_one_input = ->(data) { Ruzzy.dummy_test_one_input(data) }

    output, status, artifact = run_fuzzer(dummy_test_one_input)

    # See dummy.c
    expected_artifact = 'HI'

    assert_include(output, EXPECTED_OUTPUT_SUCCESS)
    assert_equal(status.exitstatus, LIBFUZZER_DEFAULT_SUCCESS_EXITCODE)
    assert_equal(artifact, expected_artifact)
  end

  def test_fuzz_without_proc
    assert_raise(RuntimeError) do
      Ruzzy.fuzz('not a proc')
    end
  end

  def test_fuzz_without_args
    dummy_test_one_input = ->(data) { Ruzzy.dummy_test_one_input(data) }

    assert_raise(RuntimeError) do
      Ruzzy.fuzz(dummy_test_one_input, [])
    end
  end

  def test_fuzz_with_too_many_args
    dummy_test_one_input = ->(data) { Ruzzy.dummy_test_one_input(data) }

    assert_raise(RuntimeError) do
      Ruzzy.fuzz(dummy_test_one_input, Array.new(128, 'test'))
    end
  end

  def test_trace_branch
    output, status = run_tracer('harness_branch.rb')

    assert_include(output, EXPECTED_OUTPUT_BRANCH)
    assert_equal(status.exitstatus, LIBFUZZER_DEFAULT_ERROR_EXITCODE)
  end

  def test_trace_cmp
    output, status = run_tracer('harness_cmp.rb')

    assert_include(output, EXPECTED_OUTPUT_CMP)
    assert_equal(status.exitstatus, LIBFUZZER_DEFAULT_ERROR_EXITCODE)
  end

  def test_trace_div
    output, status = run_tracer('harness_div.rb')

    assert_include(output, EXPECTED_OUTPUT_DIV)
    assert_equal(status.exitstatus, LIBFUZZER_DEFAULT_ERROR_EXITCODE)
  end

  def test_ext_path
    assert(Ruzzy::EXT_PATH)
  end

  def test_asan_path
    assert(Ruzzy::ASAN_PATH)
  end

  def test_ubsan_path
    assert(Ruzzy::UBSAN_PATH)
  end
end
