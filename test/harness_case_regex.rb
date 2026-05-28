# frozen_string_literal: true

require 'ruzzy'

test_one_input = lambda do |data|
  case data
  when /FUZZREGEX-[0-9a-f]{2}/
    raise 'TEST HARNESS CASE REGEX'
  end
  0
end

Ruzzy.fuzz(
  test_one_input,
  [
    'ruzzytestprogname',
    '-max_total_time=30',
    "-exact_artifact_path=#{File::NULL}"
  ]
)
