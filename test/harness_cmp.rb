# frozen_string_literal: true

require 'ruzzy'

test_one_input = lambda do |data|
  if data.unpack1('H*').to_i(16) == 'FUZZ'.unpack1('H*').to_i(16)
    raise 'TEST HARNESS CMP'
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
