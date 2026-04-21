#!/usr/bin/env bash
# build-iso.sh — Genereaza imagine ISO bootabila CarpatOS (multi-arch)
#
# Folosire:
#   ./scripts/build-iso.sh x86_64    # BIOS + UEFI hibrid
#   ./scripts/build-iso.sh aarch64   # UEFI-only (BOOTAA64.EFI)
#
# Cerinte runtime: xorriso, Limine instalat in /opt/limine sau $LIMINE_DIR
set -euo pipefail

ARCH="${1:-x86_64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/$ARCH"
ISO_ROOT="$BUILD/iso"
ISO_OUT="$BUILD/carpatos-$ARCH.iso"

LIMINE_DIR="${LIMINE_DIR:-/opt/limine}"

KERNEL="$ROOT/kernel/build/$ARCH/vmlinuz"
INITRAMFS="$ROOT/initramfs/build/$ARCH/initramfs.cpio.gz"

# Verificari
[[ -f "$KERNEL" ]]    || { echo "EROARE: lipseste $KERNEL (ruleaza 'make -C kernel ARCH=$ARCH')" >&2; exit 1; }
[[ -f "$INITRAMFS" ]] || { echo "EROARE: lipseste $INITRAMFS (ruleaza 'make -C initramfs ARCH=$ARCH')" >&2; exit 1; }
[[ -d "$LIMINE_DIR" ]] || { echo "EROARE: Limine nu exista la $LIMINE_DIR" >&2; exit 1; }

case "$ARCH" in
    x86_64)
        EFI_BIN="BOOTX64.EFI"
        EFI_TARGET="BOOTX64.EFI"
        ;;
    aarch64)
        EFI_BIN="BOOTAA64.EFI"
        EFI_TARGET="BOOTAA64.EFI"
        ;;
    *)
        echo "EROARE: ARCH necunoscut: $ARCH (suportat: x86_64, aarch64)" >&2
        exit 1
        ;;
esac

[[ -f "$LIMINE_DIR/$EFI_BIN" ]] || { echo "EROARE: lipseste $LIMINE_DIR/$EFI_BIN" >&2; exit 1; }

echo "==> Construiesc structura ISO pentru $ARCH in $ISO_ROOT"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot/limine"
mkdir -p "$ISO_ROOT/EFI/BOOT"

cp "$KERNEL"    "$ISO_ROOT/boot/vmlinuz"
cp "$INITRAMFS" "$ISO_ROOT/boot/initramfs.cpio.gz"
cp "$ROOT/boot/limine.conf" "$ISO_ROOT/boot/limine/limine.conf"
cp "$LIMINE_DIR/$EFI_BIN"   "$ISO_ROOT/EFI/BOOT/$EFI_TARGET"

if [[ "$ARCH" == "x86_64" ]]; then
    # ISO hibrid BIOS+UEFI
    cp "$LIMINE_DIR/limine-bios.sys"     "$ISO_ROOT/boot/limine/"
    cp "$LIMINE_DIR/limine-bios-cd.bin"  "$ISO_ROOT/boot/limine/"
    cp "$LIMINE_DIR/limine-uefi-cd.bin"  "$ISO_ROOT/boot/limine/"

    echo "==> Generez ISO hibrid BIOS+UEFI cu xorriso"
    xorriso -as mkisofs \
        -R -r -J \
        -b boot/limine/limine-bios-cd.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -hfsplus -apm-block-size 2048 \
        --efi-boot boot/limine/limine-uefi-cd.bin \
        -efi-boot-part --efi-boot-image --protective-msdos-label \
        -V "CARPATOS" \
        "$ISO_ROOT" -o "$ISO_OUT"

    echo "==> Instalez MBR boot Limine (BIOS)"
    "$LIMINE_DIR/limine" bios-install "$ISO_OUT"
else
    # aarch64: UEFI-only (Limine pe aarch64 nu suporta BIOS)
    cp "$LIMINE_DIR/limine-uefi-cd.bin"  "$ISO_ROOT/boot/limine/"

    echo "==> Generez ISO UEFI-only pentru aarch64 cu xorriso"
    xorriso -as mkisofs \
        -R -r -J \
        --efi-boot boot/limine/limine-uefi-cd.bin \
        -efi-boot-part --efi-boot-image --protective-msdos-label \
        -V "CARPATOS" \
        "$ISO_ROOT" -o "$ISO_OUT"
fi

echo ""
echo "==> Gata! ISO creat pentru $ARCH: $ISO_OUT"
ls -lh "$ISO_OUT"
