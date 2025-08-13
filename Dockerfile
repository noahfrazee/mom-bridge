# Build stage (Linux ARM64)
FROM swift:5.10-jammy AS builder
WORKDIR /build
COPY Package.* ./
RUN swift package resolve
COPY Sources ./Sources
RUN swift build -c release

# Runtime stage
FROM ubuntu:22.04
WORKDIR /app
RUN apt-get update && apt-get install -y \
    libatomic1 libcurl4 libicu70 libxml2 ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/.build/release/mom-bridge /app/mom-bridge
ENV PORT=18080
ENTRYPOINT ["/app/mom-bridge"]
