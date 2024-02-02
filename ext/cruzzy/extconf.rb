# frozen_string_literal: true

require 'mkmf'
require 'open3'
require 'tempfile'

# These ENV variables really shouldn't be used because we don't support
# compilers other than clang, like gcc, etc. Instead prefer to properly include
# clang in your PATH. But they're here if you really need them. Also note that
# *technically* Ruby does not support C extensions compiled with a different
# compiler than Ruby itself was compiled with. So we're on somewhat shaky
# ground here. For more information see:
# https://github.com/rubygems/rubygems/issues/1508
CC = ENV.fetch('CC', 'clang')
CXX = ENV.fetch('CXX', 'clang++')
FUZZER_NO_MAIN_LIB_ENV = 'FUZZER_NO_MAIN_LIB'

find_executable(CC)
find_executable(CXX)

def get_clang_file_name(file_name)
  puts("Searching for #{file_name} using #{CC}")
  stdout, status = Open3.capture2(CC, '--print-file-name', file_name)
  puts("Search command succeeded: #{status.success?}")
  puts("Search file exists: #{File.exist?(stdout.strip)}") if status.success?
  status.success? && File.exist?(stdout.strip) ? stdout.strip : false
end

def merge_asan_libfuzzer_lib(asan_lib, fuzzer_no_main_lib)
  merged_output = 'asan_with_fuzzer.so'

  # https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#why-this-is-necessary
  Tempfile.create do |file|
    file.write(File.open(asan_lib).read)

    puts("Creating ASAN archive at #{file.path}")
    _, status = Open3.capture2(
      'ar',
      'd',
      file.path,
      'asan_preinit.cc.o',
      'asan_preinit.cpp.o'
    )
    unless status.success?
      puts("The 'ar' archive command failed.")
      exit(1)
    end

    puts("Merging ASAN at #{file.path} and libFuzzer at #{fuzzer_no_main_lib} to #{merged_output}")
    _, status = Open3.capture2(
      CXX,
      '-Wl,--whole-archive',
      fuzzer_no_main_lib,
      file.path,
      '-Wl,--no-whole-archive',
      '-lpthread',
      '-ldl',
      '-shared',
      '-o',
      merged_output
    )
    unless status.success?
      puts("The 'clang' shared object merging command failed.")
      exit(1)
    end
  end
end

fuzzer_no_main_libs = [
  'libclang_rt.fuzzer_no_main.a',
  'libclang_rt.fuzzer_no_main-aarch64.a',
  'libclang_rt.fuzzer_no_main-x86_64.a'
]
fuzzer_no_main_lib = fuzzer_no_main_libs.map { |lib| get_clang_file_name(lib) }.find(&:itself)

unless fuzzer_no_main_lib
  puts("Could not find fuzzer_no_main using #{CC}.")
  fuzzer_no_main_lib = ENV.fetch(FUZZER_NO_MAIN_LIB_ENV, nil)
  if fuzzer_no_main_lib.nil?
    puts("Could not find fuzzer_no_main in #{FUZZER_NO_MAIN_LIB_ENV}.")
    puts("Please include #{CC} in your path or specify #{FUZZER_NO_MAIN_LIB_ENV} ENV variable.")
    exit(1)
  end
end

asan_libs = [
  'libclang_rt.asan.a',
  'libclang_rt.asan-aarch64.a',
  'libclang_rt.asan-x86_64.a'
]
asan_lib = asan_libs.map { |lib| get_clang_file_name(lib) }.find(&:itself)

unless asan_lib
  puts("Could not find asan using #{CC}.")
  exit(1)
end

merge_asan_libfuzzer_lib(asan_lib, fuzzer_no_main_lib)

# The LOCAL_LIBS variable allows linking arbitrary libraries into Ruby C
# extensions. It is supported by the Ruby mkmf library and C extension Makefile.
# For more information, see https://github.com/ruby/ruby/blob/master/lib/mkmf.rb.
$LOCAL_LIBS = fuzzer_no_main_lib

create_makefile('cruzzy/cruzzy')
