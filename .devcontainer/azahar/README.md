# Azahar settings for the dev container

Put Azahar's `qt-config.ini` here to give every container the same emulator setup.
`postCreateCommand` copies it to `~/.config/azahar-emu/`.

Create it once: start `azahar-headless` (or Azahar on your desktop), set
- System model: New 3DS
- CPU clock percentage: value from calibration (PLAN.md §6.1)
- Graphics API: OpenGL or Vulkan (software rendering works, just slower)
- Audio output: off / null

then copy the resulting `qt-config.ini` into this folder and commit it.
Verify the config path for the installed Azahar version; it may differ.
