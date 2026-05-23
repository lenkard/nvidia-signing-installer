# nvidia-signing-installer

Safe Debian-focused diagnostics, Secure Boot / MOK signing helpers, corrupted-module repair helpers, recovery helpers, and a terminal menu for NVIDIA drivers.

## Goals

- Diagnose common NVIDIA-on-Debian failures
- Detect Secure Boot blocking of NVIDIA modules
- Detect corrupted installed NVIDIA kernel modules like `.ko.xz`
- Verify that the installed package set actually provides `nvidia-smi`
- Detect when packages are installed successfully but the installed NVIDIA branch is too old for the GPU
- Install Debian prerequisites and Debian-packaged NVIDIA drivers
- Create and enroll a MOK key for module signing
- Re-sign NVIDIA modules for the current kernel
- Build, install, sign, and verify NVIDIA modules for a **target kernel**
- Recover from wrong MOK password / broken signing setup
- Keep per-script logs and session summary logs
- Warn when Debian-packaged NVIDIA support is likely too old for RTX 50 / Blackwell GPUs

## Target environment

- Debian 12/13, especially Debian Trixie
- Debian packages + backports
- Optional external/upstream NVIDIA guidance only
- Secure Boot enabled systems
- Headless / TTY-first workflows
- Reusable on similar Debian/NVIDIA systems
- Multiple installed kernels

## Safety model

- Safe steps can be performed automatically
- Destructive recovery steps are only reached through explicit menu/script selection
- Replacing old local MOK key files requires confirmation
- Target-kernel workflows require an explicit target kernel argument
- Driver-too-old detection warns clearly but does not hard-stop every workflow
- The project does **not** disable Secure Boot
- The project does **not** use NVIDIA's `.run` installer automatically
- The project does **not** silently change BIOS/UEFI settings

## Layout

- `scripts/00-diagnose.sh` — current-system diagnostics, `.ko.xz` health, `nvidia-smi`, GPU PCI IDs, and driver support assessment
- `scripts/10-install-debian-prereqs.sh` — install Debian prerequisites, including `whiptail`
- `scripts/15-install-nvidia-driver.sh` — install Debian-packaged NVIDIA driver and warn if the branch is too old for the GPU
- `scripts/16-switch-to-backports.sh` — switch/install NVIDIA packages from `trixie-backports`
- `scripts/20-create-or-enroll-mok.sh` — create/import MOK; supports `--fresh`
- `scripts/25-recover.sh` — recovery flow: purge/reinstall driver + repair installed modules + fresh MOK setup
- `scripts/27-repair-installed-modules.sh` — detect/remove broken installed NVIDIA module files, rebuild DKMS, depmod, initramfs, and verify `nvidia-smi`
- `scripts/30-sign-nvidia-modules.sh` — sign installed NVIDIA modules for the selected kernel and rebuild initramfs
- `scripts/40-verify.sh` — verify current/selected kernel module files, signatures, runtime state, `.ko.xz` health, and `nvidia-smi`
- `scripts/50-build-target-kernel.sh` — build + install + optional sign + depmod + initramfs + verify for a target kernel
- `scripts/51-verify-target-kernel.sh` — verify a target kernel only
- `scripts/run-all.sh` — guided first-time flow
- `scripts/run-recovery.sh` — guided recovery flow
- `scripts/menu.sh` — terminal UI menu using `whiptail`
- `helpers/common.sh` — shared helpers

## What changed for Debian module naming

Debian may install DKMS NVIDIA modules with names like:
- `nvidia-current.ko.xz`
- `nvidia-current-modeset.ko.xz`
- `nvidia-current-drm.ko.xz`
- `nvidia-current-uvm.ko.xz`

The project now detects both styles:
- `nvidia*.ko.xz`
- `nvidia-current*.ko.xz`

So signing, repair, and verification no longer assume only one filename pattern.

## Driver-too-old detection

The project now checks both:
- package-version heuristics, for example older than 570 for RTX 50 / Blackwell-era GPUs
- kernel log messages like:
  - `not supported by the NVIDIA ... driver release`

It also logs:
- detected GPU PCI IDs
- installed NVIDIA driver version
- support verdict
- remediation guidance

When this condition is detected, the project explicitly says:

> Packages installed successfully, but this driver branch does not support your GPU.

## Terminal menu

After prerequisites are installed:

```bash
./scripts/menu.sh
```

Menu features:
- diagnostics
- Debian prerequisite install
- Debian NVIDIA driver install
- MOK import using existing keys
- fresh MOK setup
- NVIDIA module signing
- verification
- repair for broken installed module files
- full recovery flow
- target-kernel build/sign/verify flows
- backports remediation helper
- dedicated “driver too old” help screen

The menu writes a summary log under `logs/` and each called script still writes its own log too.

## `nvidia-smi` verification

Diagnostics and verification check:
- whether `nvidia-smi` is in `PATH`
- which installed Debian package owns the binary, if present
- whether a separate `nvidia-smi` package exists in apt

This helps detect package-set mismatches where kernel modules are present but NVIDIA userspace utilities are missing.

## Typical first-time usage

