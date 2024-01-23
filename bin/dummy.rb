require "ruzzy"

dummy_test_one_input = lambda {|data| Ruzzy.c_dummy_test_one_input(data)}

Ruzzy.fuzz(dummy_test_one_input)
