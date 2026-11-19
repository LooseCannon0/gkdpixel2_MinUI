#!/bin/bash
# Fast-boot image assembler for GKD Pixel 2 MinUI
# Usage: assemble.sh <base-1.0.1.img> <extracted-squashfs-dir> <out.img>
#
# The extracted squashfs dir is only read (it can double as your link sysroot):
# it's copied to a private staging tree next to <out.img>, which needs about as
# much free space as the extracted tree itself.
#
# Env overrides:
#   BINS       MinUI workspace with built binaries (workspace/)
#   PREFIX_DIR cross-build prefix holding lib/libmsettings.so
#   MINUI_TAR  the base image's minui.tar (extracted from its FAT partition)
#   SKIP_XZ=1  don't produce the .xz artifact
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE_IMG=${1:?usage: assemble.sh <base.img> <squashfs-dir> <out.img>}
FSDIR=${2:?missing extracted squashfs dir}
OUT=${3:?missing output image path}
BINS=${BINS:-$HOME/upstream-minui/workspace}
PREFIX_DIR=${PREFIX_DIR:-$HOME/xprefix}
MINUI_TAR=${MINUI_TAR:-$HOME/minui.tar}
SKIP_XZ=${SKIP_XZ:-}
OUTDIR="$(mkdir -p "$(dirname "$OUT")" && cd "$(dirname "$OUT")" && pwd)"
FAT_OFFSET=16777216   # sector 32768 * 512

die() { echo "error: $*" >&2; exit 1; }

# ── preflight: catch missing inputs before any slow step ────────────────────
TOOLS="mksquashfs mdel mcopy mdir tar"
[ -n "$SKIP_XZ" ] || TOOLS="$TOOLS xz"
for t in $TOOLS; do command -v "$t" >/dev/null || die "$t not found in PATH"; done
[ -f "$BASE_IMG" ] || die "base image not found: $BASE_IMG"
[ -e "$FSDIR/usr/lib/systemd/systemd" ] || die "$FSDIR doesn't look like the extracted SYSTEM squashfs"
[ -f "$MINUI_TAR" ] || die "minui.tar not found: $MINUI_TAR (set MINUI_TAR)"
[ -f "$HERE/pwr" ] || die "$HERE/pwr not built (README step 4)"
SYSTEM_BINS=(
    "$BINS/all/minui/build/gkdpixel2/minui.elf"
    "$BINS/all/minarch/build/gkdpixel2/minarch.elf"
    "$BINS/all/say/build/gkdpixel2/say.elf"
    "$BINS/all/syncsettings/build/gkdpixel2/syncsettings.elf"
    "$BINS/gkdpixel2/keymon/keymon.elf"
)
CLOCK_ELF="$BINS/all/clock/build/gkdpixel2/clock.elf"
MINPUT_ELF="$BINS/all/minput/build/gkdpixel2/minput.elf"
LIBMSETTINGS="$PREFIX_DIR/lib/libmsettings.so"
for f in "${SYSTEM_BINS[@]}" "$CLOCK_ELF" "$MINPUT_ELF" "$LIBMSETTINGS"; do
    [ -f "$f" ] || die "missing build output: $f (README step 3)"
done

WORK=""
STAGE=""
cleanup() {
    # unsquashfs can leave read-only dirs behind; make them deletable first
    for d in "$WORK" "$STAGE"; do
        [ -n "$d" ] && [ -d "$d" ] && { chmod -R u+w "$d" 2>/dev/null || true; rm -rf "$d"; }
    done
}
trap cleanup EXIT

echo "── 1/5 squashfs: stage a private copy, install fastinit ──"
WORK="$(mktemp -d "$OUTDIR/.assemble.XXXXXX")"
ROOT="$WORK/root"
cp -a --reflink=auto "$FSDIR" "$ROOT"
SYSD="$ROOT/usr/lib/systemd/systemd"
if [ ! -f "$ROOT/usr/lib/systemd/systemd.real" ]; then
    mv "$SYSD" "$ROOT/usr/lib/systemd/systemd.real"
fi
rm -f "$SYSD"
install -m 0755 "$HERE/fastinit" "$SYSD"
mkdir -p "$ROOT/usr/share/fastboot"
install -m 0755 "$HERE/launch-fast.sh" "$ROOT/usr/share/fastboot/launch-fast.sh"
install -m 0755 "$HERE/pwr" "$ROOT/usr/share/fastboot/pwr"
install -m 0644 "$HERE/asound.conf" "$ROOT/usr/share/fastboot/asound.conf"
install -m 0644 "$HERE/loading.raw" "$ROOT/usr/share/fastboot/loading.raw"
# The fast-mode ALSA config is applied at runtime by fastinit, never via /etc,
# so rescue mode keeps the stock routing. Up to v0.6 this script installed it
# as /etc/asound.conf in place; undo that if this tree went through it (stock
# ROCKNIX ships no /etc/asound.conf).
ETC_ASOUND="$ROOT/etc/asound.conf"
if [ -f "$ETC_ASOUND" ] && grep -q 'Fast-boot audio routing' "$ETC_ASOUND"; then
    echo "   removing the fast-mode /etc/asound.conf an older assemble.sh left in $FSDIR"
    rm -f "$ETC_ASOUND"
