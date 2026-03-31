# frozen_string_literal: true

require 'ruzzy/fuzzed_data_provider'
require 'test/unit'

class FuzzedDataProviderTest < Test::Unit::TestCase
  # --- Determinism ---

  def test_deterministic_output
    data = (0..255).to_a.pack('C*')
    fdp1 = Ruzzy::FuzzedDataProvider.new(data)
    fdp2 = Ruzzy::FuzzedDataProvider.new(data)

    assert_equal fdp1.consume_int_in_range(0, 1000), fdp2.consume_int_in_range(0, 1000)
    assert_equal fdp1.consume_bytes(10), fdp2.consume_bytes(10)
    assert_equal fdp1.consume_bool, fdp2.consume_bool
  end

  # --- Remaining bytes ---

  def test_remaining_bytes_initial
    fdp = Ruzzy::FuzzedDataProvider.new("\x01\x02\x03\x04")
    assert_equal 4, fdp.remaining_bytes
  end

  def test_remaining_bytes_decreases_from_front
    fdp = Ruzzy::FuzzedDataProvider.new("\x01\x02\x03\x04")
    fdp.consume_bytes(2)
    assert_equal 2, fdp.remaining_bytes
  end

  def test_remaining_bytes_decreases_from_back
    fdp = Ruzzy::FuzzedDataProvider.new("\x01\x02\x03\x04")
    fdp.consume_int_in_range(0, 255)
    assert_equal 3, fdp.remaining_bytes
  end

  def test_remaining_bytes_both_directions
    fdp = Ruzzy::FuzzedDataProvider.new("\x01\x02\x03\x04\x05\x06")
    fdp.consume_bytes(2)          # front: 2 consumed
    fdp.consume_int_in_range(0, 255) # back: 1 consumed
    assert_equal 3, fdp.remaining_bytes
  end

  # --- Empty data behavior ---

  def test_empty_data_consume_bytes
    fdp = Ruzzy::FuzzedDataProvider.new('')
    assert_equal '', fdp.consume_bytes(10)
  end

  def test_empty_data_consume_int
    fdp = Ruzzy::FuzzedDataProvider.new('')
    assert_equal 0, fdp.consume_int(4)
  end

  def test_empty_data_consume_uint
    fdp = Ruzzy::FuzzedDataProvider.new('')
    assert_equal 0, fdp.consume_uint(4)
  end

  def test_empty_data_consume_int_in_range
    fdp = Ruzzy::FuzzedDataProvider.new('')
    assert_equal 5, fdp.consume_int_in_range(5, 100)
  end

  def test_empty_data_consume_bool
    fdp = Ruzzy::FuzzedDataProvider.new('')
    assert_equal false, fdp.consume_bool
  end

  def test_empty_data_consume_probability
    fdp = Ruzzy::FuzzedDataProvider.new('')
    assert_in_delta 0.0, fdp.consume_probability, 1e-15
  end

  def test_empty_data_consume_float_in_range
    fdp = Ruzzy::FuzzedDataProvider.new('')
    assert_in_delta 1.0, fdp.consume_float_in_range(1.0, 10.0), 1e-15
  end

  # --- consume_bytes ---

  def test_consume_bytes_exact
    fdp = Ruzzy::FuzzedDataProvider.new("\x41\x42\x43")
    assert_equal "\x41\x42", fdp.consume_bytes(2)
    assert_equal 1, fdp.remaining_bytes
  end

  def test_consume_bytes_more_than_available
    fdp = Ruzzy::FuzzedDataProvider.new("\x41\x42")
    result = fdp.consume_bytes(100)
    assert_equal "\x41\x42", result
    assert_equal 0, fdp.remaining_bytes
  end

  def test_consume_bytes_zero
    fdp = Ruzzy::FuzzedDataProvider.new("\x41\x42")
    assert_equal '', fdp.consume_bytes(0)
    assert_equal 2, fdp.remaining_bytes
  end

  def test_consume_bytes_binary_encoding
    fdp = Ruzzy::FuzzedDataProvider.new("\x41\x42")
    result = fdp.consume_bytes(2)
    assert_equal Encoding::BINARY, result.encoding
  end

  # --- consume_uint / consume_int (from end) ---

  def test_consume_uint_one_byte
    fdp = Ruzzy::FuzzedDataProvider.new("\xAA\xFF")
    # Consumes from the end: byte 0xFF
    assert_equal 0xFF, fdp.consume_uint(1)
    assert_equal 1, fdp.remaining_bytes
  end

  def test_consume_uint_two_bytes
    fdp = Ruzzy::FuzzedDataProvider.new("\xAA\x01\x02")
    # Consumes from end: bytes [0x01, 0x02] → little-endian
    # First byte consumed (back-1): 0x02, shift 0
    # Second byte consumed (back-2): 0x01, shift 8
    result = fdp.consume_uint(2)
    assert_equal 0x0102, result
    assert_equal 1, fdp.remaining_bytes
  end

  def test_consume_int_positive
    fdp = Ruzzy::FuzzedDataProvider.new("\x00\x7F")
    result = fdp.consume_int(1)
    assert_equal 0x7F, result
  end

  def test_consume_int_negative
    fdp = Ruzzy::FuzzedDataProvider.new("\x00\xFF")
    result = fdp.consume_int(1)
    assert_equal(-1, result)
  end

  def test_consume_int_negative_two_bytes
    fdp = Ruzzy::FuzzedDataProvider.new("\x00\x00\xFF\x00")
    result = fdp.consume_int(2)
    assert_equal(-256, result)
  end

  def test_consume_uint_zero_bytes
    fdp = Ruzzy::FuzzedDataProvider.new("\x41\x42")
    assert_equal 0, fdp.consume_uint(0)
    assert_equal 2, fdp.remaining_bytes
  end

  # --- consume_int_in_range (from end) ---

  def test_int_in_range_single_value
    fdp = Ruzzy::FuzzedDataProvider.new("\x41\x42\x43")
    # No bytes consumed when min == max
    assert_equal 42, fdp.consume_int_in_range(42, 42)
    assert_equal 3, fdp.remaining_bytes
  end

  def test_int_in_range_stays_in_bounds
    1000.times do |i|
      data = [i % 256, (i * 7) % 256, (i * 13) % 256, (i * 31) % 256].pack('C*')
      fdp = Ruzzy::FuzzedDataProvider.new(data)
      result = fdp.consume_int_in_range(10, 99)
      assert result >= 10, "Expected >= 10, got #{result}"
      assert result <= 99, "Expected <= 99, got #{result}"
    end
  end

  def test_int_in_range_negative_range
    fdp = Ruzzy::FuzzedDataProvider.new("\xFF")
    result = fdp.consume_int_in_range(-100, -50)
    assert result >= -100
    assert result <= -50
  end

  def test_int_in_range_covers_full_range
    # With all 256 possible single-byte inputs, every value in a small range
    # should be reachable
    seen = Array.new(10, false)
    256.times do |byte|
      fdp = Ruzzy::FuzzedDataProvider.new([byte].pack('C'))
      result = fdp.consume_int_in_range(0, 9)
      seen[result] = true
    end
    seen.each_with_index do |covered, i|
      assert covered, "Value #{i} was never generated in range 0..9"
    end
  end

  def test_int_in_range_raises_on_invalid
    fdp = Ruzzy::FuzzedDataProvider.new("\x01\x02")
    assert_raise(ArgumentError) { fdp.consume_int_in_range(10, 5) }
  end

  # --- Bidirectional consumption ---

  def test_bidirectional_independence
    # Bytes consumed from front and back should not interfere
    data = "\x41\x42\x43\x44\x0A\x0B"

    # Consume string from front, then int from back
    fdp1 = Ruzzy::FuzzedDataProvider.new(data)
    str1 = fdp1.consume_bytes(2)
    int1 = fdp1.consume_uint(2)

    # The string should be the first 2 bytes
    assert_equal "\x41\x42", str1
    # The int should be from the last 2 bytes
    assert_equal 0x0A0B, int1
  end

  def test_front_and_back_meet
    fdp = Ruzzy::FuzzedDataProvider.new("\x01\x02\x03\x04")
    fdp.consume_bytes(2)          # front eats 2
    fdp.consume_uint(2)           # back eats 2
    assert_equal 0, fdp.remaining_bytes
    assert_equal '', fdp.consume_bytes(1)
    assert_equal 0, fdp.consume_uint(1)
  end

  # --- consume_bool ---

  def test_consume_bool_true
    fdp = Ruzzy::FuzzedDataProvider.new("\x01")
    assert_equal true, fdp.consume_bool
  end

  def test_consume_bool_false
    fdp = Ruzzy::FuzzedDataProvider.new("\x02")
    assert_equal false, fdp.consume_bool
  end

  def test_consume_bool_odd_is_true
    fdp = Ruzzy::FuzzedDataProvider.new("\xFF")
    assert_equal true, fdp.consume_bool
  end

  # --- consume_probability ---

  def test_consume_probability_range
    100.times do |i|
      data = ([i * 2] * 8).pack('C*')
      fdp = Ruzzy::FuzzedDataProvider.new(data)
      prob = fdp.consume_probability
      assert prob >= 0.0, "Probability #{prob} < 0.0"
      assert prob <= 1.0, "Probability #{prob} > 1.0"
    end
  end

  def test_consume_probability_zero_data
    fdp = Ruzzy::FuzzedDataProvider.new("\x00" * 8)
    assert_in_delta 0.0, fdp.consume_probability, 1e-15
  end

  def test_consume_probability_max_data
    fdp = Ruzzy::FuzzedDataProvider.new("\xFF" * 8)
    assert_in_delta 1.0, fdp.consume_probability, 1e-15
  end

  # --- consume_float_in_range ---

  def test_float_in_range_stays_in_bounds
    100.times do |i|
      data = ([i, i * 3, i * 7, i * 13, i * 17, i * 23, i * 29, i * 31].map { |x| x % 256 }).pack('C*')
      fdp = Ruzzy::FuzzedDataProvider.new(data)
      result = fdp.consume_float_in_range(-100.0, 100.0)
      assert result >= -100.0, "Float #{result} < -100.0"
      assert result <= 100.0, "Float #{result} > 100.0"
    end
  end

  def test_float_in_range_single_value
    fdp = Ruzzy::FuzzedDataProvider.new("\x01\x02\x03\x04")
    assert_in_delta 3.14, fdp.consume_float_in_range(3.14, 3.14), 1e-15
  end

  def test_float_in_range_raises_on_invalid
    fdp = Ruzzy::FuzzedDataProvider.new("\x01\x02")
    assert_raise(ArgumentError) { fdp.consume_float_in_range(10.0, 5.0) }
  end

  def test_float_in_range_overflow
    # Test that -MAX..MAX doesn't crash (range overflows to Infinity)
    fdp = Ruzzy::FuzzedDataProvider.new("\x01" * 20)
    result = fdp.consume_float_in_range(-Float::MAX, Float::MAX)
    assert result.is_a?(Float)
    refute result.nan?
  end

  # --- consume_float ---

  def test_consume_float_returns_float
    fdp = Ruzzy::FuzzedDataProvider.new("\x01" * 20)
    result = fdp.consume_float
    assert result.is_a?(Float)
  end

  # --- pick_value_in_list ---

  def test_pick_value_in_list_stays_in_list
    choices = %w[alpha beta gamma delta]
    100.times do |i|
      fdp = Ruzzy::FuzzedDataProvider.new([i].pack('C'))
      result = fdp.pick_value_in_list(choices)
      assert_include choices, result
    end
  end

  def test_pick_value_in_list_single_element
    fdp = Ruzzy::FuzzedDataProvider.new("\xFF")
    assert_equal 'only', fdp.pick_value_in_list(['only'])
  end

  def test_pick_value_in_list_empty_raises
    fdp = Ruzzy::FuzzedDataProvider.new("\x01")
    assert_raise(ArgumentError) { fdp.pick_value_in_list([]) }
  end

  # --- consume_random_length_string ---

  def test_random_length_string_terminates_on_escape
    # \x5C = backslash, \x41 = 'A' (non-backslash, terminates)
    fdp = Ruzzy::FuzzedDataProvider.new("hello\x5C\x41world")
    result = fdp.consume_random_length_string
    assert_equal 'hello', result
  end

  def test_random_length_string_double_backslash_continues
    # \x5C\x5C = escaped backslash, should continue
    fdp = Ruzzy::FuzzedDataProvider.new("ab\x5C\x5Ccd")
    result = fdp.consume_random_length_string
    assert_equal "ab\\cd", result
  end

  def test_random_length_string_respects_max_length
    fdp = Ruzzy::FuzzedDataProvider.new('abcdefghij')
    result = fdp.consume_random_length_string(3)
    assert result.length <= 3
  end

  # --- consume_remaining_bytes ---

  def test_consume_remaining_bytes
    fdp = Ruzzy::FuzzedDataProvider.new("\x01\x02\x03\x04\x05")
    fdp.consume_bytes(2)
    fdp.consume_uint(1)
    remaining = fdp.consume_remaining_bytes
    assert_equal 2, remaining.bytesize
    assert_equal 0, fdp.remaining_bytes
  end

  # --- Data isolation ---

  def test_original_data_not_mutated
    original = "\x01\x02\x03\x04"
    frozen_copy = original.dup.freeze
    fdp = Ruzzy::FuzzedDataProvider.new(original)
    fdp.consume_bytes(4)
    assert_equal frozen_copy, original
  end
end