```bash
cd nvidia-signing-installer
./scripts/00-diagnose.sh
sudo ./scripts/10-install-debian-prereqs.sh
sudo ./scripts/15-install-nvidia-driver.sh
sudo ./scripts/20-create-or-enroll-mok.sh
```

Then:
1. Reboot
2. Complete MOK enrollment in the blue screen
3. Boot back into Linux
4. Run:

```bash
sudo ./scripts/30-sign-nvidia-modules.sh
./scripts/40-verify.sh
```

Or use:

```bash
./scripts/run-all.sh
```

## If Debian stable NVIDIA is too old for your GPU

Recommended order:
1. Try Debian backports first
2. Re-run diagnostics and verification
3. Only consider external/upstream NVIDIA packaging if Debian/backports still lacks support

### Automatic backports helper

```bash
sudo ./scripts/16-switch-to-backports.sh
```

This installs the NVIDIA stack from `trixie-backports` if available.

### Manual backports example

```bash
sudo apt-get install -t trixie-backports nvidia-driver nvidia-kernel-dkms nvidia-driver-libs nvidia-smi nvidia-settings
```

### Upstream/external guidance

The project provides guidance only. It does **not** automatically switch you to upstream `.run` or external NVIDIA packaging, because mixing packaging methods often breaks Debian DKMS setups.

## Target kernel workflow

This is for cases like:
- “I installed a new kernel and want NVIDIA ready before rebooting into it”
- “I booted a new kernel and need to rebuild NVIDIA for it”

### Signed target-kernel build

```bash
sudo ./scripts/50-build-target-kernel.sh 6.12.88+deb13-amd64
```

### Unsigned target-kernel build

```bash
sudo ./scripts/50-build-target-kernel.sh 6.12.88+deb13-amd64 --allow-unsigned
```

### Verify target kernel later

```bash
./scripts/51-verify-target-kernel.sh 6.12.88+deb13-amd64
```

### Verify target kernel but allow unsigned modules

```bash
./scripts/51-verify-target-kernel.sh 6.12.88+deb13-amd64 --unsigned-ok
```

The target-kernel workflow will:
1. require an explicit target kernel version
2. automatically install the target kernel package if apt has it and it is missing
3. automatically install matching headers if missing
4. reinstall the Debian NVIDIA package stack
5. rebuild DKMS modules for the target kernel
6. optionally sign the installed modules
7. run `depmod` for the target kernel
8. rebuild `initramfs` for the target kernel
9. verify module health, `modinfo`, signer fields, initramfs presence, and `nvidia-smi`

Target-kernel logs include the kernel version in the log file name.

## If `xz: File is corrupt` or `modinfo` fails on installed NVIDIA modules

If you see errors like:
- `libkmod: ERROR: xz_uncompress_belch: xz: File is corrupt`
- `modinfo: ERROR: could not get modinfo`

run:

```bash
sudo ./scripts/27-repair-installed-modules.sh
```

This will:
1. inspect `/lib/modules/<kernel>/updates/dkms/`
2. remove broken installed NVIDIA modules for the selected kernel
3. reinstall Debian NVIDIA DKMS-related packages
4. rebuild DKMS modules
5. run `depmod`
6. rebuild initramfs
7. verify that `xz -t` and `modinfo` work on the installed modules
8. verify that `nvidia-smi` exists after reinstall

If Secure Boot signing is also part of your issue, continue afterward with fresh MOK import or module signing.

## Recovery usage

If you entered the wrong MOK password, signing is broken, or you want a clean retry:

### Guided recovery

```bash
./scripts/run-recovery.sh
```

### Direct recovery script

```bash
sudo ./scripts/25-recover.sh
```

### Terminal menu recovery

```bash
./scripts/menu.sh
```

Choose:
- `Recovery: purge/reinstall driver + fresh MOK`

## Fresh MOK setup without full driver recovery

If you only want a new keypair and new enrollment attempt:

```bash
sudo ./scripts/20-create-or-enroll-mok.sh --fresh
```

## Reinstall driver without the rest of recovery

```bash
sudo ./scripts/15-install-nvidia-driver.sh --purge-reinstall
```

## Version consistency checks

Diagnostics print installed and apt-candidate versions for key packages such as:
- `nvidia-driver`
- `nvidia-kernel-dkms`
- `nvidia-driver-libs`
- `nvidia-smi`
- `firmware-misc-nonfree`
- `dkms`
- `linux-headers-<target-kernel>`

This helps detect partial upgrades or package mismatches.

## Logs

Per-script logs:

```text
./logs/YYYYmmdd-HHMMSS-<script>.log
```

Target-kernel logs:

```text
./logs/YYYYmmdd-HHMMSS-<script>-<target-kernel>.log
```

Menu/session summary logs:

```text
./logs/YYYYmmdd-HHMMSS-menu-session.log
```

## Manual steps you must still do yourself

- Reboot after `mokutil --import`
- Complete MOK enrollment in the blue firmware screen
- Enter the one-time MOK password you just created
- BIOS changes like PCIe Gen4 / iGPU / ReBAR / Secure Boot policy

## Rollback / cleanup

Remove local MOK files if desired:

```bash
rm -f MOK.der MOK.priv
```

Old key files preserved by fresh recovery are stored in `./backups/`.

To stop using the proprietary driver, purge it with apt as appropriate for your system.
