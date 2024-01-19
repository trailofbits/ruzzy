require "ruzzy"

dummy = lambda {|data| Ruzzy.c_dummy_test_one_input(data)}

Ruzzy.fuzz(dummy)
