#!/bin/bash

LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy.ext_path')/asan_with_fuzzer.so \
    ruby bin/dummy.rb "$@"
