# nvidia-signing-installer

Safe Debian-focused diagnostics and Secure Boot / MOK signing helpers for NVIDIA drivers.

## Goals

- Diagnose common NVIDIA-on-Debian failures
- Detect Secure Boot blocking of NVIDIA modules
- Create and enroll a MOK key for module signing
- Sign NVIDIA kernel modules for the current kernel
- Keep timestamped logs
- Warn when Debian-packaged NVIDIA support is likely too old for RTX 50 / Blackwell GPUs

## Target environment

- Debian 12/13, especially Debian Trixie
- Debian-packaged NVIDIA drivers
- Secure Boot enabled systems
- Reusable on similar Debian/NVIDIA systems

## Safety model

- Safe steps can be performed automatically
- Riskier or manual steps are clearly separated
- The scripts do **not** disable Secure Boot
- The scripts do **not** use NVIDIA's `.run` installer
- The scripts do **not** silently change BIOS/UEFI settings

## Layout

- `scripts/00-diagnose.sh` — collect system/NVIDIA/Secure Boot diagnostics
- `scripts/10-install-debian-prereqs.sh` — install Debian package prerequisites
- `scripts/15-install-nvidia-driver.sh` — optionally install Debian-packaged NVIDIA driver
- `scripts/20-create-or-enroll-mok.sh` — create a MOK key and import it with `mokutil`
- `scripts/30-sign-nvidia-modules.sh` — sign NVIDIA modules for the current kernel
- `scripts/40-verify.sh` — verify module files, signatures, and runtime state
- `scripts/run-all.sh` — guided wrapper for the common flow
- `helpers/common.sh` — shared helpers

## Typical usage

### 1) Diagnose first

```bash
cd nvidia-signing-installer
./scripts/00-diagnose.sh
```

### 2) Install prerequisites

```bash
sudo ./scripts/10-install-debian-prereqs.sh
```

### 3) Optionally install the Debian-packaged NVIDIA driver

```bash
sudo ./scripts/15-install-nvidia-driver.sh
```

### 4) Create and enroll MOK

```bash
sudo ./scripts/20-create-or-enroll-mok.sh
```

Then reboot and complete the MOK enrollment in the blue UEFI/MOK screen.

### 5) Sign NVIDIA modules

After MOK enrollment and booting back into Linux:

```bash
sudo ./scripts/30-sign-nvidia-modules.sh
sudo ./scripts/40-verify.sh
```

### 6) Or use the wrapper

```bash
./scripts/run-all.sh
```

## Important Blackwell / RTX 50 note

For RTX 5070 Ti / Blackwell GPUs, Debian-packaged NVIDIA drivers may be too old on some Debian releases or snapshots. These scripts will warn if the apt candidate is below the likely support threshold.

They only support **Debian package workflows**. If Debian packages are too old for your GPU, you may need a newer Debian package source or to wait for updated Debian packages.

## Logs

Each script writes logs to:

```text
./logs/YYYYmmdd-HHMMSS-<script>.log
```

## Manual steps you must do yourself

- Reboot after `mokutil --import`
- Complete MOK enrollment in firmware UI
- BIOS changes like PCIe Gen4 / iGPU / ReBAR / Secure Boot policy

## Rollback / cleanup

- Remove the generated MOK files if desired:

```bash
rm -f MOK.der MOK.priv
```

- To stop using the proprietary driver, purge it with apt as appropriate for your system.
- If Secure Boot remains enabled and unsigned NVIDIA modules are rebuilt later, you must re-sign them.

## Sources reflected in this project

Research for this project was based on current web/forum guidance including:

- Debian Wiki `NvidiaGraphicsDrivers` snippets indicating Secure Boot requires MOK enrollment and that Blackwell support may lag in Debian packages
- NVIDIA Developer Forums guidance on signing modules with MOK for Secure Boot
- Linux community reports about Debian/Trixie packaged NVIDIA versions being too old for Blackwell

