#!/usr/bin/env bash
# macvm-direct-boot.sh — converteste un VM bundle macvm existent la
# direct Linux kernel boot (VZLinuxBootLoader), ocolind UEFI + bootloader.
#
# De ce? Apple Virtualization.framework are edge cases pe aarch64 UEFI
# unde handoff-ul bootloader → kernel se blocheaza la "Loading kernel".
# Direct boot ocoleste intregul EFI path.
#
# Folosire:
#   ./scripts/macvm-direct-boot.sh [bundle-name]     # default: carpatos
#
# Necesita suportul .linuxKernel bootloader in MacVMCore (commit dupa
# fix-ul initial al security scope).
set -euo pipefail

BUNDLE_NAME="${1:-carpatos}"
ARCH="aarch64"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_SRC="$ROOT/kernel/build/$ARCH/vmlinuz"
INITRD_SRC="$ROOT/initramfs/build/$ARCH/initramfs.cpio.gz"

# Locatia bundle-ului in sandbox-ul aplicatiei MacVM
MACVM_DATA="$HOME/Library/Containers/dev.cpopescu.MacVM/Data/Library/Application Support/MacVM/VMs"
BUNDLE="$MACVM_DATA/$BUNDLE_NAME.macvm"
CONFIG="$BUNDLE/config.json"

[[ -f "$KERNEL_SRC" ]]  || { echo "EROARE: lipseste $KERNEL_SRC (ruleaza 'make ARCH=aarch64 kernel')" >&2; exit 1; }
[[ -f "$INITRD_SRC" ]]  || { echo "EROARE: lipseste $INITRD_SRC (ruleaza 'make ARCH=aarch64 initramfs')" >&2; exit 1; }
[[ -d "$BUNDLE" ]]      || { echo "EROARE: lipseste bundle-ul $BUNDLE — creeaza VM 'carpatos' in MacVM mai intai" >&2; exit 1; }
[[ -f "$CONFIG" ]]      || { echo "EROARE: lipseste $CONFIG" >&2; exit 1; }

echo "==> Copiez vmlinuz + initramfs in bundle-ul $BUNDLE_NAME"
cp "$KERNEL_SRC"  "$BUNDLE/vmlinuz"
cp "$INITRD_SRC"  "$BUNDLE/initramfs.cpio.gz"

# Commandline pentru kernel: aarch64 Apple Vz expune hvc0 (virtio-console,
# conectat la serial.log prin VZVirtioConsoleDeviceSerialPortConfiguration).
# Kernel Linux alege ULTIMUL console= ca default (/dev/console target), asa
# ca lasam doar hvc0 — init-ul si msh vor scrie/citi prin serial.log.
# Framebuffer (tty0) apare oricum pentru cine urmareste fereastra VM.
CMDLINE="console=hvc0 console=tty1 rdinit=/init"

echo "==> Rescriu config.json pentru direct Linux boot"
# Citesc id + setari existente si le pastrez, schimb doar bootloader +
# path-urile kernel/initrd si scot isoPath.
python3 - "$CONFIG" "$CMDLINE" <<'PY'
import json, sys, pathlib
cfg_path, cmdline = sys.argv[1], sys.argv[2]
cfg = json.loads(pathlib.Path(cfg_path).read_text())
bundle_dir = pathlib.Path(cfg_path).parent
cfg["bootloader"] = "linuxKernel"
cfg["kernelPath"] = "file://" + str(bundle_dir / "vmlinuz")
cfg["initrdPath"] = "file://" + str(bundle_dir / "initramfs.cpio.gz")
cfg["kernelCommandLine"] = cmdline
# ISO nu mai e necesar — initramfs are tot ce trebuie
cfg.pop("isoPath", None)
pathlib.Path(cfg_path).write_text(json.dumps(cfg, indent=2, sort_keys=True))
PY

echo ""
echo "==> Gata! Bundle-ul '$BUNDLE_NAME' e acum configurat pentru direct Linux boot."
echo "   kernel:  $BUNDLE/vmlinuz"
echo "   initrd:  $BUNDLE/initramfs.cpio.gz"
echo "   cmdline: $CMDLINE"
echo ""
echo "Reporneste aplicatia MacVM si apasa Start pe '$BUNDLE_NAME'."
