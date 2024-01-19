FROM debian:12-slim

RUN apt update && apt install -y \
    binutils \
    gcc \
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

ARG CLANG_URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-17.0.6/clang+llvm-17.0.6-aarch64-linux-gnu.tar.xz
ARG CLANG_CHECKSUM=6dd62762285326f223f40b8e4f2864b5c372de3f7de0731cb7cd55ca5287b75a

ENV CLANG_FILE clang.tar.xz
RUN wget -q -O $CLANG_FILE $CLANG_URL && \
    echo "$CLANG_CHECKSUM  $CLANG_FILE" | sha256sum -c - && \
    tar xf $CLANG_FILE -C $CLANG_DIR --strip-components 1 && \
    rm $CLANG_FILE

ENV CC "$CLANG_DIR/bin/clang"
ENV CFLAGS "-fsanitize=address,undefined,fuzzer-no-link -fPIC -g"
ENV CXX "$CLANG_DIR/bin/clang++"
ENV CXXFLAGS "-fsanitize=address,undefined,fuzzer-no-link -fPIC -g"
ENV LDSHARED "$CLANG_DIR/bin/clang -shared"
ENV LDSHAREDXX "$CLANG_DIR/bin/clang++ -shared"
ENV ASAN_SYMBOLIZER_PATH "$CLANG_DIR/bin/llvm-symbolizer"

# This variable is supported by the Ruby "mkmf" library and C extension Makefile
ENV LOCAL_LIBS "/app/clang/lib/clang/17/lib/aarch64-unknown-linux-gnu/libclang_rt.fuzzer_no_main.a"

# Respect ENV variables when compiling C extension, like LOCAL_LIBS above
ENV MAKE "make --environment-overrides V=1"

# The Ruby interpreter leaks data, so ignore these for now
ENV ASAN_OPTIONS "detect_leaks=0"

COPY . ruzzy/
WORKDIR ruzzy/
RUN gem build ruzzy.gemspec
RUN gem install ruzzy-*.gem
RUN rake clean
RUN rake compile

ENV LD_PRELOAD "/app/clang/lib/clang/17/lib/aarch64-unknown-linux-gnu/libclang_rt.asan.so"

ENTRYPOINT ["ruby", "bin/dummy.rb"]
CMD ["-help=1"]
