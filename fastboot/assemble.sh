#!/bin/bash
# Fast-boot image assembler for GKD Pixel 2 MinUI
# Usage: assemble.sh <base-1.0.1.img> <extracted-squashfs-dir> <out.img>
# Env overrides:
#   BINS       MinUI workspace with built binaries (workspace/)
#   PREFIX_DIR cross-build prefix holding lib/libmsettings.so
#   MINUI_TAR  the base image's minui.tar (extracted from its FAT partition)
#   SKIP_XZ=1  don't produce the .xz artifact
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE_IMG=${1:?usage: assemble.sh <base.img> <squashfs-dir> <out.img>}
FSDIR=${2:?missing extracted squashfs dir}
OUT=${3:?missing output image path}
BINS=${BINS:-$HOME/upstream-minui/workspace}
PREFIX_DIR=${PREFIX_DIR:-$HOME/xprefix}
MINUI_TAR=${MINUI_TAR:-$HOME/minui.tar}
OUTDIR="$(mkdir -p "$(dirname "$OUT")" && cd "$(dirname "$OUT")" && pwd)"
FAT_OFFSET=16777216   # sector 32768 * 512

echo "── 1/5 squashfs: install fastinit ──"
SYSD="$FSDIR/usr/lib/systemd/systemd"
if [ ! -f "$FSDIR/usr/lib/systemd/systemd.real" ]; then
    mv "$SYSD" "$FSDIR/usr/lib/systemd/systemd.real"
fi
install -m 0755 "$HERE/fastinit" "$SYSD"
mkdir -p "$FSDIR/usr/share/fastboot"
install -m 0755 "$HERE/launch-fast.sh" "$FSDIR/usr/share/fastboot/launch-fast.sh"
install -m 0755 "$HERE/pwr" "$FSDIR/usr/share/fastboot/pwr"
install -m 0644 "$HERE/asound.conf" "$FSDIR/etc/asound.conf"
install -m 0644 "$HERE/loading.raw" "$FSDIR/usr/share/fastboot/loading.raw"
# stable mountpoint aliases
mkdir -p "$FSDIR/storage/games-external" "$FSDIR/storage/roms" 2>/dev/null || true
if [ ! -e "$FSDIR/mnt/SDCARD" ] && [ ! -L "$FSDIR/mnt/SDCARD" ]; then ln -s /storage/games-external "$FSDIR/mnt/SDCARD"; fi

echo "── 2/5 squashfs: repack (gzip, b=262144) ──"
SYS_NEW="$OUTDIR/SYSTEM.fastboot"
rm -f "$SYS_NEW"
# -all-root: the stock SYSTEM is 100% root-owned (verified), so this keeps the
# repack faithful even when building as an unprivileged user
mksquashfs "$FSDIR" "$SYS_NEW" -comp gzip -b 262144 -noappend -quiet -all-root
ls -lh "$SYS_NEW" | awk '{print "   SYSTEM: "$5}'

echo "── 3/5 minui.tar: swap in rebuilt binaries + kmsdrm launcher ──"
STAGE=$(mktemp -d)
tar -C "$STAGE" -xf "$MINUI_TAR"
B="$STAGE/.system/gkdpixel2/bin"
cp "$BINS/all/minui/build/gkdpixel2/minui.elf"        "$B/"
cp "$BINS/all/minarch/build/gkdpixel2/minarch.elf"    "$B/"
cp "$BINS/all/say/build/gkdpixel2/say.elf"            "$B/"
cp "$BINS/all/syncsettings/build/gkdpixel2/syncsettings.elf" "$B/"
cp "$BINS/gkdpixel2/keymon/keymon.elf"                "$B/"
cp "$PREFIX_DIR/lib/libmsettings.so" "$STAGE/.system/gkdpixel2/lib/"
install -m 0755 "$HERE/launch-fast.sh" "$STAGE/.system/gkdpixel2/paks/MinUI.pak/launch-fast.sh"
TAR_NEW="$OUTDIR/minui.fastboot.tar"
tar -C "$STAGE" -cf "$TAR_NEW" .
rm -rf "$STAGE"
ls -lh "$TAR_NEW" | awk '{print "   minui.tar: "$5}'

echo "── 4/5 image: copy base + replace FAT payloads ──"
cp --sparse=always "$BASE_IMG" "$OUT"
mdel  -i "$OUT@@$FAT_OFFSET" ::/SYSTEM
mcopy -i "$OUT@@$FAT_OFFSET" "$SYS_NEW" ::/SYSTEM
mdel  -i "$OUT@@$FAT_OFFSET" ::/minui.tar
mcopy -i "$OUT@@$FAT_OFFSET" "$TAR_NEW" ::/minui.tar
mdir  -i "$OUT@@$FAT_OFFSET" :: | sed 's/^/   /'

echo "── 5/5 compress ──"
if [ -z "$SKIP_XZ" ]; then
    xz -T0 -f -k "$OUT"
    ls -lh "$OUT" "$OUT.xz" | awk '{print "   "$NF": "$5}'
else
    ls -lh "$OUT" | awk '{print "   "$NF": "$5}'
fi
echo "done."
