# frozen_string_literal: true

require 'mkmf'
require 'open3'

lib_name = 'libclang_rt.fuzzer_no_main.a'
env_name = 'FUZZER_NO_MAIN_LIB'
clang_name = 'clang'

lib_path, status = Open3.capture2(clang_name, "--print-file-name", lib_name)

if !status.success?
  puts("Could not find #{lib_name} using #{clang_name}.")
  lib_path = ENV.fetch(env_name, nil)
  if lib_path.nil?
    puts("Could not find #{lib_name} in #{env_name}.")
    puts("Please include #{clang_name} in your path or specify #{env_name} ENV variable.")
    exit(1)
  end
end

# The LOCAL_LIBS variable allows linking arbitrary libraries into Ruby C
# extensions. It is supported by the Ruby mkmf library and C extension Makefile.
# For more information, see https://github.com/ruby/ruby/blob/master/lib/mkmf.rb.
$LOCAL_LIBS = lib_path

create_makefile('cruzzy/cruzzy')
