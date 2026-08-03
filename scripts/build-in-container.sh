#!/usr/bin/env sh
# Build wrq for one Linux target inside a container.
#
# The build runs as a native build inside a target-arch container. This avoids
# cross-compiling LuaJIT and OpenSSL. On Apple Silicon, linux/arm64 runs at
# native speed. linux/amd64 runs under QEMU emulation (slower, but fine).
#
# Usage: build-in-container.sh <platform> <output-name>
#   platform     Docker platform string, e.g. linux/amd64 or linux/arm64
#   output-name  Artifact name written into dist/, e.g. wrq-linux-amd64
#
# Overrides:
#   CONTAINER_ENGINE  Container CLI to use (default: docker)
#   BUILD_IMAGE       Base image to build in (default: debian:bookworm)
set -eu

platform="${1:?usage: build-in-container.sh <platform> <output-name>}"
outname="${2:?usage: build-in-container.sh <platform> <output-name>}"

engine="${CONTAINER_ENGINE:-docker}"
image="${BUILD_IMAGE:-debian:bookworm}"

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$repo_root/dist"

echo "==> building $outname for $platform in $image"

# The source tree is mounted read-only and copied into the container's own
# filesystem. That keeps the host's obj/ and deps/luajit artifacts untouched
# and lets `make clean` reset any host-arch LuaJIT build we copied in.
"$engine" run --rm \
	--platform "$platform" \
	-v "$repo_root":/src:ro \
	-v "$repo_root/dist":/dist \
	"$image" \
	sh -euc '
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq
		apt-get install -y -qq build-essential libssl-dev zlib1g-dev >/dev/null
		mkdir -p /build
		tar -C /src -cf - --exclude=.git --exclude=obj --exclude=dist . \
			| tar -C /build -xf -
		cd /build
		make clean >/dev/null 2>&1 || true
		make
		cp wrq "/dist/'"$outname"'"
	'

echo "==> wrote dist/$outname"
