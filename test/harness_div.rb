# frozen_string_literal: true

require 'ruzzy'

test_one_input = lambda do |data|
  begin
    100 / data.unpack1('H*').to_i(16)
  rescue ZeroDivisionError
    raise 'TEST HARNESS DIV'
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
