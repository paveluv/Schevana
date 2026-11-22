#!/bin/sh
# The checklist demo, window-demo.ss: a plain program, run with
# this folder, the tree, as Chez's library folder. Chez compiles each
# library as it's imported, into the launchers' own cache (src/launch.ss
# names it so: Chez's version, then its machine type), and loads it from
# there once it's newer than its source.
dir=$(dirname "$0")
cache=$dir/.cache/$(scheme --version 2>&1)-$(echo '(display (machine-type))' \
                                               | scheme -q)
exec scheme --libdirs "$dir::$cache" --compile-imported-libraries \
  --program "$dir/window-demo.ss" "$@"
