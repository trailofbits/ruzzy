# frozen_string_literal: true

require 'mkmf'
require 'open3'
require 'tempfile'
require 'rbconfig'
require 'logger'

LOGGER = Logger.new($stderr)
LOGGER.level = ENV.key?('RUZZY_DEBUG') ? Logger::DEBUG : Logger::INFO

HOST_OS = RbConfig::CONFIG['host_os']
MACOS = !!(HOST_OS =~ /darwin/)
DLEXT = MACOS ? 'dylib' : 'so'

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
LD = ENV.fetch('LD', MACOS ? '/usr/bin/ld' : 'ld')
FUZZER_NO_MAIN_LIB_ENV = 'FUZZER_NO_MAIN_LIB'

LOGGER.debug("Ruby OS: #{HOST_OS}")
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
  if MACOS
    # The same weak-symbol problem the Atheris doc below describes also occurs
    # on macOS: if only the bare sanitizer dylib is DYLD_INSERT_LIBRARIES'd,
    # its weak __sanitizer_cov_* stubs land in the global symbol table first,
    # and a later-loaded instrumented C extension's sancov UNDEFs bind to
    # those no-ops instead of libFuzzer's strong implementation. So macOS
    # needs the same merge concept — libFuzzer and the sanitizer in the same
    # preloaded image — even though the mechanics differ.
    #
    # The macOS sanitizer ships as a dylib (libclang_rt.asan_osx_dynamic.dylib),
    # not a static archive, so we can't ar-strip preinits or --whole-archive
    # merge. Instead, build a thin wrapper dylib that statically pulls in
    # libFuzzer via -force_load and lists the sanitizer dylib as a runtime
    # dependency. DYLD_INSERT_LIBRARIES of the wrapper auto-loads the
    # sanitizer dylib via dyld dep resolution, so both ASan's weak sancov
    # stubs and libFuzzer's strong sancov implementations enter the global
    # namespace at the same load step — strong wins, just like the Linux
    # merge guarantees.
    LOGGER.debug("Building macOS wrapper dylib at #{merged_output} (libFuzzer #{fuzzer_no_main_lib} + #{sanitizer_lib})")

    _, status = Open3.capture2(
      CXX,
      '-dynamiclib',
      "-Wl,-force_load,#{fuzzer_no_main_lib}",
      sanitizer_lib,
      '-lpthread',
      '-lc++',
      "-Wl,-install_name,@rpath/#{File.basename(merged_output)}",
      '-o',
      merged_output
    )
    unless status.success?
      LOGGER.error("The #{CXX} dylib build command failed.")
      exit(1)
    end
    return
  end

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
      '-lstdc++',
      '-shared',
      "-fuse-ld=#{LD}",
      '-o',
      merged_output
    )
    unless status.success?
      LOGGER.error("The #{CXX} shared object merging command failed.")
      exit(1)
    end
  end
end

fuzzer_no_main_lib = ENV.fetch(FUZZER_NO_MAIN_LIB_ENV, nil)

if fuzzer_no_main_lib
  LOGGER.info("Using #{FUZZER_NO_MAIN_LIB_ENV}=#{fuzzer_no_main_lib}")
  unless File.exist?(fuzzer_no_main_lib)
    LOGGER.error("#{FUZZER_NO_MAIN_LIB_ENV} file does not exist: #{fuzzer_no_main_lib}")
    exit(1)
  end
else
  fuzzer_no_main_libs = [
    'libclang_rt.fuzzer_no_main.a',
    'libclang_rt.fuzzer_no_main-aarch64.a',
    'libclang_rt.fuzzer_no_main-x86_64.a',
    'libclang_rt.fuzzer_no_main_osx.a'
  ]
  fuzzer_no_main_lib = fuzzer_no_main_libs.map { |lib| get_clang_file_name(lib) }.find(&:itself)

  unless fuzzer_no_main_lib
    LOGGER.error("Could not find fuzzer_no_main using #{CC}.")
    LOGGER.error("Please include #{CC} in your path or specify #{FUZZER_NO_MAIN_LIB_ENV} ENV variable.")
    exit(1)
  end
end

asan_libs = [
  'libclang_rt.asan.a',
  'libclang_rt.asan-aarch64.a',
  'libclang_rt.asan-x86_64.a',
  'libclang_rt.asan_osx_dynamic.dylib'
]
asan_lib = asan_libs.map { |lib| get_clang_file_name(lib) }.find(&:itself)

unless asan_lib
  LOGGER.error("Could not find asan using #{CC}.")
  exit(1)
end

merge_sanitizer_libfuzzer_lib(
  asan_lib,
  fuzzer_no_main_lib,
  "asan_with_fuzzer.#{DLEXT}",
  'asan_preinit.cc.o',
  'asan_preinit.cpp.o'
)

ubsan_libs = [
  'libclang_rt.ubsan_standalone.a',
  'libclang_rt.ubsan_standalone-aarch64.a',
  'libclang_rt.ubsan_standalone-x86_64.a',
  'libclang_rt.ubsan_osx_dynamic.dylib'
]
ubsan_lib = ubsan_libs.map { |lib| get_clang_file_name(lib) }.find(&:itself)

unless ubsan_lib
  LOGGER.error("Could not find ubsan using #{CC}.")
  exit(1)
end

merge_sanitizer_libfuzzer_lib(
  ubsan_lib,
  fuzzer_no_main_lib,
  "ubsan_with_fuzzer.#{DLEXT}",
  'ubsan_init_standalone_preinit.cc.o',
  'ubsan_init_standalone_preinit.cpp.o'
)

# The LOCAL_LIBS variable allows linking arbitrary libraries into Ruby C
# extensions. It is supported by the Ruby mkmf library and C extension Makefile.
# For more information, see https://github.com/ruby/ruby/blob/master/lib/mkmf.rb.
#
# On macOS we deliberately skip statically linking libFuzzer into cruzzy.bundle.
# Doing so would produce two libFuzzer instances in the process at runtime:
# one inside cruzzy.bundle (statically linked), one inside the
# DYLD_INSERT_LIBRARIES'd asan_with_fuzzer.dylib (force_load'd in the merge
# step). cruzzy's call to LLVMFuzzerRunDriver is a direct branch to its local
# copy because macOS's ld64 emits non-preemptible calls to symbols it
# resolves at link time. Meanwhile a sancov-instrumented C extension loaded
# later (e.g. dummy.bundle) has its sancov refs as flat-namespace UNDEFs
# that dyld resolves at runtime, picking the wrapper's strong symbols.
# Result: the fuzz driver and the instrumented code register with different
# libFuzzer instances that share no state, so libFuzzer sees no coverage
# feedback (corpus stays at 1 entry, "Is the code instrumented for
# coverage?" warning).
#
# Linux is unaffected because ELF shared objects default to semantic
# interposition: cruzzy.so's call to LLVMFuzzerRunDriver goes through the
# PLT and resolves to whichever copy is first in the global symbol table,
# i.e. the LD_PRELOAD'd asan_with_fuzzer.so. Both copies converge on the
# preloaded instance, so the duplicate is harmless.
#
# With macOS's mkmf default of `-undefined dynamic_lookup`, leaving
# $LOCAL_LIBS unset lets cruzzy.bundle ship with UNDEF refs to
# LLVMFuzzerRunDriver and __sanitizer_cov_*. These resolve at runtime to
# the single libFuzzer instance in the preloaded wrapper.
$LOCAL_LIBS = fuzzer_no_main_lib unless MACOS

$LIBS << ' -lstdc++'
$DLDFLAGS << " -fuse-ld=#{LD}"

create_makefile('cruzzy/cruzzy')
