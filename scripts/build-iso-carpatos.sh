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

# ---- 8. construieste carpatos.squashfs ca strat NOU ----
# In loc sa modificam minimal.squashfs (care strica boot-ul Ubuntu),
# pastram TOATE fisierele Ubuntu intacte si cream un strat nou:
#   /casper/minimal.standard.live.carpatos.squashfs
# Casper detecteaza chain-ul prin strip-suffix (.carpatos -> .live ->
# .standard -> minimal). Activam noul lant prin layerfs-path= in grub.
construieste_carpatos_squashfs() {
    local extract="$1"
    local rootfs="$2"  # rootfs-ul cu carpatos installed + hooks rulate
    info "[7/8] Construiesc carpatos overlay squashfs"

    local overlay="${ROOTFS_DIR%rootfs}carpatos-overlay"
    [ -n "${ROOTFS_DIR:-}" ] || overlay="$WORK/carpatos-overlay"
    $SUDO rm -rf "$overlay"
    $SUDO mkdir -p "$overlay"

    # Instalez pachetele carpatos-* intr-un dir gol (FARA Ubuntu base).
    # Fisierele rezultate sunt strict carpatos overrides.
    info "  install pachetele carpatos-* in overlay (fresh dir)"
    for pkg in "${CARPATOS_PACKAGES[@]}"; do
        $SUDO env CPM_ROOT="$overlay" "$CPM_HOST" local "$PKG_BUILD/${pkg}.cpm" \
            >/dev/null 2>&1 || true
    done

    # Copiez artefactele compilate din rootfs (au fost generate cu chroot
    # hooks din etapa anterioara, contin overrides carpatos):
    info "  copiez gschemas.compiled (cu carpatos picture-uri etc.)"
    if [ -f "$rootfs/usr/share/glib-2.0/schemas/gschemas.compiled" ]; then
        $SUDO mkdir -p "$overlay/usr/share/glib-2.0/schemas"
        $SUDO cp "$rootfs/usr/share/glib-2.0/schemas/gschemas.compiled" \
            "$overlay/usr/share/glib-2.0/schemas/"
    fi
    info "  copiez dconf db compilat (gdm cu wallpaper carpatos)"
    if [ -d "$rootfs/etc/dconf/db" ]; then
        $SUDO mkdir -p "$overlay/etc/dconf/db"
        $SUDO cp -a "$rootfs/etc/dconf/db/." "$overlay/etc/dconf/db/" 2>/dev/null || true
    fi
    if [ -f "$rootfs/etc/dconf/profile/gdm" ]; then
        $SUDO mkdir -p "$overlay/etc/dconf/profile"
        $SUDO cp "$rootfs/etc/dconf/profile/gdm" "$overlay/etc/dconf/profile/"
    fi

    # cpm binary + repo.url + hostname (fisiere ce nu vin din .cpm packages)
    info "  cpm binary + repo.url + hostname"
    $SUDO mkdir -p "$overlay/usr/local/bin" "$overlay/etc/cpm"
    $SUDO cp "$CPM_HOST" "$overlay/usr/local/bin/cpm"
    echo "$CPM_REPO_URL" | $SUDO tee "$overlay/etc/cpm/repo.url" >/dev/null
    echo "carpatos" | $SUDO tee "$overlay/etc/hostname" >/dev/null

    # Plymouth conf
    info "  plymouth default theme = carpatos"
    $SUDO mkdir -p "$overlay/etc/plymouth"
    printf '[Daemon]\nTheme=carpatos\nShowDelay=0\n' \
        | $SUDO tee "$overlay/etc/plymouth/plymouthd.conf" >/dev/null
    if [ -d "$overlay/usr/share/plymouth/themes/carpatos" ]; then
        $SUDO ln -sf carpatos/carpatos.plymouth \
            "$overlay/usr/share/plymouth/themes/default.plymouth" || true
    fi

    info "  repack -> $extract/casper/minimal.standard.live.carpatos.squashfs"
    local out_sqfs="$extract/casper/minimal.standard.live.carpatos.squashfs"
    $SUDO rm -f "$out_sqfs"
    $SUDO mksquashfs "$overlay" "$out_sqfs" -comp xz -b 1M -no-progress 2>&1 | tail -3
    info "  carpatos.squashfs: $(du -h "$out_sqfs" | cut -f1)"
}

