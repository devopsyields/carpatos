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
    carpatos-gdm-theme
)

# Setat de need_sudo() la "sudo" sau "" (cand ruleaza ca root).
SUDO="sudo"

# ---- helpers ----
info()  { printf "\033[1;36m[info]\033[0m %s\n" "$*" >&2; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$*" >&2; }
fatal() { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || fatal "lipseste binarul: $1"
}

need_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif $SUDO -n true 2>/dev/null; then
        SUDO="sudo"
    else
        fatal "scriptul are nevoie de $SUDO (sau ruleaza ca root)"
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

# ---- 3. localize squashfs principal ----
# Ubuntu 24.04 desktop arm64 ISO are mai multe layere squashfs:
#   minimal.squashfs (1.6 GB) — baza completa, plus chestii ca dconf,
#     glib-compile-schemas, plymouth — TOT ce ne trebuie pentru hooks
#   minimal.standard.squashfs (460 MB) — overlay diff cu standard pkgs
#   minimal.standard.live.squashfs (925 MB) — overlay diff pentru live
#   minimal.<lang>.squashfs (16 MB) — language packs
# Modificam BASE-ul (minimal.squashfs) — overlay-ul carpatos se aplica la toate.
gaseste_squashfs() {
    local extract="$1"
    for cand in casper/minimal.squashfs casper/filesystem.squashfs \
                live/filesystem.squashfs install/filesystem.squashfs; do
        if [ -f "$extract/$cand" ]; then
            echo "$extract/$cand"
            return
        fi
    done
    fatal "nu gasesc squashfs principal in ISO"
}

# ---- 4. unsquashfs rootfs ----
# ATENTIE: rootfs-ul Linux contine fisiere cu xattrs + perechi de fisiere
# care difera doar prin case (ex: 'Sys' / 'sys' in perl). Pe Mac APFS via
# Docker bind mount asta esueaza. Pe Linux native sau intr-un volum Docker
# Linux ext4 merge.
# Override prin env ROOTFS_DIR — recomandata o cale in afara mount-ului host.
extrage_rootfs() {
    local sqfs="$1"
    local rootfs="${ROOTFS_DIR:-$WORK/rootfs}"
    if [ -d "$rootfs" ] && [ -n "$($SUDO ls -A "$rootfs" 2>/dev/null)" ]; then
        info "[3/8] rootfs deja extras la $rootfs (reuse)"
    else
        info "[3/8] Unsquashfs $(basename "$sqfs") -> $rootfs"
        $SUDO rm -rf "$rootfs"
        $SUDO mkdir -p "$(dirname "$rootfs")"
        $SUDO unsquashfs -d "$rootfs" "$sqfs" >/dev/null
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
        $SUDO CPM_ROOT="$rootfs" "$CPM_HOST" local "$PKG_BUILD/${pkg}.cpm" \
            2>&1 | grep -v "^Instalez " || true
    done

    info "  scriu /etc/cpm/repo.url -> $CPM_REPO_URL"
    $SUDO install -d "$rootfs/etc/cpm"
    echo "$CPM_REPO_URL" | $SUDO tee "$rootfs/etc/cpm/repo.url" >/dev/null

    info "  instalez binarul cpm la /usr/local/bin/cpm"
    $SUDO install -m 0755 "$CPM_HOST" "$rootfs/usr/local/bin/cpm"
}

# ---- 7. ruleaza hooks finale in chroot ----
ruleaza_hooks() {
    local rootfs="$1"
    info "[6/8] Hooks finale in chroot"

    # Mount-uri necesare pentru chroot
    for m in proc sys dev dev/pts; do
        $SUDO mkdir -p "$rootfs/$m"
    done
    $SUDO mount -t proc  proc      "$rootfs/proc"
    $SUDO mount -t sysfs sysfs     "$rootfs/sys"
    $SUDO mount --bind   /dev      "$rootfs/dev"
    $SUDO mount --bind   /dev/pts  "$rootfs/dev/pts"
    trap "
        $SUDO umount -lf '$rootfs/dev/pts' 2>/dev/null || true
        $SUDO umount -lf '$rootfs/dev'     2>/dev/null || true
        $SUDO umount -lf '$rootfs/sys'     2>/dev/null || true
        $SUDO umount -lf '$rootfs/proc'    2>/dev/null || true
    " EXIT

    $SUDO chroot "$rootfs" /bin/bash -eu <<'CHROOT_EOF'
        export DEBIAN_FRONTEND=noninteractive

        echo "[chroot] glib-compile-schemas"
        if [ -d /usr/share/glib-2.0/schemas ]; then
            glib-compile-schemas /usr/share/glib-2.0/schemas/ || true
        fi

        echo "[chroot] dconf update (compileaza GDM greeter dconf db)"
        if command -v dconf >/dev/null && [ -d /etc/dconf/db ]; then
            dconf update || true
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

    $SUDO umount -lf "$rootfs/dev/pts" || true
    $SUDO umount -lf "$rootfs/dev"     || true
    $SUDO umount -lf "$rootfs/sys"     || true
    $SUDO umount -lf "$rootfs/proc"    || true
    trap - EXIT
}

# ---- 8. repack squashfs + checksums + ISO ----
repack_squashfs() {
    local sqfs="$1"
    local rootfs="$2"
    info "[7/8] Repac squashfs (xz, poate dura cateva minute)"
    $SUDO rm -f "$sqfs"
    $SUDO mksquashfs "$rootfs" "$sqfs" -comp xz -b 1M -no-progress 2>&1 | tail -3
}

regenereaza_checksums() {
    local extract="$1"
    info "  regenerez md5sum.txt"
    (
        cd "$extract"
        $SUDO find . -type f ! -name md5sum.txt ! -path './isolinux/*' \
            -exec md5sum {} + | $SUDO tee md5sum.txt >/dev/null
    )
}

construieste_iso() {
    local extract="$1"
    info "[8/8] Construiesc ISO final -> $OUT"

    # Pentru arm64 doar UEFI. Cautam efi.img in locatia standard Ubuntu.
    local efi_rel=""
    for cand in boot/grub/efi.img EFI/boot/efi.img boot.img; do
        if [ -f "$extract/$cand" ]; then
            efi_rel="$cand"
            break
        fi
    done
    if [ -z "$efi_rel" ]; then
        # fallback: cautare recursiva
        local found
        found="$(cd "$extract" && find . -type f -name 'efi.img' | head -1)"
        efi_rel="${found#./}"
    fi
    [ -n "$efi_rel" ] && [ -f "$extract/$efi_rel" ] || fatal "nu gasesc efi.img in ISO extras"
    info "  efi image: $efi_rel"

    # Pattern Ubuntu live arm64 — partition 2 EF (EFI System) appended,
    # boot via -e cu interval pe partition 2.
    $SUDO xorriso -as mkisofs \
        -V "$CARPATOS_VOLID" \
        -o "$OUT" \
        -J -joliet-long -r \
        -iso-level 3 \
        -partition_offset 16 \
        --protective-msdos-label \
        -append_partition 2 0xef "$extract/$efi_rel" \
        -appended_part_as_gpt \
        -e '--interval:appended_partition_2:::' -no-emul-boot \
        "$extract" 2>&1 | tail -10

    $SUDO chown "$(id -u):$(id -g)" "$OUT"
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
