# nvidia-signing-installer

Safe Debian-focused diagnostics, Secure Boot / MOK signing helpers, corrupted-module repair helpers, recovery helpers, and a terminal menu for NVIDIA drivers.

## Goals

- Diagnose common NVIDIA-on-Debian failures
- Detect Secure Boot blocking of NVIDIA modules
- Detect corrupted installed NVIDIA kernel modules like `.ko.xz`
- Verify that the installed package set actually provides `nvidia-smi`
- Install Debian prerequisites and Debian-packaged NVIDIA drivers
- Create and enroll a MOK key for module signing
- Re-sign NVIDIA modules for the current kernel
- Recover from wrong MOK password / broken signing setup
- Keep per-script logs and session summary logs
- Warn when Debian-packaged NVIDIA support is likely too old for RTX 50 / Blackwell GPUs

## Target environment

- Debian 12/13, especially Debian Trixie
- Debian-packaged NVIDIA drivers only
- Secure Boot enabled systems
- Headless / TTY-first workflows
- Reusable on similar Debian/NVIDIA systems

## Safety model

- Safe steps can be performed automatically
- Destructive recovery steps are only reached through explicit menu/script selection
- Replacing old local MOK key files requires confirmation
- The project does **not** disable Secure Boot
- The project does **not** use NVIDIA's `.run` installer
- The project does **not** silently change BIOS/UEFI settings

## Layout

- `scripts/00-diagnose.sh` — collect system/NVIDIA/Secure Boot diagnostics, check installed `.ko.xz` health, and check `nvidia-smi`
- `scripts/10-install-debian-prereqs.sh` — install Debian prerequisites, including `whiptail`
- `scripts/15-install-nvidia-driver.sh` — install Debian-packaged NVIDIA driver, or purge+reinstall, and try to install `nvidia-smi` if split out as a separate package
- `scripts/20-create-or-enroll-mok.sh` — create/import MOK; supports `--fresh`
- `scripts/25-recover.sh` — recovery flow: purge/reinstall driver + repair installed modules + fresh MOK setup
- `scripts/27-repair-installed-modules.sh` — detect/remove broken installed NVIDIA `.ko.xz` modules, rebuild DKMS, depmod, initramfs, and verify `nvidia-smi`
- `scripts/30-sign-nvidia-modules.sh` — sign NVIDIA modules for the current kernel and rebuild initramfs
- `scripts/40-verify.sh` — verify module files, signatures, runtime state, installed `.ko.xz` health, and `nvidia-smi`
- `scripts/run-all.sh` — guided first-time flow
- `scripts/run-recovery.sh` — guided recovery flow
- `scripts/menu.sh` — terminal UI menu using `whiptail`
- `helpers/common.sh` — shared helpers

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
- repair for broken installed `.ko.xz` NVIDIA modules
- full recovery flow

The menu writes a summary log under `logs/` and each called script still writes its own log too.

## `nvidia-smi` verification

Diagnostics and verification now check:
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

## If `xz: File is corrupt` or `modinfo` fails on installed NVIDIA modules

If you see errors like:
- `libkmod: ERROR: xz_uncompress_belch: xz: File is corrupt`
- `modinfo: ERROR: could not get modinfo`

run:

```bash
sudo ./scripts/27-repair-installed-modules.sh
```

This will:
1. inspect `/lib/modules/$(uname -r)/updates/dkms/`
2. remove broken installed NVIDIA `.ko` / `.ko.xz` files for the current kernel
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

## What recovery does

Recovery is designed for the case where signing is broken and you want the shortest clean retry path.

It will:
1. install prerequisites
2. purge Debian NVIDIA packages
3. reinstall Debian NVIDIA packages
4. repair broken installed NVIDIA module files if needed
5. try to install `nvidia-smi` if Debian provides it separately
6. create a fresh local MOK keypair
7. import the new MOK with `mokutil`
8. tell you to reboot and complete MOK enrollment manually

If local `MOK.der` / `MOK.priv` files exist, the fresh MOK flow asks for confirmation before replacing them, and moves old copies into:

```text
./backups/<timestamp>/
```

## Fresh MOK setup without full driver recovery

If you only want a new keypair and new enrollment attempt:

```bash
sudo ./scripts/20-create-or-enroll-mok.sh --fresh
```

## Reinstall driver without the rest of recovery

```bash
sudo ./scripts/15-install-nvidia-driver.sh --purge-reinstall
```

## Important Blackwell / RTX 50 note

For RTX 5070 Ti / Blackwell GPUs, Debian-packaged NVIDIA drivers may be too old on some Debian releases or snapshots. The scripts warn if the `nvidia-driver` apt candidate appears older than a likely Blackwell-capable branch.

These helpers only support **Debian package workflows**. If Debian packages are too old for your GPU, you may need a newer Debian package source or to wait for updated Debian packages.

## Version consistency checks

Diagnostics print installed and apt-candidate versions for key packages such as:
- `nvidia-driver`
- `nvidia-kernel-dkms`
- `nvidia-driver-libs`
- `nvidia-smi`
- `firmware-misc-nonfree`
- `dkms`
- `linux-headers-$(uname -r)`

This helps detect partial upgrades or package mismatches.

## Logs

Per-script logs:

```text
./logs/YYYYmmdd-HHMMSS-<script>.log
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

## Sources reflected in this project

Research for this project was based on current web/forum guidance including:

- Debian Wiki `NvidiaGraphicsDrivers` snippets indicating Secure Boot requires MOK enrollment and that Blackwell support may lag in Debian packages
- NVIDIA Developer Forums guidance on signing modules with MOK for Secure Boot
- Linux community reports about Debian/Trixie packaged NVIDIA versions being too old for Blackwell
