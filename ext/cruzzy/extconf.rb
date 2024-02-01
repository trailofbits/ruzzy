# frozen_string_literal: true

require 'mkmf'
require 'open3'
require 'tempfile'

CC = 'clang'
CXX = 'clang++'
FUZZER_NO_MAIN_LIB_ENV = 'FUZZER_NO_MAIN_LIB'

find_executable(CC)

def get_clang_file_name(file_name)
  stdout, status = Open3.capture2(CC, '--print-file-name', file_name)
  status.success? && File.exist?(stdout.strip) ? stdout.strip : false
end

def merge_asan_libfuzzer_lib(asan_lib, fuzzer_no_main_lib)
  # https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#why-this-is-necessary
  Tempfile.create do |file|
    file.write(File.open(asan_lib).read)

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
      'asan_with_fuzzer.so'
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

# The LOCAL_LIBS variable allows linking arbitrary libraries into Ruby C
# extensions. It is supported by the Ruby mkmf library and C extension Makefile.
# For more information, see https://github.com/ruby/ruby/blob/master/lib/mkmf.rb.
$LOCAL_LIBS = fuzzer_no_main_lib

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

create_makefile('cruzzy/cruzzy')
