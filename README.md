# Fast-boot MinUI for the GKD Pixel 2

> Built by Anthropic's **Claude Fable 5** model.

A custom firmware layer that boots the GKD Pixel 2 straight into
[MinUI](https://github.com/shauninman/MinUI) in about **4 seconds** — no
systemd, no Wayland compositor, no stock frontend in the path.

```
stock:  U-Boot → kernel → systemd → Sway → wayland MinUI     (~25-30 s)
this:   U-Boot → kernel → fastinit (PID 1) → MinUI on KMS/DRM  (~4 s)
```

MinUI runs as the direct DRM master via SDL2's kmsdrm backend; a ~100-line
shell script replaces the entire init system.

## Credits — this builds directly on others' work

- **[shauninman/MinUI](https://github.com/shauninman/MinUI)** — the launcher
  itself and the platform architecture this port plugs into.
- **[NukeBomB3000/minui-gkd-pixel2](https://github.com/NukeBomB3000/minui-gkd-pixel2)** —
  the wayland-based MinUI port whose v1.0.1 image supplies the bootloader,
  kernel, DTB, partition layout, emulator paks, and hardware documentation.
  This project modifies that image; it is required as the base.
- The stock firmware's ROCKNIX/LibreELEC-derived system squashfs remains in
  place as the runtime library base and as the rescue-mode OS.

Respect the upstream projects' licenses when redistributing.

## Repository layout

```
fastboot/
  fastinit         PID-1 init script (installed as /usr/lib/systemd/systemd
                   inside the SYSTEM squashfs; the initramfs execs it directly)
  launch-fast.sh   MinUI launcher: kmsdrm + alsa-softvol env, game loop, splash
  asound.conf      reconnects ALSA defaults and defines the 'minui' softvol pcm
                   (the codec exposes no hardware volume control at all)
  pwr.c            ~20-line reboot(2) tool; this kernel has no sysrq and its
                   busybox has no poweroff applet, so PID 1 needs this
  loading.raw      480x640 XRGB8888 pre-rotated "LOADING..." framebuffer image
  make-splash.py   regenerates loading.raw / custom splashes
  assemble.sh      builds the flashable image: repacks the SYSTEM squashfs,
                   swaps rebuilt binaries + launch-fast.sh into minui.tar, and
                   writes both into the base image's FAT partition via mtools
minui/gkdpixel2/   MinUI platform layer for this device (drop into MinUI's
                   workspace/ as workspace/gkdpixel2):
  platform/        platform.c/.h — based on NukeBomB3000's port, plus a
                   rotation layer: everything renders into a 640x480 target
                   texture, presented with one rotated GPU blit to the portrait
                   (480x640) panel; auto-detects, MINUI_ROTATION env overrides
  keymon/          hotkey daemon (raw evdev)
  libmsettings/    brightness/volume/jack backend, patched for this device's
                   real ALSA controls ('MinUI' softvol; Speaker/Headphone
                   switches)
patches/
  minui-api-aarch64-guard.patch   upstream MinUI gates ARMv7 inline asm with
                   `#if __ARM_ARCH >= 5`, which also matches aarch64; this adds
                   `&& !defined(__aarch64__)`
```

## Building the binaries

Cross-compiled on Ubuntu 24.04 with `gcc-aarch64-linux-gnu`, linked against the
device's own libraries (extract the SYSTEM squashfs from the base image with
`unsquashfs`) so ABI compatibility is guaranteed:

1. Clone shauninman/MinUI, apply `patches/minui-api-aarch64-guard.patch`, copy
   `minui/gkdpixel2/` in as `workspace/gkdpixel2/`.
2. Fetch matching SDL headers (device ships SDL 2.30.9, SDL_ttf 2.20.2,
   SDL_image 2.8.2) and point `platform/makefile.env`'s include/lib paths at
   them plus a symlink farm over the extracted squashfs's `/usr/lib`.
3. `make PLATFORM=gkdpixel2 CROSS_COMPILE=aarch64-linux-gnu- PREFIX=...` in
   `workspace/gkdpixel2/libmsettings`, then in `workspace/all/{minui,minarch,
   say,syncsettings,clock,minput}` and `workspace/gkdpixel2/keymon`.
4. `aarch64-linux-gnu-gcc -O2 -s fastboot/pwr.c -o fastboot/pwr`
5. `fastboot/assemble.sh <base-1.0.1.img> <extracted-squashfs-dir> <out.img>`

Binaries can be sanity-checked without hardware via qemu-user against the
extracted squashfs (`qemu-aarch64 <fs>/usr/lib/ld-linux-aarch64.so.1
--library-path <fs>/usr/lib minui.elf` with `SDL_VIDEODRIVER=dummy`).

## Runtime notes

- **Rescue mode:** an empty `rescue.txt` on the FAT partition boots the
  original stock stack (fastinit execs the preserved `systemd.real`).
- **Rotation override:** `rotation.txt` on the FAT partition containing
  0/90/180/270.
- **Custom boot splash:** drop a `splash.raw` on the FAT partition (generate
  with `make-splash.py`).
- **Diagnostics:** fastinit mirrors `fastboot.log`, a dmesg tail, and the ALSA
  control list (`mixer.txt`) to the ROMS partition every boot.
- Shutdown unmounts the SD partitions and powers off via `pwr`; PID 1 is
  guarded against ever exiting (kernel panic otherwise).
- WiFi/Bluetooth services are not started in fast mode by design.

## Known limitations

- Deep sleep (suspend-to-RAM) untested without systemd; MinUI's screen-off
  sleep works.
- The CPU runs on the `performance` governor throughout; MinUI's per-state
  clocking writes `scaling_setspeed`, which is inert unless the `userspace`
  governor is active. Costs some battery, never performance.
- The SYSTEM squashfs still carries the full stock userland (~415 MB) as a
  library donor and rescue base; it could be stripped much smaller.
- The pre-U-Boot logo and the initramfs bootsplash are untouched.
