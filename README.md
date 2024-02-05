# Ruzzy

A Ruby C extension fuzzer.

Ruzzy is based on Google's [Atheris](https://github.com/google/atheris), a Python fuzzer. Unlike Atheris, Ruzzy is focused on fuzzing Ruby C extensions and not Ruby code itself. This may change in the future as the project gains traction.

# Installing

Ruzzy requires a recent version of `clang`, preferably the [latest release](https://github.com/llvm/llvm-project/releases).

Install Ruzzy with the following command:

```bash
MAKE="make --environment-overrides V=1" \
CC="/path/to/clang" \
CXX="/path/to/clang++" \
LDSHARED="/path/to/clang -shared" \
LDSHAREDXX="/path/to/clang++ -shared" \
    gem install ruzzy
```

There's a lot going on here, so let's break it down:

- The `MAKE` environment variable overrides the `make` command when compiling the Ruzzy C extension. This tells `make` to respect subsequent environment variables when compiling the extension.
- The rest of the environment variables are used during compilation to ensure we're using the proper `clang` binaries. This ensures we have the latest `clang` features, which are necessary for proper fuzzing.

If you run into issues installing, then you can run the following command to get debugging output:

```bash
RUZZY_DEBUG=1 gem install --verbose ruzzy
```

# Using

## Getting started

Ruzzy includes a [toy example](https://llvm.org/docs/LibFuzzer.html#toy-example) to demonstrate how it works.

First, we need to set the following environment variable:

```bash
export ASAN_OPTIONS="allocator_may_return_null=1:detect_leaks=0:use_sigaltstack=0"
```

<details>
<summary>Understanding these options isn't necessary, but if you're curious click here.</summary>

### `ASAN_OPTIONS`

1. Memory allocation failures are common and low impact (DoS), so skip them for now.
1. Like Python, the Ruby interpreter [leaks data](https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#leak-detection), so ignore these for now.
1. Ruby recommends [disabling sigaltstack](https://github.com/ruby/ruby/blob/master/doc/contributing/building_ruby.md#building-with-address-sanitizer).

</details>

You can then run the example with the following command:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy.ext_path')/asan_with_fuzzer.so \
    ruby -e 'require "ruzzy"; Ruzzy.dummy'
```

_`LD_PRELOAD` is required for the same reasons [as Atheris](https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#option-a-sanitizerlibfuzzer-preloads). However, unlike `ASAN_OPTIONS`, you probably do not want to `export` it as it may interfere with other programs._

It should quickly produce a crash like the following:

```
INFO: Running with entropic power schedule (0xFF, 100).
INFO: Seed: 2527961537
==3==ERROR: AddressSanitizer: stack-use-after-return on address 0xffffa8000920 at pc 0xffffa96a1a58 bp 0xfffff04ddbb0 sp 0xfffff04ddba8
...
SUMMARY: AddressSanitizer: stack-use-after-return /var/lib/gems/3.1.0/gems/ruzzy-0.5.0/ext/dummy/dummy.c:18:24 in _c_dummy_test_one_input
...
==3==ABORTING
MS: 1 InsertByte-; base unit: 253420c1158bc6382093d409ce2e9cff5806e980
0x48,0x49,0x28,
HI(
artifact_prefix='./'; Test unit written to ./crash-7099f1508d4048cfe74226869805efa3db24b165
Base64: SEko
```

You can re-run the crash case with the following command:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy.ext_path')/asan_with_fuzzer.so \
    ruby -e 'require "ruzzy"; Ruzzy.dummy' \
    ./crash-7099f1508d4048cfe74226869805efa3db24b165
```

## Fuzzing third-party libraries

Let's fuzz the [`msgpack-ruby`](https://github.com/msgpack/msgpack-ruby) library as an example. First, install the gem:

```bash
MAKE="make --environment-overrides V=1" \
CC="/path/to/clang" \
CXX="/path/to/clang++" \
LDSHARED="/path/to/clang -shared" \
LDSHAREDXX="/path/to/clang++ -shared" \
CFLAGS="-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g" \
CXXFLAGS="-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g" \
    gem install msgpack
```

In addition to the environment variables used when compiling Ruzzy, we're specifying `CFLAGS` and `CXXFLAGS`. These flags aid in the fuzzing process. They enable helpful functionality like an address sanitizer, and improved stack trace information. For more information see [AddressSanitizerFlags](https://github.com/google/sanitizers/wiki/AddressSanitizerFlags).

Next, we need a fuzzing harness for `msgpack`.

The following is a basic example that should be familiar to those with [libFuzzer experience](https://llvm.org/docs/LibFuzzer.html#fuzz-target):

```ruby
# frozen_string_literal: true

require 'msgpack'
require 'ruzzy'

test_one_input = lambda do |data|
  begin
    MessagePack.unpack(data)
  rescue Exception
    # We're looking for memory corruption, not Ruby exceptions
  end
  return 0
end

Ruzzy.fuzz(test_one_input)
```

Let's call this file `fuzz_msgpack.rb`.

You can run this file and start fuzzing with the following command:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy.ext_path')/asan_with_fuzzer.so \
    ruby fuzz_msgpack.rb
```

libFuzzer options can be passed to the Ruby script like so:

```bash
LD_PRELOAD=$(ruby -e 'require "ruzzy"; print Ruzzy.ext_path')/asan_with_fuzzer.so \
    ruby fuzz_msgpack.rb /path/to/corpus
```

See [libFuzzer options](https://llvm.org/docs/LibFuzzer.html#options) for more information.

# Developing

Development can be done locally, or using the `Dockerfile` provided in this repository.

You can build the Ruzzy Docker image with the following command:

```bash
docker build --tag ruzzy .
```

_You may want to grab a cup of coffee, the initial build can take a while._

By default, this will build a Docker image for AArch64 architectures (e.g. M-series MacBooks). If you need to run Ruzzy on other architectures, like x86, you can use the following [build arguments](https://docs.docker.com/build/guide/build-args/):

```
docker build \
    --build-arg CLANG_ARCH=x86_64 \
    --build-arg CLANG_URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-17.0.6/clang+llvm-17.0.6-x86_64-linux-gnu-ubuntu-22.04.tar.xz \
    --build-arg CLANG_CHECKSUM=884ee67d647d77e58740c1e645649e29ae9e8a6fe87c1376be0f3a30f3cc9ab3 \
    --tag ruzzy \
    .
```

Then, you can shell into the container using the following command:

```
docker run -it -v $(pwd):/app/ruzzy --entrypoint /bin/bash ruzzy
```

## Testing

We use `rake` unit tests to test Ruby code.

You can run the tests within the container with the following command:

```bash
rake test
```

## Linting

We use `rubocop` to lint Ruby code.

You can run `rubocop` within the container with the following command:

```bash
rubocop
```

# Recommended reading

- Ruby C extensions
  - https://guides.rubygems.org/gems-with-extensions/
  - https://www.rubyguides.com/2018/03/write-ruby-c-extension/
  - https://rubyreferences.github.io/rubyref/advanced/extensions.html
  - https://silverhammermba.github.io/emberb/c/
  - https://ruby-doc.org/3.3.0/stdlibs/mkmf/MakeMakefile.html
  - https://github.com/flavorjones/ruby-c-extensions-explained
  - https://github.com/ruby/ruby/blob/v3_1_2/lib/mkmf.rb
- Ruby fuzzing
  - https://github.com/twistlock/kisaten
  - https://github.com/richo/afl-ruby
  - https://z2-2z.github.io/2024/jan/16/fuzzing-ruby-c-extensions-with-coverage-and-asan.html
  - https://bsidessf2018.sched.com/event/E6jC/fuzzing-ruby-and-c-extensions
- Atheris
  - https://github.com/google/atheris/blob/master/native_extension_fuzzing.md
  - https://security.googleblog.com/2020/12/how-atheris-python-fuzzer-works.html
  - https://github.com/google/atheris/blob/2.3.0/setup.py
  - https://github.com/google/atheris/blob/2.3.0/src/native/core.cc
