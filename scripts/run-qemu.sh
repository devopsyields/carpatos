#!/usr/bin/env bash
# run-qemu.sh — Rulare CarpatOS in QEMU
#
# Moduri:
#   direct  — boot direct kernel+initramfs (rapid, pentru iteratie)
#   iso     — boot din ISO (testare calea completa Limine -> kernel)
#   uefi    — boot ISO in modul UEFI (necesita OVMF)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-direct}"

KERNEL="$ROOT/kernel/build/vmlinuz"
INITRAMFS="$ROOT/initramfs/build/initramfs.cpio.gz"
ISO="$ROOT/build/carpatos.iso"

# Comun
QEMU_COMMON=(
    -m 512M
    -cpu qemu64
    -smp 2
    -no-reboot
    -serial mon:stdio
    -nographic
)

case "$MODE" in
    direct)
        [[ -f "$KERNEL" ]] || { echo "Lipseste $KERNEL"; exit 1; }
        [[ -f "$INITRAMFS" ]] || { echo "Lipseste $INITRAMFS"; exit 1; }
        echo "==> Boot direct in QEMU (Ctrl+A X pentru iesire)"
        exec qemu-system-x86_64 \
            "${QEMU_COMMON[@]}" \
            -kernel "$KERNEL" \
            -initrd "$INITRAMFS" \
            -append "console=ttyS0,115200 rdinit=/init quiet"
        ;;
    iso)
        [[ -f "$ISO" ]] || { echo "Lipseste $ISO (ruleaza build-iso.sh)"; exit 1; }
        echo "==> Boot ISO in QEMU (BIOS, Ctrl+A X pentru iesire)"
        exec qemu-system-x86_64 \
            "${QEMU_COMMON[@]}" \
            -cdrom "$ISO" \
            -boot d
        ;;
    uefi)
        [[ -f "$ISO" ]] || { echo "Lipseste $ISO"; exit 1; }
        OVMF="${OVMF:-/usr/share/ovmf/OVMF.fd}"
        [[ -f "$OVMF" ]] || { echo "Lipseste OVMF la $OVMF"; exit 1; }
        echo "==> Boot ISO in QEMU (UEFI, Ctrl+A X pentru iesire)"
        exec qemu-system-x86_64 \
            "${QEMU_COMMON[@]}" \
            -bios "$OVMF" \
            -cdrom "$ISO" \
            -boot d
        ;;
    *)
        echo "Folosire: $0 [direct|iso|uefi]"
        exit 1
        ;;
esac
