#!/bin/sh
# Fast-boot launcher: MinUI directly on KMS/DRM — no compositor.
export PLATFORM="gkdpixel2"
export SDCARD_PATH="/mnt/SDCARD"
export BIOS_PATH="$SDCARD_PATH/Bios"
export SAVES_PATH="$SDCARD_PATH/Saves"
export SYSTEM_PATH="$SDCARD_PATH/.system/$PLATFORM"
export CORES_PATH="$SYSTEM_PATH/cores"
export USERDATA_PATH="$SDCARD_PATH/.userdata/$PLATFORM"
export SHARED_USERDATA_PATH="$SDCARD_PATH/.userdata/shared"
export LOGS_PATH="$USERDATA_PATH/logs"
export DATETIME_PATH="$SHARED_USERDATA_PATH/datetime.txt"
mkdir -p "$LOGS_PATH" "$SHARED_USERDATA_PATH/.minui"
export PATH="$SYSTEM_PATH/bin:$PATH"
# /usr/lib first, as in the base port: the device's own SDL must win over
# anything bundled in $SYSTEM_PATH/lib. No trailing ':' when LD_LIBRARY_PATH
# starts out empty — an empty entry means "current directory" to ld.so.
export LD_LIBRARY_PATH="/usr/lib:$SYSTEM_PATH/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# The whole point:
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
export AUDIODEV=minui         # softvol pcm from the fast-mode asound.conf
# Tells libmsettings it owns the mixer (softvol + Speaker/Headphone switches).
# Rescue mode runs the same binaries without it and keeps PipeWire's routing.
export MINUI_FASTBOOT=1
# Rotation autodetects from the portrait display mode; override at
# /flash/rotation.txt with 0 / 90 / 180 / 270 if the panel comes up wrong
# (anything else is logged and ignored).
[ -f /flash/rotation.txt ] && export MINUI_ROTATION="$(cat /flash/rotation.txt)"

# keep logs bounded across boots (one generation kept as .old)
trim_log() {
    [ -f "$1" ] && [ "$(wc -c < "$1")" -gt 262144 ] && mv -f "$1" "$1.old"
}
trim_log "$LOGS_PATH/minui.txt"
trim_log "$LOGS_PATH/keymon.txt"

echo "$(date) launch-fast started (kmsdrm)" >> "$LOGS_PATH/minui.txt"
keymon.elf >> "$LOGS_PATH/keymon.txt" 2>&1 &

uptime_s() { cut -d. -f1 /proc/uptime; }

cd "$SYSTEM_PATH/paks/MinUI.pak"
EXEC_PATH=/tmp/minui_exec
NEXT_PATH=/tmp/next
# minui.elf only exits on its own to launch something (/tmp/next), to power off
# (/tmp/poweroff), or after an HDMI change (it sleeps 4 s first). A quicker exit
# with neither file means it failed to start; give up after a few in a row
# rather than restart it forever.
MAX_FAILS=5
FAILS=0
touch "$EXEC_PATH" && sync
while [ -f "$EXEC_PATH" ]; do
    STARTED=$(uptime_s)
    minui.elf >> "$LOGS_PATH/minui.txt" 2>&1
    RC=$?
    echo "$(date +'%F %T')" > "$DATETIME_PATH"
    sync
    [ -f /tmp/poweroff ] && break
    if [ -f "$NEXT_PATH" ]; then
        FAILS=0
        CMD=$(cat "$NEXT_PATH")
        rm -f "$NEXT_PATH"
        cat /usr/share/fastboot/loading.raw 2>/dev/null > /dev/fb0
        eval "$CMD"
        cat /usr/share/fastboot/loading.raw 2>/dev/null > /dev/fb0
        echo "$(date +'%F %T')" > "$DATETIME_PATH"
        sync
    elif [ $(( $(uptime_s) - ${STARTED:-0} )) -lt 3 ]; then
        FAILS=$((FAILS+1))
        echo "$(date) minui.elf exited after <3 s with nothing queued (status $RC), failure $FAILS/$MAX_FAILS" >> "$LOGS_PATH/minui.txt"
        if [ $FAILS -ge $MAX_FAILS ]; then
            echo "$(date) minui.elf keeps failing to start; giving up (see the lines above)" >> "$LOGS_PATH/minui.txt"
            sync
            break
        fi
        sleep 1
    else
        FAILS=0
    fi
    [ -f /tmp/poweroff ] && break
done
# fall back to fastinit, which unmounts the SD partitions and powers off
