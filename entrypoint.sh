#!/bin/bash

LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy::ASAN_PATH') \
    ruby bin/dummy.rb "$@"
