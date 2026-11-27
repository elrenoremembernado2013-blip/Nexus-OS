# NEXUS OS Gaming, Steam & Proton Architecture (Phase 6)

## Scope & Honesty Rules

- **No fabricated libraries or FPS claims:** NEXUS Gaming Hub reports only locally installed Steam manifests (`appmanifest_*.acf`), detected Proton tool directories, real `/sys/bus/pci/devices` GPUs, real `vulkaninfo`/`glxinfo` output when installed, and real `/sys/class/input/js*` controllers.
- **No false Windows compatibility promises:** Native Linux games run directly on Linux Mint libraries; Windows titles via Valve's **Steam Play / Proton** depend on GPU Vulkan/OpenGL support and per-title compatibility (some anti-cheat or DRM titles remain unsupported).
- **Safe hardware boundaries:** NEXUS Gaming Mode adjusts reversible `powerprofilesctl` and compositor/animation settings (`apply-nexus-xfce.sh --lightweight` / `apply-nexus-cinnamon.sh --profile performance`) and recommends `gamemoderun %command%`. It never overclocks hardware or alters kernel/voltage limits.

## Linux Mint Gaming Components

1. **Steam & Store Gaming Ecosystem**:
   - Steam is packaged via Linux Mint/Ubuntu's `steam-installer` APT package (`linux/mint/nexus-gaming-cli.sh steam install` -> `nexus-store-cli.sh install apt steam-installer` with `pkexec`).
   - Supporting tools in `apps/store-catalog.js` and `linux/config/mint-packages.list`: `GameMode`, `MangoHud`, `Lutris` (`net.lutris.Lutris` via Flathub), and `Heroic Games Launcher` (`com.heroicgameslauncher.hgl` via Flathub).

2. **Graphics & Drivers**:
   - AMD and Intel GPUs use Linux Mint's built-in open-source Mesa / `amdgpu` / `i915` drivers (`mesa-vulkan-drivers`, `vulkan-tools`).
   - NVIDIA GPUs should be configured using Linux Mint's **Driver Manager** (`mintdrivers`) rather than unverified third-party driver scripts.

3. **Controllers**:
   - USB and Bluetooth Xbox, PlayStation, and generic HID gamepads use Linux kernel `hid`/`xpad`/`hid-playstation` modules and `/dev/input/js*` + Steam Input. Installing `steam-devices` provides controller udev permissions when needed.

## Verification & Current Limits

- **Verified locally & in CI:** `bash -n`, `shellcheck`, JSON status output from `nexus-gaming-cli.sh status`, `--dry-run gaming-mode` & `--dry-run steam install/remove`, `/api/gaming/status` over authenticated loopback HTTP, and `scripts/check-gaming.js` UI/boundary tests.
- **Requires a physical GPU / booted Linux Mint session (not yet tested):** Live Steam download/login/launch, Proton Windows-title execution, `vulkaninfo` GPU acceleration, GameMode process priority behavior, and physical USB/Bluetooth controller input.
