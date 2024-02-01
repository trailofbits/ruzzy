# frozen_string_literal: true

require 'mkmf'

# https://github.com/google/sanitizers/wiki/AddressSanitizerFlags
$CFLAGS = '-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g'
$CXXFLAGS = '-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g'

create_makefile('dummy/dummy')
