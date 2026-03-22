# Noosphere Browser - Multi-platform Build Container
FROM ubuntu:24.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Zig
ARG ZIG_VERSION=0.13.0
RUN curl -fsSL https://ziglang.org/builds/zig-linux-x86_64-${ZIG_VERSION}.tar.xz -o /tmp/zig.tar.xz \
    && tar -xf /tmp/zig.tar.xz -C /opt \
    && ln -s /opt/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig \
    && rm /tmp/zig.tar.xz

WORKDIR /app

# Copy source
COPY . .

# Build for all platforms
RUN make build-all

# Output
RUN ls -la release/

# Create installer
RUN mkdir -p release/installer && \
    cp install.sh release/ && \
    cp README.md release/ && \
    cp LICENSE release/ || true

FROM scratch
COPY --from=0 /app/release/* /noosphere/
COPY --from=0 /app/install.sh /noosphere/
ENTRYPOINT ["/noosphere/noosphere"]
