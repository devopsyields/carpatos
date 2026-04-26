#!/usr/bin/env bash
# build-iso-carpatos.sh
#
# Construieste ISO-ul CarpatOS Desktop pornind de la Ubuntu Desktop 24.04 LTS
# arm64 si aplicand overlay-ul CarpatOS (pachete carpatos-* + setari finale).
#
# Strategie:
#   1. Descarc / cache ISO Ubuntu Desktop arm64
#   2. Extrag continut ISO cu xorriso
#   3. Unsquashfs la rootfs (filesystem.squashfs)
#   4. Aplic pachete carpatos-* peste rootfs cu cpm CPM_ROOT=...
#   5. chroot in rootfs si rulez hooks (glib-compile-schemas,
#      plymouth-set-default-theme, update-initramfs)
#   6. Pun cpm binar + /etc/cpm/repo.url
#   7. Repac squashfs si regenerez md5sum.txt
#   8. Rebuild ISO cu xorriso (UEFI-only pentru arm64)
#
# Cerinte:
#   - rulat pe Linux arm64 (rootfs-ul e arm64; chroot necesita binarele
#     native) sau in container privileged cu binfmt qemu-user-static
#   - sudo
#   - xorriso, squashfs-tools, util-linux, coreutils
#
# Output: build/iso/carpatos-desktop-1.0-arm64.iso
set -euo pipefail

# ---- config ----
UBUNTU_RELEASE="${UBUNTU_RELEASE:-24.04.4}"
UBUNTU_ARH="${UBUNTU_ARH:-arm64}"
UBUNTU_ISO_URL="${UBUNTU_ISO_URL:-https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-${UBUNTU_RELEASE}-desktop-${UBUNTU_ARH}.iso}"

CARPATOS_VERSION="${CARPATOS_VERSION:-1.0}"
CARPATOS_VOLID="${CARPATOS_VOLID:-CarpatOS Desktop ${CARPATOS_VERSION} ${UBUNTU_ARH}}"
CPM_REPO_URL="${CPM_REPO_URL:-https://github.com/devopsyields/carpatos-repo/releases/download/v0.2-essentials}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$ROOT/build/iso}"
WORK="$BUILD/work"
DOWNLOAD="$BUILD/download"
PKG_BUILD="$BUILD/packages"
OUT="$BUILD/carpatos-desktop-${CARPATOS_VERSION}-${UBUNTU_ARH}.iso"

CPM_HOST="$ROOT/initramfs/src/cpm/cpm_host"

CARPATOS_PACKAGES=(
    carpatos-os-release
    carpatos-banner
    carpatos-wallpapers
    carpatos-gnome-defaults
    carpatos-plymouth-theme
)

