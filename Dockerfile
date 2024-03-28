# https://hub.docker.com/_/ruby
ARG RUBY_VERSION=3.3

FROM ruby:$RUBY_VERSION-slim-bookworm

RUN apt update && apt install -y \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# LLVM builds version 15-18 for Debian 12 (Bookworm)
# https://apt.llvm.org/bookworm/dists/
ARG LLVM_VERSION=18

RUN echo "deb http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-$LLVM_VERSION main" > /etc/apt/sources.list.d/llvm.list
RUN echo "deb-src http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-$LLVM_VERSION main" >> /etc/apt/sources.list.d/llvm.list
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key > /etc/apt/trusted.gpg.d/apt.llvm.org.asc

RUN apt update && apt install -y \
    build-essential \
    clang-$LLVM_VERSION \
    && rm -rf /var/lib/apt/lists/*

ENV APP_DIR="/app"
RUN mkdir $APP_DIR
WORKDIR $APP_DIR

ENV CC="clang-$LLVM_VERSION"
ENV CXX="clang++-$LLVM_VERSION"
ENV LDSHARED="clang-$LLVM_VERSION -shared"
ENV LDSHAREDXX="clang++-$LLVM_VERSION -shared"
ENV ASAN_SYMBOLIZER_PATH="/usr/bin/llvm-symbolizer-$LLVM_VERSION"

# The MAKE variable allows overwriting the make command at runtime. This forces the
# Ruby C extension to respect ENV variables when compiling, like CC, CFLAGS, etc.
ENV MAKE="make --environment-overrides V=1"

# 1. Skip memory allocation failures for now, they are common, and low impact (DoS)
# 2. The Ruby interpreter leaks data, so ignore these for now
# 3. Ruby recommends disabling sigaltstack: https://github.com/ruby/ruby/blob/master/doc/contributing/building_ruby.md#building-with-address-sanitizer
ENV ASAN_OPTIONS="allocator_may_return_null=1:detect_leaks=0:use_sigaltstack=0"

WORKDIR ruzzy/
COPY . .
RUN gem build
RUN RUZZY_DEBUG=1 gem install --development --verbose ruzzy-*.gem

ENTRYPOINT ["./entrypoint.sh"]
CMD ["-help=1"]
