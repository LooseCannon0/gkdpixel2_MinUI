# Changelog

## v0.7
Fixes from a full review.

Boot and power
- PID 1 can no longer exit: the log redirect is probed before `exec` (a failed
  `exec >>` killed the shell, i.e. a kernel panic, e.g. when /storage didn't
  mount), and rescue mode only execs `systemd.real` if it's there.
- Backlight is switched on before the splash and the first-boot install; the
  panel can come up powered down, which left both on a dark screen.
- About 0.3 s off the boot path: no fixed `sleep 0.3` before audio setup, and
  the diagnostics dump runs in the background. The softvol pcm is opened with
  empty input, so it never holds the device when a game auto-resumes.
- Shutdown waits for keymon before unmounting (it used to fall back to a lazy
  unmount) and remounts /storage read-only before powering off.
- The launcher gives up after 5 failed `minui.elf` starts instead of
  restarting it forever; fastboot.log, minui.txt and keymon.txt are rotated
  at 256 KB.

Audio
- The fast-mode ALSA config is applied at runtime (`/run/asound.conf`) instead
  of replacing `/etc/asound.conf`, so rescue mode keeps PipeWire's routing.
  It now also points the default pcm at the `minui` softvol, so programs that
  open "default" (mpv in the Music pak) get sound.
- Volume keys work in rescue mode again: libmsettings drives the softvol only
  when `MINUI_FASTBOOT=1` (set by launch-fast.sh), else PipeWire's `Master`.
- `SetVolume` clamps to 0–20, and stored settings are validated on load; an
  out-of-range volume reached ALSA as e.g. 5000%.
- libmsettings: one `amixer` call per change (init went from 6 to 2), settings
  saved only when they change, with `fsync` of that file instead of a global
  `sync`, and no crash if shared memory is unavailable.

MinUI platform
- Rotation: `rotation.txt` is validated (0/90/180/270; BOM/CRLF tolerated);
  an empty or bad value no longer silently disables autodetection, and a
  failed rotation texture falls back to unrotated output instead of black.
- No more uninitialized reads when `wlan0` or the DT model is missing (could
  show a phantom WiFi icon); About shows the full model name.
- RK3326 CPU frequencies instead of rgb30's; L3/R3 no longer aliased to MENU
  (keymon matches); keymon no longer misreads `/dev/input/js0`.

Build
- assemble.sh: never modifies the extracted squashfs dir, checks all inputs
  up front, cleans up on failure, packages the Clock and Input tools (no RTC
  in fast mode), un-pins the base port's Files/Music paks from Wayland, and
  writes a root-owned minui.tar.
- assemble.sh repacks SYSTEM with `-no-xattrs` (stock has none), so a build
  host's SELinux labels no longer end up in the image.
- make-splash.py finds its font on Fedora/Arch too (or `SPLASH_FONT`).
- libmsettings builds at -O2 and warning-clean under `-Wall -Werror`.
- `makefile.env` makes implicit function declarations an error, and the
  README says to use a real Linux/aarch64 `SDL_config.h`: SDL's generic one is
  libc-less on Linux, which made MinUI's string functions implicit
  (pointer-truncating on aarch64) and broke the `say` build.
- Stale comments and docs corrected.

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
