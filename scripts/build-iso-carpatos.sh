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
    carpatos-installer-rebrand
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
#   minimal.squashfs (1.6 GB) — baza completa
#   minimal.standard.squashfs (460 MB) — overlay diff standard pkgs
#   minimal.standard.live.squashfs (925 MB) — overlay live (shadow-uieste base)
#   minimal.<lang>.squashfs (16 MB) — language packs
# Modificam BASE-ul (minimal.squashfs) ca overlay-ul carpatos sa apara
# si in instalat si in live. Plus separat aplicam gschema overrides la
# live overlay (acolo gschemas.compiled shadowuieste base-ul).
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
        # Folosim `env VAR=val cmd` in loc de `VAR=val cmd` pentru ca
        # daca $SUDO e gol, bash incearca sa execute "VAR=val" ca o
        # comanda. `env` lucreaza mereu corect.
        $SUDO env CPM_ROOT="$rootfs" "$CPM_HOST" local "$PKG_BUILD/${pkg}.cpm" \
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

        echo "[chroot] plymouth default theme = carpatos (scriere directa)"
        # plymouth-set-default-theme are bug-uri in chroot — scrie direct
        # /etc/plymouth/plymouthd.conf (fisierul de pe care plymouth citeste).
        mkdir -p /etc/plymouth
        cat > /etc/plymouth/plymouthd.conf <<'PLYC'
[Daemon]
Theme=carpatos
PLYC
        # Cream si link-ul standard plymouth-default-theme (alte componente
        # il citesc).
        if [ -d /usr/share/plymouth/themes/carpatos ]; then
            ln -sf /usr/share/plymouth/themes/carpatos/carpatos.plymouth \
                /usr/share/plymouth/themes/default.plymouth || true
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

