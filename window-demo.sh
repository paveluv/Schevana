#!/bin/sh
# Runs the checklist demo, window-demo.ss, as a plain Chez program with
# this folder (the tree) as Chez's library folder. Chez compiles each
# library when it is imported, into the same cache the launchers use
# (src/launch.ss names its folders the same way: Chez's version, then the
# machine type), and loads the compiled file from there while it is newer
# than its source.
dir=$(dirname "$0")
cache=$dir/.cache/$(scheme --version 2>&1)-$(echo '(display (machine-type))' \
                                               | scheme -q)
exec scheme --libdirs "$dir::$cache" --compile-imported-libraries \
  --program "$dir/window-demo.ss" "$@"
