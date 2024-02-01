# frozen_string_literal: true

require 'mkmf'
require 'open3'
require 'tempfile'

CLANG = 'clang'
FUZZER_NO_MAIN_LIB = 'FUZZER_NO_MAIN_LIB'

find_executable(CLANG)

def get_clang_file_name(file_name)
  stdout, status = Open3.capture2(CLANG, '--print-file-name', file_name)
  status.success? && File.exist?(stdout.strip) ? stdout.strip : false
end

def merge_asan_libfuzzer_lib(asan_lib, fuzzer_no_main_lib)
  # https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#why-this-is-necessary
  Tempfile.create do |file|
    file.write(File.open(asan_lib).read)

    stdout, status = Open3.capture2(
      'ar',
      'd',
      file.path,
      'asan_preinit.cc.o',
      'asan_preinit.cpp.o'
    )

    stdout, status = Open3.capture2(
      ENV['CXX'],
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
  end
end

fuzzer_no_main_libs = [
  'libclang_rt.fuzzer_no_main.a',
  'libclang_rt.fuzzer_no_main-aarch64.a',
  'libclang_rt.fuzzer_no_main-x86_64.a'
]
fuzzer_no_main_lib = fuzzer_no_main_libs.map { |lib| get_clang_file_name(lib) }.find(&:itself)

unless fuzzer_no_main_lib
  puts("Could not find fuzzer_no_main using #{CLANG}.")
  fuzzer_no_main_lib = ENV.fetch(FUZZER_NO_MAIN_LIB, nil)
  if fuzzer_no_main_lib.nil?
    puts("Could not find fuzzer_no_main in #{FUZZER_NO_MAIN_LIB}.")
    puts("Please include #{CLANG} in your path or specify #{FUZZER_NO_MAIN_LIB} ENV variable.")
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
  puts("Could not find asan using #{CLANG}.")
  exit(1)
end

merge_asan_libfuzzer_lib(asan_lib, fuzzer_no_main_lib)

create_makefile('cruzzy/cruzzy')
