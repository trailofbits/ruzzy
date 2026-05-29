# frozen_string_literal: true

require 'ruzzy'

test_one_input = lambda do |data|
  case data
  when /(FUZZALT_FOO|FUZZALT_BAR)/
    raise 'TEST HARNESS CASE REGEX ALT'
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
