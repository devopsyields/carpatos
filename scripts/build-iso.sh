#!/usr/bin/env bash
# build-iso.sh — Genereaza imagine ISO bootabila CarpatOS (BIOS+UEFI)
#
# Cerinte runtime: xorriso, Limine instalat in /opt/limine sau $LIMINE_DIR
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ISO_ROOT="$BUILD/iso"
ISO_OUT="$BUILD/carpatos.iso"

LIMINE_DIR="${LIMINE_DIR:-/opt/limine}"

KERNEL="$ROOT/kernel/build/vmlinuz"
INITRAMFS="$ROOT/initramfs/build/initramfs.cpio.gz"

# Verific ca artefactele exista
if [[ ! -f "$KERNEL" ]]; then
    echo "EROARE: kernel-ul nu exista la $KERNEL" >&2
    echo "Ruleaza 'make -C kernel' intai." >&2
    exit 1
fi
if [[ ! -f "$INITRAMFS" ]]; then
    echo "EROARE: initramfs nu exista la $INITRAMFS" >&2
    echo "Ruleaza 'make -C initramfs' intai." >&2
    exit 1
fi
if [[ ! -d "$LIMINE_DIR" ]]; then
    echo "EROARE: Limine nu exista la $LIMINE_DIR" >&2
    echo "Seteaza LIMINE_DIR sau instaleaza in /opt/limine." >&2
    exit 1
fi

echo "==> Construiesc structura ISO in $ISO_ROOT"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot/limine"
mkdir -p "$ISO_ROOT/EFI/BOOT"

# Copiez kernel + initramfs in structura ISO
cp "$KERNEL"    "$ISO_ROOT/boot/vmlinuz"
cp "$INITRAMFS" "$ISO_ROOT/boot/initramfs.cpio.gz"

# Copiez fisierele Limine
cp "$ROOT/boot/limine.conf"              "$ISO_ROOT/boot/limine/limine.conf"
cp "$LIMINE_DIR/limine-bios.sys"         "$ISO_ROOT/boot/limine/"
cp "$LIMINE_DIR/limine-bios-cd.bin"      "$ISO_ROOT/boot/limine/"
cp "$LIMINE_DIR/limine-uefi-cd.bin"      "$ISO_ROOT/boot/limine/"
cp "$LIMINE_DIR/BOOTX64.EFI"             "$ISO_ROOT/EFI/BOOT/"

echo "==> Generez ISO hibrid cu xorriso"
xorriso -as mkisofs \
    -R -r -J \
    -b boot/limine/limine-bios-cd.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -hfsplus -apm-block-size 2048 \
    --efi-boot boot/limine/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    -V "CARPATOS" \
    "$ISO_ROOT" -o "$ISO_OUT"

# Fac ISO-ul bootabil BIOS prin Limine
echo "==> Instalez MBR boot Limine"
"$LIMINE_DIR/limine" bios-install "$ISO_OUT"

echo ""
echo "==> Gata! ISO creat: $ISO_OUT"
ls -lh "$ISO_OUT"