# Live overlay-ul are propriul gschemas.compiled care shadowuieste cel din
# baza. Daca-l lasam ca atare, wallpaper + dconf overrides nu se aplica
# in sesiunea live. Solutie: copiem fisierele noastre carpatos-* peste
# o copie a overlay-ului si recompilam gschemas + dconf.
patcheaza_live_overlay() {
    local extract="$1"
    local rootfs="$2"
    local live_sqfs="$extract/casper/minimal.standard.live.squashfs"
    [ -f "$live_sqfs" ] || { info "  fara live overlay, sar peste"; return; }

    info "[7b/8] Patchez live overlay (gschemas + dconf carpatos)"
    local live_root="${ROOTFS_DIR%rootfs}live-overlay-rootfs"
    [ -n "${ROOTFS_DIR:-}" ] || live_root="$WORK/live-overlay-rootfs"
    $SUDO rm -rf "$live_root"
    $SUDO mkdir -p "$(dirname "$live_root")"
    $SUDO unsquashfs -d "$live_root" "$live_sqfs" >/dev/null

    # Aplic carpatos-gnome-defaults + carpatos-gdm-theme in live overlay
    # ca sa garantez ca override-urile schemei sunt prezente acolo (in
    # plus fata de ce e in base — overlayfs uneste cele doua).
    for pkg in carpatos-gnome-defaults carpatos-gdm-theme; do
        $SUDO env CPM_ROOT="$live_root" "$CPM_HOST" local \
            "$PKG_BUILD/${pkg}.cpm" >/dev/null 2>&1 || true
    done

    # Live overlay nu are toolchain (glib-compile-schemas, dconf). Bind-
    # mount /usr si /lib din base rootfs intr-un punct temporar separat,
    # apoi exec direct cu PATH/LD_LIBRARY_PATH ajustate pe live_root —
    # asa scrie gschemas.compiled in live_root/usr/share/glib-2.0/schemas
    # cu binarele din base, fara sa stricam fisierele live_root.
    info "  compilez gschemas in live overlay"
    if [ -d "$live_root/usr/share/glib-2.0/schemas" ]; then
        $SUDO env LD_LIBRARY_PATH="$rootfs/usr/lib/aarch64-linux-gnu:$rootfs/lib/aarch64-linux-gnu" \
            "$rootfs/usr/bin/glib-compile-schemas" \
            "$live_root/usr/share/glib-2.0/schemas/" 2>&1 | head -3 || true
    fi

    info "  compilez dconf db in live overlay"
    if [ -d "$live_root/etc/dconf/db" ]; then
        # dconf update vrea sa scrie /etc/dconf/db/*. Foloseste DCONF_PROFILE
        # ca sa-l directionez la live_root.
        for db_dir in "$live_root/etc/dconf/db"/*.d; do
            [ -d "$db_dir" ] || continue
            local db_name="${db_dir%.d}"
            db_name="$(basename "$db_name")"
            $SUDO env LD_LIBRARY_PATH="$rootfs/usr/lib/aarch64-linux-gnu:$rootfs/lib/aarch64-linux-gnu" \
                "$rootfs/usr/bin/dconf" compile "$live_root/etc/dconf/db/$db_name" \
                "$db_dir" 2>&1 | head -3 || true
        done
    fi

    info "  repack $(basename "$live_sqfs")"
    $SUDO rm -f "$live_sqfs"
    $SUDO mksquashfs "$live_root" "$live_sqfs" -comp xz -b 1M -no-progress 2>&1 | tail -3
}

# Plymouth la live boot citeste din /casper/initrd, NU din /boot/initrd.img
# al rootfs-ului. Copiem initrd-ul din rootfs (care a fost regenerat cu
# update-initramfs si include theme-ul carpatos) peste casper/initrd.
update_casper_initrd() {
    local extract="$1"
    local rootfs="$2"
    info "[7c/8] Update casper/initrd cu plymouth carpatos"
    local initrd_src
    initrd_src="$($SUDO find "$rootfs/boot" -maxdepth 1 -name 'initrd.img-*' -type f | sort -V | tail -1)"
    if [ -n "$initrd_src" ] && [ -f "$initrd_src" ]; then
        $SUDO cp "$initrd_src" "$extract/casper/initrd"
        info "  copied $(basename "$initrd_src") -> casper/initrd ($(du -h "$extract/casper/initrd" | cut -f1))"
    else
        warn "  nu gasesc initrd.img-* in rootfs/boot, casper/initrd ramane original"
    fi
}

# Modifica grub.cfg si .disk/info ca sa nu mai zica "Ubuntu" la boot.
patcheaza_branding_iso() {
    local extract="$1"
    info "  rebrand boot menu + .disk/info"
    if [ -f "$extract/boot/grub/grub.cfg" ]; then
        $SUDO sed -i \
            -e 's|Try or Install Ubuntu|Try or Install CarpatOS|g' \
            -e 's|Install Ubuntu|Install CarpatOS|g' \
            -e 's|Try Ubuntu|Try CarpatOS|g' \
            "$extract/boot/grub/grub.cfg"
    fi
    if [ -f "$extract/.disk/info" ]; then
        echo -n "CarpatOS Desktop ${CARPATOS_VERSION} arm64 (peste Ubuntu noble)" \
            | $SUDO tee "$extract/.disk/info" >/dev/null
    fi
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
    local orig_iso="$2"
    info "[8/8] Construiesc ISO final -> $OUT"

    # Ubuntu 24.04 arm64 ISO are El Torito EFI boot image hidden (la
    # un LBA specific, nu fisier in arborele filesystem). Folosim modul
    # de "clonare" xorriso: -indev orig + -outdev new + replay boot info
    # + -update_r pentru a inlocui arborele cu cel modificat.
    $SUDO rm -f "$OUT"
    $SUDO xorriso \
        -indev "$orig_iso" \
        -outdev "$OUT" \
        -boot_image any replay \
        -volid "$CARPATOS_VOLID" \
        -update_r "$extract" / \
        2>&1 | tail -10

    $SUDO chown "$(id -u):$(id -g)" "$OUT" 2>/dev/null || true
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
patcheaza_live_overlay "$EXTRACT" "$ROOTFS"
update_casper_initrd "$EXTRACT" "$ROOTFS"
patcheaza_branding_iso "$EXTRACT"
regenereaza_checksums "$EXTRACT"
construieste_iso "$EXTRACT" "$ISO"

info "Gata. Testeaza in QEMU/UTM cu:"
info "  qemu-system-aarch64 -M virt -cpu cortex-a72 -m 4G \\"
info "    -bios /usr/share/AAVMF/AAVMF_CODE.fd \\"
info "    -cdrom $OUT"
