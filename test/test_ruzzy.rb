# frozen_string_literal: true

require 'English'
require 'tempfile'

require 'ruzzy'
require 'test/unit'

def fork_function(func)
  out_reader, out_writer = IO.pipe
  exc_reader, exc_writer = IO.pipe
  pid = fork

  if pid
    out_writer.close
    exc_writer.close
    output = out_reader.read
    exc_data = exc_reader.read
    Process.wait
    status = $CHILD_STATUS
    exception = exc_data.empty? ? nil : Marshal.load(exc_data)
    [output, status, exception]
  else
    out_reader.close
    exc_reader.close
    $stdout.reopen(out_writer)
    $stderr.reopen(out_writer)
    begin
      func.call
    rescue Exception => e
      # Convert backtrace_locations (Thread::Backtrace::Location objects
      # which aren't Marshal-able) to plain strings before dumping.
      e.set_backtrace(e.backtrace) if e.backtrace
      exc_writer.write(Marshal.dump(e))
    ensure
      exc_writer.close
      # Always skip at_exit handlers — Test::Unit's autorunner is inherited
      # via fork and would otherwise recursively re-run the queued tests in
      # this child, blowing up wall time exponentially.
      exit!
    end
  end
end

def run_fuzzer(test_one_input, args = ['ruzzytestprogname'], max_total_time = 30)
  output = nil
  status = nil
  exception = nil
  artifact = nil

  # Don't spin the test too long if something goes wrong
  args.append("-max_total_time=#{max_total_time}")

  Tempfile.create do |file|
    args.append("-exact_artifact_path=#{file.path}")
    func = proc { Ruzzy.fuzz(test_one_input, args) }
    output, status, exception = fork_function(func)
    artifact = file.read
  end

  [output, status, exception, artifact]
end

def run_tracer(tracer_script)
  # TODO: capture artifact output and return it for later assertions
  func = proc { Ruzzy.trace(tracer_script) }
  fork_function(func)
end

# Linux defaults to abort_on_error=0 while macOS is abort_on_error=1. Account
# for this discrepancy using this function. We could set abort_on_error=0 in
# ASAN_OPTIONS, but solving it here is easier than remembering to set an ENV
# variable everywhere.
def assert_status(status, expected_exitcode)
  exited_with_expected = status.exited? && status.exitstatus == expected_exitcode
  aborted = status.signaled? && status.termsig == Signal.list['ABRT']
  assert(
    exited_with_expected || aborted,
    "expected exit #{expected_exitcode} or SIGABRT, got #{status.inspect}"
  )
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

    _output, _status, exception, artifact = run_fuzzer(dummy_test_one_input)

    assert_kind_of(TypeError, exception)
    assert_match(/fuzz target function did not return an integer or nil/, exception.message)
    assert_empty(artifact)
  end

  def test_dummy_test_one_input_success
    dummy_test_one_input = ->(data) { Ruzzy.dummy_test_one_input(data) }

    output, status, _exception, artifact = run_fuzzer(dummy_test_one_input)

    # See dummy.c
    expected_artifact = 'HI'
    expected_output = 'ERROR: AddressSanitizer: heap-use-after-free'
    expected_status = 1

    assert_include(output, expected_output)
    assert_status(status, expected_status)
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
    _output, _status, exception = run_tracer('harness_branch.rb')

    assert_kind_of(RuntimeError, exception)
    assert_equal('TEST HARNESS BRANCH', exception.message)
  end

  def test_trace_cmp
    _output, _status, exception = run_tracer('harness_cmp.rb')

    assert_kind_of(RuntimeError, exception)
    assert_equal('TEST HARNESS CMP', exception.message)
  end

  def test_trace_div
    _output, _status, exception = run_tracer('harness_div.rb')

    assert_kind_of(RuntimeError, exception)
    assert_equal('TEST HARNESS DIV', exception.message)
  end

  def test_trace_case_string
    _output, _status, exception = run_tracer('harness_case_string.rb')

    assert_kind_of(RuntimeError, exception)
    assert_equal('TEST HARNESS CASE STRING', exception.message)
  end

  def test_trace_case_integer
    _output, _status, exception = run_tracer('harness_case_integer.rb')

    assert_kind_of(RuntimeError, exception)
    assert_equal('TEST HARNESS CASE INTEGER', exception.message)
  end

  def test_trace_case_regex
    _output, _status, exception = run_tracer('harness_case_regex.rb')

    assert_kind_of(RuntimeError, exception)
    assert_equal('TEST HARNESS CASE REGEX', exception.message)
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
