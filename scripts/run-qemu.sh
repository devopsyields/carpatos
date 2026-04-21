#!/usr/bin/env bash
# run-qemu.sh — Rulare CarpatOS in QEMU (multi-arch)
#
# Folosire:
#   ./scripts/run-qemu.sh <arch> <mod>
#     arch: x86_64 | aarch64
#     mod : direct | iso | uefi
#
# Iesire QEMU: Ctrl+A apoi X
set -euo pipefail

ARCH="${1:-x86_64}"
MODE="${2:-direct}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="$ROOT/kernel/build/$ARCH/vmlinuz"
INITRAMFS="$ROOT/initramfs/build/$ARCH/initramfs.cpio.gz"
ISO="$ROOT/build/$ARCH/carpatos-$ARCH.iso"

case "$ARCH" in
    x86_64)
        QEMU=qemu-system-x86_64
        QEMU_COMMON=(-m 512M -cpu qemu64 -smp 2 -no-reboot -serial mon:stdio -nographic)
        CMDLINE_DIRECT="console=ttyS0,115200 rdinit=/init quiet"
        OVMF="${OVMF:-/opt/ovmf.fd}"
        [[ -f "$OVMF" ]] || OVMF="/usr/share/ovmf/OVMF.fd"
        ;;
    aarch64)
        QEMU=qemu-system-aarch64
        QEMU_COMMON=(-machine virt -cpu cortex-a72 -m 512M -smp 2 -no-reboot -serial mon:stdio -nographic)
        CMDLINE_DIRECT="console=ttyAMA0,115200 rdinit=/init"
        AAVMF_CODE="${AAVMF_CODE:-/opt/aavmf-code.fd}"
        AAVMF_VARS="${AAVMF_VARS:-/opt/aavmf-vars.fd}"
        [[ -f "$AAVMF_CODE" ]] || AAVMF_CODE="/usr/share/AAVMF/AAVMF_CODE.fd"
        [[ -f "$AAVMF_VARS" ]] || AAVMF_VARS="/usr/share/AAVMF/AAVMF_VARS.fd"
        ;;
    *)
        echo "EROARE: ARCH necunoscut: $ARCH (suportat: x86_64, aarch64)" >&2
        exit 1
        ;;
esac

# Helper: copie writable a AAVMF_VARS pentru pflash
arm_pflash_args() {
    local vars_copy
    vars_copy="$(mktemp -t aavmf-vars-XXXXXX.fd)"
    cp "$AAVMF_VARS" "$vars_copy"
    echo "-drive if=pflash,format=raw,readonly=on,file=$AAVMF_CODE -drive if=pflash,format=raw,file=$vars_copy"
}

case "$MODE" in
    direct)
        [[ -f "$KERNEL" ]]    || { echo "Lipseste $KERNEL" >&2; exit 1; }
        [[ -f "$INITRAMFS" ]] || { echo "Lipseste $INITRAMFS" >&2; exit 1; }
        echo "==> Boot direct $ARCH (Ctrl+A X pentru iesire)"
        exec $QEMU "${QEMU_COMMON[@]}" \
            -kernel "$KERNEL" -initrd "$INITRAMFS" \
            -append "$CMDLINE_DIRECT"
        ;;
    iso)
        [[ -f "$ISO" ]] || { echo "Lipseste $ISO (ruleaza build-iso.sh $ARCH)" >&2; exit 1; }
        if [[ "$ARCH" == "x86_64" ]]; then
            echo "==> Boot ISO $ARCH (BIOS, Ctrl+A X)"
            exec $QEMU "${QEMU_COMMON[@]}" -cdrom "$ISO" -boot d
        else
            echo "==> Boot ISO $ARCH (UEFI obligatoriu pe aarch64, Ctrl+A X)"
            # Pe aarch64 nu exista BIOS legacy — direct UEFI
            # shellcheck disable=SC2046
            exec $QEMU "${QEMU_COMMON[@]}" $(arm_pflash_args) -cdrom "$ISO" -boot d
        fi
        ;;
    uefi)
        [[ -f "$ISO" ]] || { echo "Lipseste $ISO" >&2; exit 1; }
        if [[ "$ARCH" == "x86_64" ]]; then
            [[ -f "$OVMF" ]] || { echo "Lipseste OVMF la $OVMF" >&2; exit 1; }
            echo "==> Boot ISO $ARCH (UEFI/OVMF, Ctrl+A X)"
            exec $QEMU "${QEMU_COMMON[@]}" -bios "$OVMF" -cdrom "$ISO" -boot d
        else
            [[ -f "$AAVMF_CODE" && -f "$AAVMF_VARS" ]] || \
                { echo "Lipseste AAVMF (code=$AAVMF_CODE vars=$AAVMF_VARS)" >&2; exit 1; }
            echo "==> Boot ISO $ARCH (UEFI/AAVMF, Ctrl+A X)"
            # shellcheck disable=SC2046
            exec $QEMU "${QEMU_COMMON[@]}" $(arm_pflash_args) -cdrom "$ISO" -boot d
        fi
        ;;
    *)
        echo "Folosire: $0 <x86_64|aarch64> <direct|iso|uefi>" >&2
        exit 1
        ;;
esac
