# nvidia-signing-installer

Safe Debian-focused diagnostics, Secure Boot / MOK signing helpers, recovery helpers, and a terminal menu for NVIDIA drivers.

## Goals

- Diagnose common NVIDIA-on-Debian failures
- Detect Secure Boot blocking of NVIDIA modules
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

- `scripts/00-diagnose.sh` — collect system/NVIDIA/Secure Boot diagnostics
- `scripts/10-install-debian-prereqs.sh` — install Debian prerequisites, including `whiptail`
- `scripts/15-install-nvidia-driver.sh` — install Debian-packaged NVIDIA driver, or purge+reinstall
- `scripts/20-create-or-enroll-mok.sh` — create/import MOK; supports `--fresh`
- `scripts/25-recover.sh` — recovery flow: purge/reinstall driver + fresh MOK setup
- `scripts/30-sign-nvidia-modules.sh` — sign NVIDIA modules for the current kernel and rebuild initramfs
- `scripts/40-verify.sh` — verify module files, signatures, and runtime state
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
- full recovery flow

The menu writes a summary log under `logs/` and each called script still writes its own log too.

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

## Recovery usage

If you entered the wrong MOK password or want to restart signing from scratch:

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
4. create a fresh local MOK keypair
5. import the new MOK with `mokutil`
6. tell you to reboot and complete MOK enrollment manually

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
