# frozen_string_literal: true

require 'ruzzy'
require 'test/unit'

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
    omit("This test calls LLVMFuzzerRunDriver, which we don't have a good harness for yet")

    dummy_test_one_input = lambda do |data|
      Ruzzy.dummy_test_one_input(data)
      'not an integer or nil'
    end

    assert_raise(TypeError) do
      Ruzzy.fuzz(dummy_test_one_input)
    end
  end

  def test_fuzz_without_proc
    assert_raise(RuntimeError) do
      Ruzzy.fuzz('not a proc')
    end
  end

  def test_ext_path
    assert(Ruzzy.ext_path)
  end
end
