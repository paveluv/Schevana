# Testing

The tests, how to run them and the rules for writing them are in
[tests/GUIDE.md](../tests/GUIDE.md). From the tree's root:

```bash
mkdir -p out
scheme --script tests/smoke.ss out
scheme --script tests/units.ss out
scheme --script tests/frame.ss out
scheme --script tests/sources.ss
```

For the hacker edition (`--hacker`, every library spliced into the
world), run smoke and units again with `SCHEVANA_HACKER=1` before each;
there the units' runner picks by itself the topics that tell the two
editions apart. Any other suite runs in the hacker edition the same way.

They run headless, on lavapipe (`mesa-vulkan-drivers`) on Linux and on
Metal on a Mac, and need `spirv-tools` on both for the shaders' checks.
They never touch your `~/.schevana-theme.ss`, `~/.schevana.ss` or
`~/.schevana.d`.
