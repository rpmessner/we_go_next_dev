#!/bin/sh
set -eu

mix zig.get
mix assets.deploy
