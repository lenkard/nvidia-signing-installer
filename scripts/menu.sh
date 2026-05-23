#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers/common.sh"

command_exists whiptail || die "whiptail is required. Run sudo ./scripts/10-install-debian-prereqs.sh first."

export NSI_SESSION_LOG="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-menu-session.log"
TITLE="nvidia-signing-installer"
BACKTITLE="Debian NVIDIA Secure Boot helper"

run_script() {
  local label="$1"
  shift
  local cmd=("$@")
  local tmp
  tmp="$(mktemp)"
  if "${cmd[@]}" >"$tmp" 2>&1; then
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --scrolltext --msgbox "$label completed.\n\nSummary log: $NSI_SESSION_LOG\n\n$(tail -n 25 "$tmp")" 24 90
  else
    whiptail --title "$TITLE" --backtitle "$BACKTITLE" --scrolltext --msgbox "$label failed.\n\nSummary log: $NSI_SESSION_LOG\n\n$(tail -n 40 "$tmp")" 24 90
  fi
  rm -f "$tmp"
}

confirm() {
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" --yesno "$1" 12 78
}

prompt_kernel() {
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" --inputbox "Enter target kernel version (example: 6.12.88+deb13-amd64)" 12 80 3>&1 1>&2 2>&3
}

show_help() {
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" --scrolltext --msgbox "Use this menu for Debian NVIDIA Secure Boot setup and recovery.\n\nRecommended flows:\n- First-time setup: 1 -> 2 -> 3 -> 4\n- If installed NVIDIA module files are corrupt: 8\n- Recovery after wrong MOK password or broken signing: 9 or 12\n- For a newly installed kernel: 13 (build/sign/verify for target kernel)\n- If the driver branch is too old for the GPU: 10 (switch to backports)\n- Diagnostics and verification also detect GPU/driver incompatibility and check whether nvidia-smi is installed\n\nManual firmware step always required after MOK import:\nReboot and complete MOK enrollment in the blue screen." 24 95
}

show_driver_too_old_help() {
  whiptail --title "$TITLE" --backtitle "$BACKTITLE" --scrolltext --msgbox "If the project reports: 'Packages installed successfully, but this driver branch does not support your GPU', the Debian stable branch is too old for your GPU.\n\nRecommended order:\n1. Try Debian backports first\n2. Re-run diagnostics and verification\n3. Only consider upstream/external NVIDIA packaging if Debian/backports still lacks support\n\nThe menu can run a backports switch helper automatically if selected." 22 95
}

while true; do
  choice=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" --menu "Choose an action" 28 105 18 \
    "1" "Diagnose current system" \
    "2" "Install Debian prerequisites" \
    "3" "Install Debian NVIDIA driver" \
    "4" "Create/import MOK (reuse existing keys)" \
    "5" "Fresh MOK setup (replace old key files after confirmation)" \
    "6" "Sign NVIDIA modules + rebuild initramfs" \
    "7" "Verify Secure Boot/NVIDIA state" \
    "8" "Repair broken installed NVIDIA module files" \
    "9" "Recovery: purge/reinstall driver + fresh MOK" \
    "10" "Remediation: switch NVIDIA packages to backports" \
    "11" "Remediation: show 'driver too old' help" \
    "12" "Guided recovery flow" \
    "13" "Target kernel: build + sign + depmod + initramfs + verify" \
    "14" "Target kernel: verify only" \
    "15" "Guided first-time flow" \
    "16" "Help" \
    "17" "Exit" 3>&1 1>&2 2>&3) || exit 0

  case "$choice" in
    1) run_script "Diagnostics" "$PROJECT_DIR/scripts/00-diagnose.sh" ;;
    2) run_script "Install prerequisites" run_as_root "$PROJECT_DIR/scripts/10-install-debian-prereqs.sh" ;;
    3)
      if confirm "Install Debian-packaged NVIDIA driver now?"; then
        run_script "Install NVIDIA driver" run_as_root "$PROJECT_DIR/scripts/15-install-nvidia-driver.sh"
      fi
      ;;
    4)
      if confirm "Import/re-import MOK using existing keys if present?"; then
        run_script "Create/import MOK" run_as_root "$PROJECT_DIR/scripts/20-create-or-enroll-mok.sh"
      fi
      ;;
    5)
      if confirm "Fresh MOK setup will replace old local key files after script confirmation. Continue?"; then
        run_script "Fresh MOK setup" run_as_root "$PROJECT_DIR/scripts/20-create-or-enroll-mok.sh" --fresh
      fi
      ;;
    6)
      if confirm "Sign NVIDIA modules and rebuild initramfs now?"; then
        run_script "Sign NVIDIA modules" run_as_root "$PROJECT_DIR/scripts/30-sign-nvidia-modules.sh"
      fi
      ;;
    7) run_script "Verify state" "$PROJECT_DIR/scripts/40-verify.sh" ;;
    8)
      if confirm "Repair broken installed NVIDIA module files, rebuild DKMS, depmod, and initramfs now?"; then
        run_script "Repair installed NVIDIA modules" run_as_root "$PROJECT_DIR/scripts/27-repair-installed-modules.sh"
      fi
      ;;
    9)
      if confirm "Recovery will purge and reinstall Debian NVIDIA packages, repair installed module files, then create a fresh MOK import. Continue?"; then
        run_script "Recovery" run_as_root "$PROJECT_DIR/scripts/25-recover.sh"
      fi
      ;;
    10)
      if confirm "Switch NVIDIA packages to Debian backports now?"; then
        run_script "Switch to backports" run_as_root "$PROJECT_DIR/scripts/16-switch-to-backports.sh"
      fi
      ;;
    11) show_driver_too_old_help ;;
    12)
      if confirm "Guided recovery will purge/reinstall NVIDIA, repair installed modules, and start fresh MOK setup. Continue?"; then
        run_script "Guided recovery flow" "$PROJECT_DIR/scripts/run-recovery.sh"
      fi
      ;;
    13)
      kernel="$(prompt_kernel)" || continue
      mode=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" --menu "Signing mode for $kernel" 14 80 3 \
        "signed" "Build and sign (requires MOK files)" \
        "unsigned" "Build without signing" \
        "cancel" "Cancel" 3>&1 1>&2 2>&3) || continue
      case "$mode" in
        signed) run_script "Target kernel build/sign" run_as_root "$PROJECT_DIR/scripts/50-build-target-kernel.sh" "$kernel" ;;
        unsigned) run_script "Target kernel build unsigned" run_as_root "$PROJECT_DIR/scripts/50-build-target-kernel.sh" "$kernel" --allow-unsigned ;;
        *) ;;
      esac
      ;;
    14)
      kernel="$(prompt_kernel)" || continue
      mode=$(whiptail --title "$TITLE" --backtitle "$BACKTITLE" --menu "Verification mode for $kernel" 14 80 3 \
        "signed" "Require signer fields" \
        "unsigned" "Allow unsigned modules" \
        "cancel" "Cancel" 3>&1 1>&2 2>&3) || continue
      case "$mode" in
        signed) run_script "Target kernel verify" "$PROJECT_DIR/scripts/51-verify-target-kernel.sh" "$kernel" ;;
        unsigned) run_script "Target kernel verify unsigned-ok" "$PROJECT_DIR/scripts/51-verify-target-kernel.sh" "$kernel" --unsigned-ok ;;
        *) ;;
      esac
      ;;
    15) run_script "Guided first-time flow" "$PROJECT_DIR/scripts/run-all.sh" ;;
    16) show_help ;;
    17) exit 0 ;;
  esac
done
