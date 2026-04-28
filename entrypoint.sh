#!/bin/bash

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy::ASAN_PATH') \
    RUZZY_ARGV0="$SCRIPT_PATH" ruby -e 'require "ruzzy"; Ruzzy.dummy' -- "$@"
