# frozen_string_literal: true

require 'ruzzy'

test_one_input = lambda do |data|
  if data.length == 4
    if data[0] == 'F'
      if data[1] == 'U'
        if data[2] == 'Z'
          if data[3] == 'Z'
            raise 'TEST HARNESS BRANCH'
          end
        end
      end
    end
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
