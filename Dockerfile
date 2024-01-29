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

ENV APP_DIR "/app"
ENV CLANG_DIR "$APP_DIR/clang"
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

# https://github.com/google/sanitizers/wiki/AddressSanitizerFlags
ENV CC "$CLANG_DIR/bin/clang"
ENV CFLAGS "-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g -O0"
ENV CXX "$CLANG_DIR/bin/clang++"
ENV CXXFLAGS "-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer -fno-common -fPIC -g -O0"
ENV LDSHARED "$CLANG_DIR/bin/clang -shared"
ENV LDSHAREDXX "$CLANG_DIR/bin/clang++ -shared"
ENV ASAN_SYMBOLIZER_PATH "$CLANG_DIR/bin/llvm-symbolizer"

ENV FUZZER_NO_MAIN_LIB "$CLANG_DIR/lib/clang/17/lib/$CLANG_ARCH-unknown-linux-gnu/libclang_rt.fuzzer_no_main.a"
ENV ASAN_LIB "$CLANG_DIR/lib/clang/17/lib/$CLANG_ARCH-unknown-linux-gnu/libclang_rt.asan.a"
ENV ASAN_STRIPPED_LIB "/tmp/libclang_rt.asan.a"
ENV ASAN_MERGED_LIB "/tmp/asan_with_fuzzer.so"

# https://github.com/google/atheris/blob/master/native_extension_fuzzing.md#why-this-is-necessary
RUN cp "$ASAN_LIB" "$ASAN_STRIPPED_LIB"
RUN ar d "$ASAN_STRIPPED_LIB" asan_preinit.cc.o asan_preinit.cpp.o
RUN "$CXX" \
    -Wl,--whole-archive \
    "$FUZZER_NO_MAIN_LIB" \
    "$ASAN_STRIPPED_LIB" \
    -Wl,--no-whole-archive \
    -lpthread -ldl -shared \
    -o "$ASAN_MERGED_LIB"

# The LOCAL_LIBS variable allows linking arbitrary libraries into Ruby C
# extensions. It is supported by the Ruby mkmf library and C extension Makefile.
# For more information, see https://github.com/ruby/ruby/blob/master/lib/mkmf.rb.
ENV LOCAL_LIBS=${FUZZER_NO_MAIN_LIB}

# The MAKE variable allows overwriting the make command at runtime. This forces the
# Ruby C extension to respect ENV variables when compiling, like LOCAL_LIBS above.
ENV MAKE "make --environment-overrides V=1"

# 1. Skip memory allocation failures for now, they are common, and low impact (DoS)
# 2. The Ruby interpreter leaks data, so ignore these for now
ENV ASAN_OPTIONS "allocator_may_return_null=1:detect_leaks=0:use_sigaltstack=0"

# Split dependency and application code installation for improved caching
COPY ruzzy.gemspec Gemfile ruzzy/
WORKDIR ruzzy/
RUN bundler3.1 install

COPY . .
RUN rake compile

ENTRYPOINT ["./entrypoint.sh"]
CMD ["-help=1"]
