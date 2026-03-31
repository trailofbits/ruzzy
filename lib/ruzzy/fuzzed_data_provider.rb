# frozen_string_literal: true

module Ruzzy
  # Splits raw fuzzer bytes into typed Ruby values.
  #
  # FuzzedDataProvider wraps a binary string (typically from libFuzzer via
  # Ruzzy.fuzz) and provides methods to consume typed values from it. This
  # enables fuzz targets that test APIs accepting typed arguments rather than
  # raw byte strings.
  #
  # Following libFuzzer's FuzzedDataProvider.h design, strings and raw bytes
  # are consumed from the *front* of the buffer, while integers are consumed
  # from the *end*. This bidirectional consumption lets the fuzzer modify
  # structural decisions (integers controlling lengths, indices, variant
  # selection) independently from content (string payloads, raw bytes),
  # improving mutation quality.
  #
  # @example Basic usage in a fuzz target
  #   test_one_input = lambda do |data|
  #     fdp = Ruzzy::FuzzedDataProvider.new(data)
  #     name = fdp.consume_random_length_string(50)
  #     age = fdp.consume_int_in_range(0, 150)
  #     score = fdp.consume_float_in_range(0.0, 100.0)
  #     role = fdp.pick_value_in_list(['admin', 'user', 'guest'])
  #     User.new(name: name, age: age, score: score, role: role).validate!
  #   end
  #   Ruzzy.fuzz(test_one_input)
  class FuzzedDataProvider
    def initialize(data)
      @data = data
      # Front cursor for strings/bytes (advances forward)
      @front = 0
      # Back cursor for integers (advances backward)
      @back = @data.bytesize
    end

    # Returns the number of unconsumed bytes remaining.
    def remaining_bytes
      @back - @front
    end

    # --- Byte and String methods (consume from front) ---

    # Consume up to +count+ raw bytes from the front of the buffer.
    # Returns a binary-encoded String.
    def consume_bytes(count)
      count = clamp_count(count)
      result = @data.byteslice(@front, count)
      @front += count
      result.force_encoding(Encoding::BINARY)
    end

    # Consume a variable-length string from the front of the buffer.
    # The string terminates when a backslash followed by a non-backslash
    # byte is encountered, or when +max_length+ characters are consumed.
    # This encoding lets the fuzzer easily control string length through
    # single-byte mutations.
    #
    # Matches libFuzzer's ConsumeRandomLengthString.
    def consume_random_length_string(max_length = remaining_bytes)
      result = +''
      max_length.times do
        break if remaining_bytes.zero?

        byte = consume_front_byte
        char = byte.chr(Encoding::BINARY)

        if char == '\\' && remaining_bytes.positive?
          next_byte = consume_front_byte
          next_char = next_byte.chr(Encoding::BINARY)
          break if next_char != '\\'

          result << '\\'
        else
          result << char
        end
      end
      result
    end

    # Consume all remaining bytes. Returns a binary-encoded String.
    def consume_remaining_bytes
      consume_bytes(remaining_bytes)
    end

    # Consume all remaining bytes as a String.
    def consume_remaining_as_string
      consume_remaining_bytes
    end

    # --- Integer methods (consume from end) ---

    # Consume an unsigned integer from the end of the buffer.
    # Reads up to +count+ bytes in little-endian order from the back.
    # Returns 0 when no data remains.
    def consume_uint(count)
      return 0 if count <= 0 || remaining_bytes.zero?

      actual = [count, remaining_bytes].min
      result = 0
      actual.times do |i|
        @back -= 1
        result |= @data.getbyte(@back) << (i * 8)
      end
      result
    end

    # Consume a signed integer from the end of the buffer.
    # Reads +count+ bytes and interprets as two's complement.
    # Returns 0 when no data remains.
    def consume_int(count)
      unsigned = consume_uint(count)
      return 0 if count.zero?

      bits = count * 8
      max_unsigned = 1 << bits
      half = max_unsigned >> 1

      unsigned >= half ? unsigned - max_unsigned : unsigned
    end

    # Consume an integer in [min, max] from the end of the buffer.
    # Returns +min+ when no data remains.
    # Raises ArgumentError if min > max.
    #
    # Matches libFuzzer's ConsumeIntegralInRange: consumes only as many
    # bytes from the end as needed to cover the range.
    def consume_int_in_range(min, max)
      raise ArgumentError, "min (#{min}) must be <= max (#{max})" if min > max

      range = max - min
      return min if range.zero?

      # Consume bytes from the end, one at a time, until we've covered the range.
      # This matches libFuzzer: only consume bytes while (range >> offset) > 0.
      result = 0
      offset = 0
      while offset < 64 && (range >> offset).positive? && remaining_bytes.positive?
        @back -= 1
        result = (result << 8) | @data.getbyte(@back)
        offset += 8
      end

      if range == (1 << offset) - 1
        # range+1 is a power of 2, modulo is identity
        min + result
      else
        min + (result % (range + 1))
      end
    end

    # Consume a boolean from the end of the buffer.
    # Returns false when no data remains.
    def consume_bool
      (consume_uint(1) & 1) == 1
    end

    # --- Float methods (consume from end) ---

    # Consume a Float in [0.0, 1.0] from the end of the buffer.
    # Returns 0.0 when no data remains.
    def consume_probability
      raw = consume_uint(8)
      raw.to_f / 18_446_744_073_709_551_615.0 # 2^64 - 1
    end

    # Consume a Float in [min, max] from the end of the buffer.
    # Returns +min+ when no data remains.
    # Raises ArgumentError if min > max.
    def consume_float_in_range(min, max)
      raise ArgumentError, 'min must be <= max' if min > max
      return min if min == max

      range = max - min
      if range.infinite?
        # Overflow: split the range and recurse
        mid = min / 2.0 + max / 2.0
        if consume_bool
          consume_float_in_range(mid, max)
        else
          consume_float_in_range(min, mid)
        end
      else
        min + range * consume_probability
      end
    end

    # Consume a Float spanning the full double range.
    # Matches libFuzzer's ConsumeFloatingPoint.
    def consume_float
      consume_float_in_range(-Float::MAX, Float::MAX)
    end

    # --- Selection methods ---

    # Return a random element from +list+, consuming bytes from the end.
    # Raises ArgumentError if the list is empty.
    def pick_value_in_list(list)
      raise ArgumentError, 'list must not be empty' if list.empty?

      list[consume_int_in_range(0, list.length - 1)]
    end

    private

    # Consume a single byte from the front.
    def consume_front_byte
      return 0 if remaining_bytes.zero?

      byte = @data.getbyte(@front)
      @front += 1
      byte
    end

    def clamp_count(count)
      count = 0 if count.negative?
      count = remaining_bytes if count > remaining_bytes
      count
    end
  end
end