# Activeaza carpatos overlay prin grub cmdline.
patcheaza_grub_layerfs() {
    local extract="$1"
    info "  activeaza layerfs-path=...carpatos in grub.cfg"
    if [ -f "$extract/boot/grub/grub.cfg" ]; then
        # Adaug layerfs-path= ca prim parametru dupa /casper/vmlinuz
        $SUDO sed -i \
            -e 's|/casper/vmlinuz |/casper/vmlinuz layerfs-path=minimal.standard.live.carpatos.squashfs |' \
            "$extract/boot/grub/grub.cfg"
    fi
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

    # Strategie: sterg fisierele compilate din live overlay (gschemas.
    # compiled si dconf db). Base rootfs are deja totul compilat cu
    # override-urile noastre carpatos. Dupa overlayfs mount la live boot,
    # base layer's compiled iese la suprafata (nu mai e shadowuit de
    # un fisier 0-byte sau diferit din live overlay).
    info "  sterg compiled din live overlay (fall-through la base)"
    $SUDO rm -f "$live_root/usr/share/glib-2.0/schemas/gschemas.compiled"
    # dconf db files (fara extensie, in /etc/dconf/db/) — pastram numai
    # subdirectoarele *.d (override files, util la rebuild).
    if [ -d "$live_root/etc/dconf/db" ]; then
        $SUDO find "$live_root/etc/dconf/db" -mindepth 1 -maxdepth 1 -type f -delete
    fi

    info "  repack $(basename "$live_sqfs")"
    $SUDO rm -f "$live_sqfs"
    $SUDO mksquashfs "$live_root" "$live_sqfs" -comp xz -b 1M -no-progress 2>&1 | tail -3
}

# Plymouth la live boot citeste din /casper/initrd. minimal.squashfs nu
# contine /boot/initrd.img-* (Ubuntu live foloseste casper/initrd direct).
# In loc sa regeneram initrd, despachetam initrd-ul existent, adaugam
# fisierele plymouth carpatos, repacheteaza in acelasi format.
update_casper_initrd() {
    local extract="$1"
    local rootfs="$2"
    info "[7c/8] Update casper/initrd cu plymouth carpatos"
    local initrd="$extract/casper/initrd"
    [ -f "$initrd" ] || { warn "  /casper/initrd lipseste, sar peste"; return; }

    # Detectez compresia (zstd / xz / gz / cpio plain)
    local magic
    magic=$($SUDO head -c 4 "$initrd" | od -An -tx1 | tr -d ' \n')
    local decompress repack
    case "$magic" in
        28b52ffd*) decompress="zstd -dc";  repack="zstd --ultra -22 -T0" ;;
        fd377a58*) decompress="xz -dc";    repack="xz --check=crc32 -9 --lzma2=dict=1MiB" ;;
        1f8b0808*|1f8b*) decompress="gzip -dc"; repack="gzip" ;;
        303730*)   decompress="cat";       repack="cat" ;;  # cpio plain
        *) warn "  format necunoscut casper/initrd ($magic), sar"; return ;;
    esac

    local extract_dir="${ROOTFS_DIR%rootfs}initrd-extract"
    [ -n "${ROOTFS_DIR:-}" ] || extract_dir="$WORK/initrd-extract"
    $SUDO rm -rf "$extract_dir"
    $SUDO mkdir -p "$extract_dir"
    info "  despachetez initrd ($magic) -> $extract_dir"
    (cd "$extract_dir" && $SUDO sh -c "$decompress < '$initrd' | cpio -idm --quiet") 2>&1 | head -3 || true

    info "  copiez plymouth theme carpatos in initrd"
    $SUDO mkdir -p "$extract_dir/usr/share/plymouth/themes/carpatos" "$extract_dir/etc/plymouth"
    if [ -d "$rootfs/usr/share/plymouth/themes/carpatos" ]; then
        $SUDO cp -a "$rootfs/usr/share/plymouth/themes/carpatos/." \
            "$extract_dir/usr/share/plymouth/themes/carpatos/"
    fi
    if [ -f "$rootfs/etc/plymouth/plymouthd.conf" ]; then
        $SUDO cp -a "$rootfs/etc/plymouth/plymouthd.conf" \
            "$extract_dir/etc/plymouth/plymouthd.conf"
    else
        printf '[Daemon]\nTheme=carpatos\n' \
            | $SUDO tee "$extract_dir/etc/plymouth/plymouthd.conf" >/dev/null
    fi
    if [ -d "$rootfs/usr/share/plymouth/themes" ]; then
        $SUDO ln -sf carpatos/carpatos.plymouth \
            "$extract_dir/usr/share/plymouth/themes/default.plymouth" || true
    fi

    info "  repac initrd"
    (cd "$extract_dir" && $SUDO sh -c "find . | cpio -o -H newc --quiet | $repack > '$initrd.new'")
    $SUDO mv "$initrd.new" "$initrd"
    info "  /casper/initrd: $(du -h "$initrd" | cut -f1)"
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
# NU repack-uim minimal.squashfs (Ubuntu intact). Construiesc carpatos
# ca strat separat, activat prin layerfs-path= in grub cmdline.
construieste_carpatos_squashfs "$EXTRACT" "$ROOTFS"
patcheaza_grub_layerfs "$EXTRACT"
patcheaza_branding_iso "$EXTRACT"
regenereaza_checksums "$EXTRACT"
construieste_iso "$EXTRACT" "$ISO"

info "Gata. Testeaza in QEMU/UTM cu:"
info "  qemu-system-aarch64 -M virt -cpu cortex-a72 -m 4G \\"
info "    -bios /usr/share/AAVMF/AAVMF_CODE.fd \\"
info "    -cdrom $OUT"
