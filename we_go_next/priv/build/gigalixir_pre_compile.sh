#!/bin/sh
set -eu

zig_version="0.15.2"
zig_root=".platform_tools/zig"
zig_executable="${zig_root}/zig"

if [ ! -x "${zig_executable}" ]; then
  archive="/tmp/zig-${zig_version}.tar.xz"

  curl -fsSL \
    "https://ziglang.org/download/${zig_version}/zig-x86_64-linux-${zig_version}.tar.xz" \
    -o "${archive}"
  mkdir -p "${zig_root}"
  tar -xJf "${archive}" -C "${zig_root}" --strip-components=1
fi

ln -sf "$(pwd)/${zig_executable}" .platform_tools/elixir/bin/zig
mix assets.deploy