fi
if grep -q '/run/asound.conf' "$ROOT/usr/share/alsa/alsa.conf" 2>/dev/null; then
    echo "   ALSA: fast-mode config goes to /run/asound.conf at boot"
else
    # fastinit falls back to bind-mounting over /etc/asound.conf, which needs
    # the file to exist; an empty placeholder leaves rescue mode unaffected
    echo "   ALSA: alsa.conf doesn't load /run/asound.conf; fastinit will bind-mount over /etc/asound.conf"
    [ -e "$ETC_ASOUND" ] || [ -L "$ETC_ASOUND" ] || \
        echo "# placeholder: fast-boot mode bind-mounts /usr/share/fastboot/asound.conf here" > "$ETC_ASOUND"
fi
# stable mountpoint aliases
mkdir -p "$ROOT/storage/games-external" "$ROOT/storage/roms" 2>/dev/null || true
if [ ! -e "$ROOT/mnt/SDCARD" ] && [ ! -L "$ROOT/mnt/SDCARD" ]; then ln -s /storage/games-external "$ROOT/mnt/SDCARD"; fi

echo "── 2/5 squashfs: repack (gzip, b=262144) ──"
SYS_NEW="$OUTDIR/SYSTEM.fastboot"
rm -f "$SYS_NEW"
# -all-root: the stock SYSTEM is 100% root-owned (verified), so this keeps the
# repack faithful even when building as an unprivileged user.
# -no-xattrs: the stock SYSTEM carries no xattrs (verified); without this, a
# build host's own labels (e.g. security.selinux on Fedora) end up in the image.
mksquashfs "$ROOT" "$SYS_NEW" -comp gzip -b 262144 -noappend -quiet -all-root -no-xattrs
ls -lh "$SYS_NEW" | awk '{print "   SYSTEM: "$5}'

echo "── 3/5 minui.tar: swap in rebuilt binaries + kmsdrm launcher ──"
STAGE=$(mktemp -d)
tar -C "$STAGE" -xf "$MINUI_TAR"
B="$STAGE/.system/gkdpixel2/bin"
[ -d "$B" ] || die "$MINUI_TAR has no .system/gkdpixel2/bin"
cp "${SYSTEM_BINS[@]}" "$B/"
cp "$LIBMSETTINGS" "$STAGE/.system/gkdpixel2/lib/"
install -m 0755 "$HERE/launch-fast.sh" "$STAGE/.system/gkdpixel2/paks/MinUI.pak/launch-fast.sh"
# Clock and Input tools (not in the base image). Clock matters here: there's
# no RTC and no network time in fast mode.
T="$STAGE/Tools/gkdpixel2"
mkdir -p "$T/Clock.pak" "$T/Input.pak"
install -m 0755 "$HERE/tools/Clock.pak/launch.sh" "$CLOCK_ELF" "$T/Clock.pak/"
install -m 0755 "$HERE/tools/Input.pak/launch.sh" "$MINPUT_ELF" "$T/Input.pak/"
# The base port's own paks (Files, Music) pin themselves to Wayland, which
# doesn't exist in fast mode. Drop those exports so they inherit the
# environment of whichever launcher runs them — the stock launcher still sets
# Wayland in rescue mode. The stock MinUI.pak/launch.sh itself keeps them.
while IFS= read -r f; do
    case "$f" in */paks/MinUI.pak/*) continue ;; esac
    sed -i -E '/^[[:space:]]*export[[:space:]]+(SDL_VIDEODRIVER=wayland|WAYLAND_DISPLAY=|XDG_RUNTIME_DIR=)/d' "$f"
    echo "   un-pinned from Wayland: ${f#"$STAGE"/}"
done < <(grep -rlE --include=launch.sh '^[[:space:]]*export[[:space:]]+SDL_VIDEODRIVER=wayland' "$STAGE" || true)
TAR_NEW="$OUTDIR/minui.fastboot.tar"
# root-owned like the base tar, so extracting onto exFAT doesn't try to chown
tar -C "$STAGE" --owner=0 --group=0 --numeric-owner -cf "$TAR_NEW" .
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