# ---- helpers ----
info()  { printf "\033[1;36m[info]\033[0m %s\n" "$*" >&2; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$*" >&2; }
fatal() { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || fatal "lipseste binarul: $1"
}

need_sudo() {
    if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        fatal "scriptul are nevoie de sudo (extragere/repacking squashfs)"
    fi
}

# ---- preflight ----
preflight() {
    info "preflight: verific dependentele"
    for t in xorriso unsquashfs mksquashfs curl; do need "$t"; done
    [ -x "$CPM_HOST" ] || fatal "lipseste $CPM_HOST (compileaza cu make ARCH=aarch64)"
    need_sudo
    mkdir -p "$BUILD" "$WORK" "$DOWNLOAD" "$PKG_BUILD"
}

# ---- 1. download Ubuntu ISO ----
descarca_ubuntu() {
    local iso="$DOWNLOAD/$(basename "$UBUNTU_ISO_URL")"
    if [ -f "$iso" ]; then
        info "[1/8] ISO Ubuntu deja descarcat: $iso"
    else
        info "[1/8] Descarc Ubuntu ISO -> $iso"
        curl -fL --progress-bar -o "$iso.part" "$UBUNTU_ISO_URL"
        mv "$iso.part" "$iso"
    fi
    echo "$iso"
}

# ---- 2. extract ISO ----
extrage_iso() {
    local iso="$1"
    local extract="$WORK/iso-extract"
    if [ -d "$extract" ] && [ -n "$(ls -A "$extract" 2>/dev/null)" ]; then
        info "[2/8] ISO deja extras la $extract (reuse)"
    else
        info "[2/8] Extrag ISO -> $extract"
        rm -rf "$extract"
        mkdir -p "$extract"
        xorriso -osirrox on -indev "$iso" -extract / "$extract" 2>&1 | tail -5
    fi
    echo "$extract"
}

# ---- 3. localize filesystem.squashfs ----
gaseste_squashfs() {
    local extract="$1"
    for cand in casper/filesystem.squashfs casper/minimal.squashfs \
                live/filesystem.squashfs install/filesystem.squashfs; do
        if [ -f "$extract/$cand" ]; then
            echo "$extract/$cand"
            return
        fi
    done
    fatal "nu gasesc filesystem.squashfs in ISO"
}

# ---- 4. unsquashfs rootfs ----
extrage_rootfs() {
    local sqfs="$1"
    local rootfs="$WORK/rootfs"
    if [ -d "$rootfs" ] && [ -n "$(sudo ls -A "$rootfs" 2>/dev/null)" ]; then
        info "[3/8] rootfs deja extras la $rootfs (reuse)"
    else
        info "[3/8] Unsquashfs $(basename "$sqfs") -> $rootfs"
        sudo rm -rf "$rootfs"
        sudo unsquashfs -d "$rootfs" "$sqfs" >/dev/null
    fi
    echo "$rootfs"
}

# ---- 5. construieste pachete carpatos-* ----
construieste_pachete() {
    info "[4/8] Construiesc pachete carpatos-*"
    for pkg in "${CARPATOS_PACKAGES[@]}"; do
        local out="$PKG_BUILD/${pkg}.cpm"
        if [ -f "$out" ]; then
            info "  $pkg.cpm exista (reuse)"
        else
            info "  build $pkg"
            "$CPM_HOST" build "$ROOT/packages/$pkg" -o "$out" >/dev/null
        fi
    done
}

# ---- 6. aplic pachete peste rootfs ----
aplica_overlay() {
    local rootfs="$1"
    info "[5/8] Aplic pachete carpatos-* peste rootfs"
    for pkg in "${CARPATOS_PACKAGES[@]}"; do
        info "  install $pkg"
        sudo CPM_ROOT="$rootfs" "$CPM_HOST" local "$PKG_BUILD/${pkg}.cpm" \
            2>&1 | grep -v "^Instalez " || true
    done

    info "  scriu /etc/cpm/repo.url -> $CPM_REPO_URL"
    sudo install -d "$rootfs/etc/cpm"
    echo "$CPM_REPO_URL" | sudo tee "$rootfs/etc/cpm/repo.url" >/dev/null

    info "  instalez binarul cpm la /usr/local/bin/cpm"
    sudo install -m 0755 "$CPM_HOST" "$rootfs/usr/local/bin/cpm"
}

# ---- 7. ruleaza hooks finale in chroot ----
ruleaza_hooks() {
    local rootfs="$1"
    info "[6/8] Hooks finale in chroot"

    # Mount-uri necesare pentru chroot
    for m in proc sys dev dev/pts; do
        sudo mkdir -p "$rootfs/$m"
    done
    sudo mount -t proc  proc      "$rootfs/proc"
    sudo mount -t sysfs sysfs     "$rootfs/sys"
    sudo mount --bind   /dev      "$rootfs/dev"
    sudo mount --bind   /dev/pts  "$rootfs/dev/pts"
    trap "
        sudo umount -lf '$rootfs/dev/pts' 2>/dev/null || true
        sudo umount -lf '$rootfs/dev'     2>/dev/null || true
        sudo umount -lf '$rootfs/sys'     2>/dev/null || true
        sudo umount -lf '$rootfs/proc'    2>/dev/null || true
    " EXIT

    sudo chroot "$rootfs" /bin/bash -eu <<'CHROOT_EOF'
        export DEBIAN_FRONTEND=noninteractive

        echo "[chroot] glib-compile-schemas"
        if [ -d /usr/share/glib-2.0/schemas ]; then
            glib-compile-schemas /usr/share/glib-2.0/schemas/ || true
        fi

        echo "[chroot] plymouth-set-default-theme carpatos"
        if command -v plymouth-set-default-theme >/dev/null; then
            plymouth-set-default-theme -R carpatos || true
        fi

        echo "[chroot] update-initramfs (sa includa noua tema plymouth)"
        if command -v update-initramfs >/dev/null; then
            update-initramfs -u -k all || true
        fi

        echo "[chroot] hostname implicit"
        echo "carpatos" > /etc/hostname

        echo "[chroot] terminat"
CHROOT_EOF

    sudo umount -lf "$rootfs/dev/pts" || true
    sudo umount -lf "$rootfs/dev"     || true
    sudo umount -lf "$rootfs/sys"     || true
    sudo umount -lf "$rootfs/proc"    || true
    trap - EXIT
}

# ---- 8. repack squashfs + checksums + ISO ----
repack_squashfs() {
    local sqfs="$1"
    local rootfs="$2"
    info "[7/8] Repac squashfs (xz, poate dura cateva minute)"
    sudo rm -f "$sqfs"
    sudo mksquashfs "$rootfs" "$sqfs" -comp xz -b 1M -no-progress 2>&1 | tail -3
}

regenereaza_checksums() {
    local extract="$1"
    info "  regenerez md5sum.txt"
    (
        cd "$extract"
        sudo find . -type f ! -name md5sum.txt ! -path './isolinux/*' \
            -exec md5sum {} + | sudo tee md5sum.txt >/dev/null
    )
}

construieste_iso() {
    local extract="$1"
    info "[8/8] Construiesc ISO final -> $OUT"

    # Pentru arm64 doar UEFI. xorriso reconstruieste din extract dir +
    # imaginea EFI deja prezenta in /boot/grub/efi.img.
    local efi_img="$extract/boot/grub/efi.img"
    if [ ! -f "$efi_img" ]; then
        # Unele ISO Ubuntu au efi.img sub /EFI/boot/ direct
        efi_img="$(find "$extract" -name efi.img | head -1)"
    fi
    [ -f "$efi_img" ] || fatal "nu gasesc efi.img in ISO extras"

    sudo xorriso -as mkisofs \
        -V "$CARPATOS_VOLID" \
        -o "$OUT" \
        -J -joliet-long -r \
        -e "$(basename "$efi_img")" -no-emul-boot \
        -append_partition 2 0xef "$efi_img" \
        -partition_cyl_align all \
        "$extract" 2>&1 | tail -5

    sudo chown "$(id -u):$(id -g)" "$OUT"
    info "ISO gata: $OUT ($(du -h "$OUT" | cut -f1))"
}

# ---- main ----
preflight
ISO=$(descarca_ubuntu)
EXTRACT=$(extrage_iso "$ISO")
SQFS=$(gaseste_squashfs "$EXTRACT")
ROOTFS=$(extrage_rootfs "$SQFS")
construieste_pachete
aplica_overlay "$ROOTFS"
ruleaza_hooks "$ROOTFS"
repack_squashfs "$SQFS" "$ROOTFS"
regenereaza_checksums "$EXTRACT"
construieste_iso "$EXTRACT"

info "Gata. Testeaza in QEMU/UTM cu:"
info "  qemu-system-aarch64 -M virt -cpu cortex-a72 -m 4G \\"
info "    -bios /usr/share/AAVMF/AAVMF_CODE.fd \\"
info "    -cdrom $OUT"
