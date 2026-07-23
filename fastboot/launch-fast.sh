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
export LD_LIBRARY_PATH="$SYSTEM_PATH/lib:/usr/lib:$LD_LIBRARY_PATH"

# The whole point:
export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
export AUDIODEV=minui         # softvol pcm defined in /etc/asound.conf
# Rotation autodetects from the portrait display mode; override at
# /flash/rotation.txt with 0 / 90 / 180 / 270 if the panel comes up wrong.
[ -f /flash/rotation.txt ] && export MINUI_ROTATION="$(cat /flash/rotation.txt)"

echo "$(date) launch-fast started (kmsdrm)" >> "$LOGS_PATH/minui.txt"
keymon.elf >> "$LOGS_PATH/keymon.txt" 2>&1 &

cd "$SYSTEM_PATH/paks/MinUI.pak"
EXEC_PATH=/tmp/minui_exec
NEXT_PATH=/tmp/next
touch "$EXEC_PATH" && sync
while [ -f "$EXEC_PATH" ]; do
    minui.elf >> "$LOGS_PATH/minui.txt" 2>&1
    echo "$(date +'%F %T')" > "$DATETIME_PATH"
    sync
    if [ -f "$NEXT_PATH" ]; then
        CMD=$(cat "$NEXT_PATH")
        rm -f "$NEXT_PATH"
        cat /usr/share/fastboot/loading.raw > /dev/fb0 2>/dev/null
        eval "$CMD"
        cat /usr/share/fastboot/loading.raw > /dev/fb0 2>/dev/null
        echo "$(date +'%F %T')" > "$DATETIME_PATH"
        sync
    fi
    [ -f /tmp/poweroff ] && break
done
# fall back to fastinit, which powers off via sysrq
