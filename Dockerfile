FROM debian:12-slim

RUN apt update && apt install -y \
    binutils \
    gcc \
    g++ \
    libc-dev \
    make \
    ruby \
    ruby-dev \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV APP_DIR="/app"
ENV CLANG_DIR="$APP_DIR/clang"
RUN mkdir $APP_DIR
RUN mkdir $CLANG_DIR
WORKDIR $APP_DIR

ARG CLANG_ARCH=aarch64
ARG CLANG_URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-17.0.6/clang+llvm-17.0.6-aarch64-linux-gnu.tar.xz
ARG CLANG_CHECKSUM=6dd62762285326f223f40b8e4f2864b5c372de3f7de0731cb7cd55ca5287b75a

ENV CLANG_ARCH=${CLANG_ARCH}
ENV CLANG_URL=${CLANG_URL}
ENV CLANG_CHECKSUM=${CLANG_CHECKSUM}

ENV CLANG_FILE clang.tar.xz
RUN wget -q -O $CLANG_FILE $CLANG_URL && \
    echo "$CLANG_CHECKSUM  $CLANG_FILE" | sha256sum -c - && \
    tar xf $CLANG_FILE -C $CLANG_DIR --strip-components 1 && \
    rm $CLANG_FILE

ENV PATH="$PATH:$CLANG_DIR/bin"
ENV CC="clang"
ENV CXX="clang++"
ENV LDSHARED="clang -shared"
ENV LDSHAREDXX="clang++ -shared"

# The MAKE variable allows overwriting the make command at runtime. This forces the
# Ruby C extension to respect ENV variables when compiling, like CC, CFLAGS, etc.
ENV MAKE="make --environment-overrides V=1"

# 1. Skip memory allocation failures for now, they are common, and low impact (DoS)
# 2. The Ruby interpreter leaks data, so ignore these for now
# 3. Ruby recommends disabling sigaltstack: https://github.com/ruby/ruby/blob/master/doc/contributing/building_ruby.md#building-with-address-sanitizer
ENV ASAN_OPTIONS="allocator_may_return_null=1:detect_leaks=0:use_sigaltstack=0"

# Split dependency and application code installation for improved caching
COPY ruzzy.gemspec Gemfile ruzzy/
WORKDIR ruzzy/
RUN bundler3.1 install

COPY . .
RUN gem build
RUN RUZZY_DEBUG=1 gem install --verbose ruzzy-*.gem

ENTRYPOINT ["./entrypoint.sh"]
CMD ["-help=1"]
