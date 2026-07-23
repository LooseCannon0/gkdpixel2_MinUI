# Changelog

## v0.6
- Fixed: the first-boot fallback reboot used sysrq, which this kernel doesn't
  have — if the installer ever returned, the device would have fallen through
  into a broken boot. Now uses `pwr reboot` (sysrq kept as a last resort).
- Fixed: `SetBrightness` read an uninitialized value when passed an
  out-of-range level; input is now clamped to 0–10.
- Removed per-keypress/per-axis-event logging from the input path (SD wear
  and unbounded log growth).
- `keymon.c` includes `<sys/time.h>` explicitly for `gettimeofday`.
- Build scripts parameterized: `makefile.env`, the keymon makefile, and
  `assemble.sh` no longer hardcode the original build machine's paths; the
  `.img.xz` release artifact step is enabled.
- "Option B" naming retired: `optionb/` is now `fastboot/`, code markers are
  `FASTBOOT:`.

## v0.5
- Volume finally works: msettings drives the softvol control by its correct
  ALSA *simple* name (`MinUI` — simple mixer strips the "Volume" suffix), and
  also writes the raw control (0–100 maps 1:1 to the slider).
- Headphone/speaker switching uses this kernel's real controls
  (`Speaker`/`Headphone` switches; there are no path-mux controls).
- Softvol floor lowered to −60 dB so minimum volume is effectively silent.
- Default boot splash removed (opt-in via `splash.raw` on the FAT partition);
  added "LOADING..." framebuffer splash when entering and leaving games.

## v0.4
- Volume rework attempt: ALSA default *mixer* was routed to the dead PipeWire
  daemon — added /etc/asound.conf override plus a softvol pcm ('minui') since
  the codec turned out to expose no hardware volume control at all.
- Boot splash painted from fastinit (later made opt-in in v0.5).
- fastinit dumps the ALSA control list to the SD for diagnostics.

## v0.3
- Power-off fixed: this kernel has no sysrq and busybox has no power applets,
  so PID 1 exiting caused a panic-hang. Added `pwr` (direct reboot(2) syscall,
  same final step systemd performs); shutdown now unmounts SD partitions
  first and PID 1 can never exit.
- Mixer calls made card-explicit.

## v0.2
- GPU fixed: fastinit loads `gpu-sched` + `panfrost` (udev used to) and waits
  for the render node — cures the 2 s/frame software-rendered UI and the
  "frozen" games.
- Audio routed direct to hardware (`AUDIODEV`), bypassing the dead daemon.
- Logs line-buffered; renderer name logged; fastboot.log + dmesg mirrored to
  the visible SD partition.

## v0.1
- Initial Option B: systemd/Sway removed, fastinit as PID 1, MinUI as direct
  DRM master via SDL2 kmsdrm, GPU-rotated presentation for the portrait
  panel, rescue-mode hatch, first-boot partitioning preserved from the base
  image. Built on NukeBomB3000's wayland port v1.0.1.
