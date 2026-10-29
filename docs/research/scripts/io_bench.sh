#!/usr/bin/env bash
# Raw sequential read throughput for a ~107 MB slice (the size of the largest
# Sept 6 pull) from the WSL Windows mount vs local ext4. Read-only.
#
#   bash docs/research/scripts/io_bench.sh <mnt_e_cold_file> <mnt_e_file> <local_copy>
#
# The first file should not have been read this session (cold-ish; the Windows
# host cache may still hold it). Offsets are arbitrary mid-file 1 MiB blocks.
set -euo pipefail
cold="$1"; mnt="$2"; local_copy="$3"

slice() { dd if="$1" of=/dev/null bs=1M skip="$2" count=107 2>&1 | tail -1; }

echo "--- /mnt/e cold-ish file, same slice x3"
for _ in 1 2 3; do slice "$cold" 300; done
echo "--- /mnt/e Sept 6 archive, slice x2"
for _ in 1 2; do slice "$mnt" 500; done
echo "--- local copy, same slice x2"
for _ in 1 2; do slice "$local_copy" 500; done
echo "--- mount"
mount | grep " /mnt/e " || true
