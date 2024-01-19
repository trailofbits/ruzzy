require "ruzzy"
require "test/unit"

class RuzzyTest < Test::Unit::TestCase
  def test_c_libfuzzer_is_loaded
    result = Ruzzy.c_libfuzzer_is_loaded()

    assert_true(result)
  end

  def test_c_dummy_test_one_input
    dummy = Proc.new {|data| Ruzzy.c_dummy_test_one_input(data)}

    result = dummy.call("test")
    expected = 0

    assert_equal(result, expected)
  end

  def test_fuzz_without_proc
    assert_raise(RuntimeError) do
      Ruzzy.fuzz("not a proc")
    end
  end
end
