# frozen_string_literal: true

require 'mkmf'

$CFLAGS = '-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g'
$CXXFLAGS = '-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g'

create_makefile('cruzzy/cruzzy/dummy')
