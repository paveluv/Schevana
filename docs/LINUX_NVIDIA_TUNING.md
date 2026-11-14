# NVIDIA on Linux: hardware vblank stamps

With NVIDIA's proprietary driver on a Wayland desktop (GNOME's mutter), an
animation in Schevana, Boids 3D say, can stutter now and then: a refresh
shows the previous frame again, although Schevana had the next one ready,
drawn and submitted well in time. Monitor and the Pipeline don't count it as
late, because it isn't Schevana's: the compositor held the frame back.

The cure is one module option and a reboot:

```bash
echo "options nvidia-drm vblank=1" |
  sudo tee /etc/modprobe.d/nvidia-drm-vblank.conf
sudo update-initramfs -u
sudo reboot
```

After the reboot, check it took:

```bash
cat /sys/module/nvidia_drm/parameters/vblank
journalctl --user -b | grep -c "Invalid sequence for VSYNC frame info"
```

The first should say `Y`, and the second `0`. To undo it, delete the file,
run `sudo update-initramfs -u` again and reboot.

Measured on Debian 13 (Linux 6.12), NVIDIA 615.71.10 and GNOME Shell 48.7,
at 60 Hz. Other versions may differ: NVIDIA ships the option off. NVIDIA
595.99.02, Ubuntu 26.04's, has none to turn on: `modinfo -p nvidia_drm`
lists `modeset` and `fbdev` alone. There, Boids 3D shows a refresh again
about every 3 s ([PLATFORMS.md](PLATFORMS.md)).

## Why

Three parts below Schevana work together to drop a ready frame:

1. **nvidia-drm stamps flips late.** Loaded with its default `vblank=N`, it
   has no vblank support, so each page-flip event carries the kernel's clock
   at the moment the event is sent, not the vblank's time, with sequence 0.
   The event is sent from a deferred worker thread at ordinary priority:
   most stamps are within tens of microseconds of the refresh, but some come
   0.5 to 9 ms late. Mutter reports these stamps to its clients as when
   frames were presented, and logs "Invalid sequence for VSYNC frame info".
2. **NVIDIA's Vulkan driver targets each frame 0.5 ms early.** In FIFO mode
   it attaches a `wp_commit_timer_v1` timestamp to every present: the
   refresh it predicts from the stamp of an earlier frame, less 500 µs.
   This is Mesa's algorithm, which the targets match to within 2 µs.
3. **Mutter compares that target strictly.** It applies a timed commit only
   in a frame whose predicted presentation (its newest stamp plus a
   refresh) is not earlier than the target. Nothing is applied on arrival;
   a held commit waits for the next frame of mutter's.

So when one stamp is about 0.52 ms or more late, the target of a later frame
lands just past mutter's prediction, and mutter shows the previous frame
once more, though the new one was finished 20 to 40 ms earlier.

With `vblank=1`, nvidia-drm initializes vblank support, and flip events
carry the display engine's own vblank time and real sequence numbers. The
0.5 ms margin then holds against stamps accurate to the microsecond. In a
191-second run with the Pipeline open, stamps were within 1 µs at the 99th
percentile, no frame was held for its target, and one refresh was lost,
during input, with Schevana's frame on time: most likely a miss of mutter's
own.

Before the option, about 1 frame in 1,100 was held this way with the
Pipeline maximized, more in bursts, and the largest late stamps fell on the
first refresh after each whole second of the session's clock (gnome-shell's
garbage collector is the leading suspect). No pacing on the client's side
can avoid it: the target is the driver's, and an application's own present
timing can only make it later, not earlier.

## What to watch for

- **Early stamps after idle.** After 5 s with no flips (DRM's default
  vblank off-delay), the first flips may carry a coarse stamp, up to 4 ms
  early, until the next vblank interrupt. An early stamp can hold a frame
  the same way. If animations stutter as they start after a pause,
  `drm.vblankoffdelay=-1` on the kernel's command line keeps vblank
  interrupts on; this is untested.
- **Early stamps from an order race.** If the driver finishes a flip before
  handling that vblank's interrupt, the flip carries the previous vblank's
  time, which shows as pairs of gaps of about 0 and 2 refreshes. Not seen
  so far.

## Bugs in mutter, for anyone who'd like to fix them

Line numbers are mutter 48.7's.

- **The strict commit-timing test.**
  `meta-wayland-transaction.c:312-316` holds a commit whose target is even a
  microsecond past the frame's predicted presentation:
  `if (target_time_us < transaction->target_presentation_time_us) return
  FALSE`. Predictions rest on presentation feedback, which jitters (by
  milliseconds with NVIDIA's software stamps), so a client that targets a
  refresh exactly loses a whole refresh to rounding. Upstream main keeps
  the same comparison. A tolerance, say a quarter of a refresh (Mesa's WSI
  snaps targets to the grid within that), would keep the protocol's meaning
  and drop the stutter.
- **The KMS deadline timer, silently off.** `meta-kms-crtc.c:656` builds the
  GError for a failed `drmWaitVBlank` from `-ret`, which is 1 (EPERM),
  rather than from `errno`. With NVIDIA's `vblank=N` the real error is
  EOPNOTSUPP, but it reads as PERMISSION_DENIED, and the deadline timer is
  quietly marked inhibited (`meta-kms-impl-device.c:1397-1406`). Mutter then
  commits each composite to KMS as soon as it's submitted, and one that
  finishes after the vblank flips a refresh later for the whole screen.
- **An assertion around swapchain rebuilds.**
  "meta_wayland_buffer_process_damage: assertion 'buffer->resource'
  failed", logged twice when a Vulkan
  swapchain was torn down and built again (a maximize, a resize), without a
  crash. Commits still queued in mutter when the swapchain's buffers are
  destroyed are the suspect.
- **A crash.** Two FIFO presents through NVIDIA's Vulkan driver on a
  `wl_surface` that had no role (no `xdg_toplevel`), with the driver's
  `wp_fifo_v1` barriers and `wp_commit_timer_v1` timestamps on them,
  crashed mutter on the second commit and took the whole session down. A
  client's mistake shouldn't do that. Schevana's windows always have a role;
  this came from a research probe.

And two for NVIDIA: the FIFO driver's fixed 0.5 ms margin is narrower than
its own `vblank=N` stamps' error, and `VK_EXT_present_timing` reports a
refresh of 16,666,666 ns where the display's is 16,667,604 ns.
