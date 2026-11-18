# Azahar settings for the dev container

Put Azahar's `qt-config.ini` here to give every container and workspace the same emulator setup.
`postCreateCommand` (dev container) and `tools/setup-workspace.sh` (Coder workspace) copy it to
`~/.config/azahar-emu/qt-config.ini` (path verified for Azahar 2126.2, see NOTES.md).

Create it once: start `azahar-headless` (or Azahar on your desktop), set
- System model: New 3DS
- CPU clock percentage: value from calibration (PLAN.md §6.1)
- Graphics API: OpenGL or Vulkan (software rendering works, just slower)
- Audio output: off / null

then copy the resulting `qt-config.ini` into this folder and commit it.
