# Ruzzy

A Ruby C extension fuzzer.

Ruzzy is based on Google's [Atheris](https://github.com/google/atheris), a Python fuzzer. Unlike Atheris, Ruzzy is focused on fuzzing Ruby C extensions and not Ruby code itself. This may change in the future as the project gains traction.

# Building

Ruzzy relies on Docker for both development and production fuzzer usage.

You can build the Ruzzy Docker image with the following command:

```bash
docker build --tag ruzzy .
```

_You may want to grab a cup of coffee, the initial build can take a while._

# Using

## Getting started

Ruzzy includes a [toy example](https://llvm.org/docs/LibFuzzer.html#toy-example) to demonstrate how it works.

You can run the example with the following command:

```bash
$ docker run -v $(pwd):/tmp/output/ ruzzy -artifact_prefix=/tmp/output/
INFO: Running with entropic power schedule (0xFF, 100).
INFO: Seed: 1250491632
...
==2==ABORTING
MS: 1 CopyPart-; base unit: 253420c1158bc6382093d409ce2e9cff5806e980
0x48,0x49,0x48,0x49,
HIHI
artifact_prefix='/tmp/output/'; Test unit written to /tmp/output/crash-53551f97ce4b956f4bfcdeec9eb8d01b5d5533a7
Base64: SElISQ==
```

This should produce a crash relatively quickly. We can inspect the crash with the following command:

```bash
$ xxd crash-53551f97ce4b956f4bfcdeec9eb8d01b5d5533a7
00000000: 4849 4849                                HIHI
```

The Docker volume and `-artifact_prefix` flag will persist any crashes within the container into the host's filesystem. This highlights one of Ruzzy's features: flags passed to the Docker container are then [sent to libFuzzer](https://llvm.org/docs/LibFuzzer.html#options). You can use this functionality to re-run crash files:

```bash
$ docker run -v $(pwd):/tmp/output/ ruzzy /tmp/output/crash-53551f97ce4b956f4bfcdeec9eb8d01b5d5533a7
INFO: Running with entropic power schedule (0xFF, 100).
INFO: Seed: 1672214264
...
Running: /tmp/output/crash-53551f97ce4b956f4bfcdeec9eb8d01b5d5533a7
...
Executed /tmp/output/crash-53551f97ce4b956f4bfcdeec9eb8d01b5d5533a7 in 2 ms
***
*** NOTE: fuzzing was not performed, you have only
***       executed the target code on a fixed set of inputs.
***
```

You can also use this functionality to pass in a fuzzing corpus:

```bash
docker run -v $(pwd)/corpus:/tmp/corpus -v $(pwd):/tmp/output/ ruzzy /tmp/corpus
```

## Fuzzing third-party libraries

There are two primary ways you may want to fuzz third-party libraries: 1) modify the `Dockerfile` and `entrypoint.sh` script, and/or 2) shell into a Ruzzy container. This section will focus on (2).

You can get a shell in the Ruzzy environment with the following command:

```bash
docker run -it -v $(pwd):/app/ruzzy --entrypoint /bin/bash ruzzy
```

Let's fuzz the [`msgpack-ruby`](https://github.com/msgpack/msgpack-ruby) library as an example. First, install the gem:

```bash
gem install --verbose msgpack
```

Next, we need a fuzzing target for `msgpack`.

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
LD_PRELOAD=${ASAN_MERGED_LIB} ruby -Ilib fuzz_msgpack.rb
```

_`LD_PRELOAD` is required for the same reasons [as Atheris](https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#option-a-sanitizerlibfuzzer-preloads)._

# Developing

Development is done primarily within the Docker container.

First, shell into the container using the `docker run ... --entrypoint` command above.

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
  - https://ruby-doc.org/3.3.0/stdlibs/mkmf/MakeMakefile.html
  - https://github.com/flavorjones/ruby-c-extensions-explained
  - https://github.com/ruby/ruby/blob/v3_1_2/lib/mkmf.rb
- Atheris
  - https://github.com/google/atheris/blob/master/native_extension_fuzzing.md
  - https://security.googleblog.com/2020/12/how-atheris-python-fuzzer-works.html
  - https://github.com/google/atheris/blob/2.3.0/setup.py
  - https://github.com/google/atheris/blob/2.3.0/src/native/core.cc
