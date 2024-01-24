#!/bin/bash

export LD_PRELOAD=${ASAN_MERGED_LIB}

ruby -Ilib bin/dummy.rb "$@"
