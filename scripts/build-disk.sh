#!/usr/bin/env bash
# build-disk.sh — genereaza disk image raw GPT+ESP bootabil (aarch64 UEFI)
#
# Spre deosebire de ISO (care e detectat inconsistent de unele framework-uri
# de virtualizare, ex: Apple Virtualization pe Mac), un .img raw cu GPT si
# EFI System Partition FAT32 e recunoscut universal ca disc bootabil.
#
# Folosire:
#   ./scripts/build-disk.sh aarch64     # produce build/aarch64/carpatos-aarch64.img
#
# Cerinte runtime: sgdisk (gdisk), mformat+mcopy (mtools), dd
set -euo pipefail

ARCH="${1:-aarch64}"
case "$ARCH" in
    aarch64) EFI_BIN="BOOTAA64.EFI" ;;
    x86_64)  EFI_BIN="BOOTX64.EFI" ;;
    *) echo "EROARE: ARCH necunoscut: $ARCH" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/$ARCH"
DISK_OUT="$BUILD/carpatos-$ARCH.img"
ESP_IMG="$BUILD/esp-disk-$ARCH.img"
LIMINE_DIR="${LIMINE_DIR:-/opt/limine}"

KERNEL="$ROOT/kernel/build/$ARCH/vmlinuz"
INITRAMFS="$ROOT/initramfs/build/$ARCH/initramfs.cpio.gz"
LIMINE_CONF="$ROOT/boot/limine.conf"

[[ -f "$KERNEL" ]]    || { echo "EROARE: lipseste $KERNEL" >&2; exit 1; }
[[ -f "$INITRAMFS" ]] || { echo "EROARE: lipseste $INITRAMFS" >&2; exit 1; }
[[ -f "$LIMINE_DIR/$EFI_BIN" ]] || { echo "EROARE: lipseste $LIMINE_DIR/$EFI_BIN" >&2; exit 1; }

mkdir -p "$BUILD"

# 1) Construiesc ESP FAT32 (64 MB = amplu pentru kernel + initramfs + Limine)
ESP_SIZE_MB=64
echo "==> Construiesc ESP FAT32 (${ESP_SIZE_MB} MB)"
rm -f "$ESP_IMG"
dd if=/dev/zero of="$ESP_IMG" bs=1M count=$ESP_SIZE_MB status=none
mformat -i "$ESP_IMG" -F -v CARPATOS ::
mmd -i "$ESP_IMG" ::/EFI ::/EFI/BOOT ::/boot ::/boot/limine
mcopy -i "$ESP_IMG" "$LIMINE_DIR/$EFI_BIN" "::/EFI/BOOT/$EFI_BIN"
mcopy -i "$ESP_IMG" "$KERNEL"              "::/boot/vmlinuz"
mcopy -i "$ESP_IMG" "$INITRAMFS"           "::/boot/initramfs.cpio.gz"
mcopy -i "$ESP_IMG" "$LIMINE_CONF"         "::/boot/limine/limine.conf"

# 2) Construiesc disk image final: GPT + o partitie ESP care contine ESP-ul
#    Aloc un pic mai mult decat ESP pentru header/backup GPT (~1 MB overhead)
echo "==> Construiesc disk image GPT ($DISK_OUT)"
DISK_SIZE_MB=$((ESP_SIZE_MB + 2))
rm -f "$DISK_OUT"
dd if=/dev/zero of="$DISK_OUT" bs=1M count=$DISK_SIZE_MB status=none

# sgdisk: partitie 1, sectoare 2048..sfarsit-34, tip EFI System (EF00)
#   -n 1:2048:+${ESP_SIZE_MB}M     creeaza partitie 1 la offset 2048 sectoare
#   -t 1:ef00                       tip EFI System Partition
#   -c 1:"EFI System"               label
#   --hybrid-mbr nu e necesar pentru Apple Vz — doar GPT pur
sgdisk --zap-all "$DISK_OUT" >/dev/null
sgdisk -n "1:2048:+${ESP_SIZE_MB}M" -t 1:ef00 -c "1:EFI System" "$DISK_OUT" >/dev/null

# 3) Copiez ESP-ul la offset 2048 sectoare (1 MB)
echo "==> Copiez ESP in partitia 1 (offset 1 MB)"
dd if="$ESP_IMG" of="$DISK_OUT" bs=512 seek=2048 conv=notrunc status=none

rm -f "$ESP_IMG"

echo ""
echo "==> Gata! Disk image creat pentru $ARCH: $DISK_OUT"
ls -lh "$DISK_OUT"
echo ""
echo "Folosire cu Apple Virtualization:"
echo "  Atașează $DISK_OUT ca 'Primary disk' (virtio block, read-write)."
echo "  Firmware-ul EFI al VM-ului va gasi ESP-ul si va lansa Limine."
