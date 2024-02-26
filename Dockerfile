FROM ubuntu:jammy

RUN apt update && apt install -y \
    build-essential \
    gnupg \
    lsb-release \
    ruby \
    ruby-dev \
    software-properties-common \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://apt.llvm.org/llvm.sh && chmod +x llvm.sh
RUN ./llvm.sh 18

ENV APP_DIR="/app"
RUN mkdir $APP_DIR
WORKDIR $APP_DIR

ENV CC="clang-18"
ENV CXX="clang++-18"
ENV LDSHARED="clang-18 -shared"
ENV LDSHAREDXX="clang++-18 -shared"

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
