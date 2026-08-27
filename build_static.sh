#!/bin/bash
set -e

docker run --rm --privileged \
  multiarch/qemu-user-static \
  --reset -p yes

# The static builds must not drag in host-native shards, so they reinstall
# dependencies inside the container. shard.lock is committed now, so it
# stays in place and pins the dependency versions for reproducibility.
# Only the host-built lib/ tree is cleared.

# Build for AMD64
docker build . -f Dockerfile.static -t hace-builder
docker run -i --rm -v "$PWD":/app --user="$UID" hace-builder /bin/sh -c "cd /app && rm -rf lib && shards install --without-development && shards build --release --without-development --static"
mv bin/hace bin/hace-static-linux-amd64

# Build for ARM64
docker build . -f Dockerfile.static --platform linux/arm64 -t hace-builder-arm64
docker run -i --rm -v "$PWD":/app --platform linux/arm64 --user="$UID" hace-builder-arm64 /bin/sh -c "cd /app && rm -rf lib && shards install --without-development && shards build --release --without-development --static"
mv bin/hace bin/hace-static-linux-arm64
