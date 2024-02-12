# frozen_string_literal: true

require 'mkmf'
require 'open3'
require 'tempfile'
require 'rbconfig'
require 'logger'

LOGGER = Logger.new($stderr)
LOGGER.level = ENV.key?('RUZZY_DEBUG') ? Logger::DEBUG : Logger::INFO

# These ENV variables really shouldn't be used because we don't support
# compilers other than clang, like gcc, etc. Instead prefer to properly include
# clang in your PATH. But they're here if you really need them. Also note that
# *technically* Ruby does not support C extensions compiled with a different
# compiler than Ruby itself was compiled with. So we're on somewhat shaky
# ground here. For more information see:
# https://github.com/rubygems/rubygems/issues/1508
CC = ENV.fetch('CC', 'clang')
CXX = ENV.fetch('CXX', 'clang++')
AR = ENV.fetch('AR', 'ar')
FUZZER_NO_MAIN_LIB_ENV = 'FUZZER_NO_MAIN_LIB'

LOGGER.debug("Ruby CC: #{RbConfig::CONFIG['CC']}")
LOGGER.debug("Ruby CXX: #{RbConfig::CONFIG['CXX']}")
LOGGER.debug("Ruby AR: #{RbConfig::CONFIG['AR']}")

find_executable(CC)
find_executable(CXX)

def get_clang_file_name(file_name)
  stdout, status = Open3.capture2(CC, '--print-file-name', file_name)
  success = status.success?
  exists = success ? File.exist?(stdout.strip) : false
  LOGGER.debug("Search for #{file_name} using #{CC}: success=#{success} exists=#{exists}")
  success && exists ? stdout.strip : false
end

def merge_sanitizer_libfuzzer_lib(sanitizer_lib, fuzzer_no_main_lib, merged_output, *preinits)
  # https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#why-this-is-necessary
  Tempfile.create do |file|
    LOGGER.debug("Creating #{sanitizer_lib} sanitizer archive at #{file.path}")

    file.write(File.open(sanitizer_lib).read)

    _, status = Open3.capture2(
      AR,
      'd',
      file.path,
      *preinits
    )
    unless status.success?
      LOGGER.error("The #{AR} archive command failed.")
      exit(1)
    end

    LOGGER.debug("Merging sanitizer at #{file.path} with libFuzzer at #{fuzzer_no_main_lib} to #{merged_output}")

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
      LOGGER.error("The #{CXX} shared object merging command failed.")
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
  LOGGER.warn("Could not find fuzzer_no_main using #{CC}.")
  fuzzer_no_main_lib = ENV.fetch(FUZZER_NO_MAIN_LIB_ENV, nil)
  if fuzzer_no_main_lib.nil?
    LOGGER.error("Could not find fuzzer_no_main in #{FUZZER_NO_MAIN_LIB_ENV}.")
    LOGGER.error("Please include #{CC} in your path or specify #{FUZZER_NO_MAIN_LIB_ENV} ENV variable.")
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
  LOGGER.error("Could not find asan using #{CC}.")
  exit(1)
end

merge_sanitizer_libfuzzer_lib(
  asan_lib,
  fuzzer_no_main_lib,
  'asan_with_fuzzer.so',
  'asan_preinit.cc.o',
  'asan_preinit.cpp.o'
)

ubsan_libs = [
  'libclang_rt.ubsan_standalone.a',
  'libclang_rt.ubsan_standalone-aarch64.a',
  'libclang_rt.ubsan_standalone-x86_64.a'
]
ubsan_lib = ubsan_libs.map { |lib| get_clang_file_name(lib) }.find(&:itself)

unless ubsan_lib
  LOGGER.error("Could not find ubsan using #{CC}.")
  exit(1)
end

merge_sanitizer_libfuzzer_lib(
  ubsan_lib,
  fuzzer_no_main_lib,
  'ubsan_with_fuzzer.so',
  'ubsan_init_standalone_preinit.cc.o',
  'ubsan_init_standalone_preinit.cpp.o'
)

# The LOCAL_LIBS variable allows linking arbitrary libraries into Ruby C
# extensions. It is supported by the Ruby mkmf library and C extension Makefile.
# For more information, see https://github.com/ruby/ruby/blob/master/lib/mkmf.rb.
$LOCAL_LIBS = fuzzer_no_main_lib

create_makefile('cruzzy/cruzzy')
