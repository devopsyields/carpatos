#!/usr/bin/env bash
# build-iso-debian.sh
#
# Construieste ISO-ul CarpatOS Desktop pe baza Debian 13 (trixie) aarch64.
# Spre deosebire de varianta Ubuntu (build-iso-carpatos.sh, abandonata),
# aici controlam TOATE straturile vizuale:
#   - Plymouth carpatos = default din build (update-initramfs in chroot)
#   - GNOME defaults compilate corect (glib-compile-schemas + dconf update)
#   - Calamares ca installer, rebrand-uit cu branding carpatos
#   - Wallpaper, iconuri, terminal — toate carpatos din start, fara fight
#     cu Ubuntu's runtime
#
# Etape:
#   1. debootstrap Debian trixie aarch64 -> /work/debian-rootfs
#   2. apt install kernel + GNOME + plymouth + Calamares + live-boot
#   3. cpm install pachetele carpatos-* peste rootfs (overlay)
#   4. chroot hooks: glib-compile-schemas, dconf update, plymouth -R,
#      update-initramfs (asa initrd are plymouth carpatos)
#   5. squashfs rootfs -> /work/iso/live/filesystem.squashfs
#   6. copy kernel + initrd -> /work/iso/live/
#   7. grub.cfg + grub-efi-arm64 -> /work/iso/EFI/BOOT/
#   8. xorriso -> build/iso/carpatos-desktop-1.0-arm64.iso
#
# Cerinte runtime:
#   - Linux arm64 (sau Docker --privileged pe Apple Silicon, native arm64)
#   - sudo (sau root)
#   - debootstrap, xorriso, squashfs-tools, mtools, dosfstools, grub-efi-arm64-bin
set -euo pipefail

# ---- config ----
DEBIAN_RELEASE="${DEBIAN_RELEASE:-trixie}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_ARH="${DEBIAN_ARH:-arm64}"

CARPATOS_VERSION="${CARPATOS_VERSION:-1.0}"
CARPATOS_VOLID="${CARPATOS_VOLID:-CarpatOS Desktop ${CARPATOS_VERSION}}"
CPM_REPO_URL="${CPM_REPO_URL:-https://github.com/devopsyields/carpatos-repo/releases/download/v0.2-essentials}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD:-$ROOT/build/debian-iso}"
WORK="$BUILD/work"
OUT="$BUILD/carpatos-desktop-${CARPATOS_VERSION}-${DEBIAN_ARH}.iso"

CPM_HOST="$ROOT/initramfs/src/cpm/cpm_host"

# Suport ROOTFS_DIR override (volum Docker pentru a evita FS limitations)
ROOTFS_DIR="${ROOTFS_DIR:-$WORK/rootfs}"
ISO_DIR="${ISO_DIR:-$WORK/iso}"

CARPATOS_PACKAGES=(
    carpatos-os-release
    carpatos-banner
    carpatos-wallpapers
    carpatos-gnome-defaults
    carpatos-plymouth-theme
    carpatos-gdm-theme
    carpatos-installer-rebrand
)

# Lista pachete Debian instalate in chroot
DEBIAN_PACKAGES_CORE=(
    # Core sistem
    init systemd-sysv dbus locales console-setup keyboard-configuration
    network-manager isc-dhcp-client ca-certificates curl wget sudo
    # Live boot
    live-boot live-config live-config-systemd
    # Kernel + initramfs tools
    linux-image-arm64 initramfs-tools
    # Bootloader (in rootfs, dar copiate la ISO)
    grub-efi-arm64-bin grub-common
)

DEBIAN_PACKAGES_DESKTOP=(
    # GNOME minimal
    gnome-core gdm3 gnome-terminal gnome-text-editor nautilus eog
    gnome-control-center gnome-tweaks
    # Browser + utilitare
    firefox-esr
    # Plymouth (boot splash)
    plymouth plymouth-themes
    # Tools
    bash-completion htop vim-tiny git
    # Audio
    pipewire pipewire-pulse wireplumber
)

DEBIAN_PACKAGES_INSTALLER=(
    # Calamares — installer GUI customizabil (folosit de Manjaro etc.)
    calamares calamares-settings-debian
    # squashfs-tools necesar de Calamares pentru unsquashfs target
    squashfs-tools rsync
)

# ---- helpers ----
info()  { printf "\033[1;36m[info]\033[0m %s\n" "$*" >&2; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$*" >&2; }
fatal() { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || fatal "lipseste binarul: $1"; }

SUDO="sudo"
need_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif sudo -n true 2>/dev/null; then
        SUDO="sudo"
    else
        fatal "scriptul are nevoie de sudo (sau ruleaza ca root)"
    fi
}

preflight() {
    info "preflight: dependinte"
    for t in debootstrap xorriso unsquashfs mksquashfs mformat \
             mkfs.fat curl; do need "$t"; done
    [ -x "$CPM_HOST" ] || fatal "lipseste $CPM_HOST (compileaza cu make ARCH=aarch64)"
    need_sudo
    mkdir -p "$BUILD" "$WORK" "$ISO_DIR"
    [ "$(uname -m)" = "aarch64" ] || \
        warn "arhitectura host nu e aarch64 (e $(uname -m)) — debootstrap foreign poate fi mai lent"
}

# ---- 1. debootstrap base Debian rootfs ----
debootstrap_rootfs() {
    if [ -d "$ROOTFS_DIR" ] && [ -n "$($SUDO ls -A "$ROOTFS_DIR" 2>/dev/null)" ]; then
        info "[1/8] rootfs deja initializat la $ROOTFS_DIR (reuse)"
        return
    fi
    info "[1/8] debootstrap $DEBIAN_RELEASE/$DEBIAN_ARH -> $ROOTFS_DIR"
    $SUDO mkdir -p "$ROOTFS_DIR"
    $SUDO debootstrap \
        --arch="$DEBIAN_ARH" \
        --variant=minbase \
        --include=apt-transport-https,gnupg \
        "$DEBIAN_RELEASE" "$ROOTFS_DIR" "$DEBIAN_MIRROR"
    info "  rootfs baza: $($SUDO du -sh "$ROOTFS_DIR" | cut -f1)"
}

# ---- 2. apt sources + install pachete chroot ----
configure_apt_si_install() {
    info "[2/8] configurez apt sources + instalez pachete in chroot"

    # Sources.list cu main contrib non-free-firmware
    $SUDO tee "$ROOTFS_DIR/etc/apt/sources.list" >/dev/null <<EOF
deb $DEBIAN_MIRROR $DEBIAN_RELEASE main contrib non-free-firmware
deb $DEBIAN_MIRROR $DEBIAN_RELEASE-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security $DEBIAN_RELEASE-security main contrib non-free-firmware
EOF

    # mounts pentru chroot (proc, sys, dev)
    chroot_mount

    # Update + install
    $SUDO chroot "$ROOTFS_DIR" /bin/bash -eux <<'CHROOT_EOF'
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y --no-install-recommends \
            init systemd-sysv dbus locales console-setup keyboard-configuration \
            network-manager isc-dhcp-client ca-certificates curl wget sudo \
            live-boot live-config live-config-systemd \
            linux-image-arm64 initramfs-tools \
            grub-efi-arm64-bin grub-common
        # locale en_US.UTF-8 + ro_RO.UTF-8
        sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/; s/^# *ro_RO.UTF-8/ro_RO.UTF-8/' /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8

        # GNOME desktop
        apt-get install -y --no-install-recommends \
            gnome-core gdm3 gnome-terminal gnome-text-editor nautilus eog \
            gnome-control-center \
            firefox-esr \
            plymouth plymouth-themes \
            bash-completion htop vim-tiny git \
            pipewire pipewire-pulse wireplumber \
            calamares calamares-settings-debian \
            squashfs-tools rsync

        # Curatare apt cache (sa fie ISO mai mic)
        apt-get clean
        rm -rf /var/lib/apt/lists/*
CHROOT_EOF
    info "  rootfs dupa install: $($SUDO du -sh "$ROOTFS_DIR" | cut -f1)"
}

chroot_mount() {
    for m in proc sys dev dev/pts; do
        $SUDO mkdir -p "$ROOTFS_DIR/$m"
    done
    $SUDO mount -t proc  proc      "$ROOTFS_DIR/proc"     2>/dev/null || true
    $SUDO mount -t sysfs sysfs     "$ROOTFS_DIR/sys"      2>/dev/null || true
    $SUDO mount --bind   /dev      "$ROOTFS_DIR/dev"      2>/dev/null || true
    $SUDO mount --bind   /dev/pts  "$ROOTFS_DIR/dev/pts"  2>/dev/null || true
    trap 'chroot_umount' EXIT
}

chroot_umount() {
    $SUDO umount -lf "$ROOTFS_DIR/dev/pts" 2>/dev/null || true
    $SUDO umount -lf "$ROOTFS_DIR/dev"     2>/dev/null || true
    $SUDO umount -lf "$ROOTFS_DIR/sys"     2>/dev/null || true
    $SUDO umount -lf "$ROOTFS_DIR/proc"    2>/dev/null || true
}

# ---- 3. construieste pachete carpatos-* ----
construieste_pachete() {
    info "[3/8] Construiesc pachete carpatos-*"
    local pkgdir="$WORK/packages"
    $SUDO rm -rf "$pkgdir"
    mkdir -p "$pkgdir"
    for pkg in "${CARPATOS_PACKAGES[@]}"; do
        info "  build $pkg"
        "$CPM_HOST" build "$ROOT/packages/$pkg" \
            -o "$pkgdir/${pkg}.cpm" >/dev/null
    done
    echo "$pkgdir"
}

# ---- 4. aplica overlay carpatos peste rootfs ----
aplica_overlay() {
    local pkgdir="$1"
    info "[4/8] Aplic pachete carpatos-* peste rootfs Debian"
    for pkg in "${CARPATOS_PACKAGES[@]}"; do
        info "  install $pkg"
        $SUDO env CPM_ROOT="$ROOTFS_DIR" "$CPM_HOST" local \
            "$pkgdir/${pkg}.cpm" 2>&1 | grep -v "^Instalez " || true
    done

    info "  scriu /etc/cpm/repo.url + binar cpm"
    $SUDO install -d "$ROOTFS_DIR/etc/cpm"
    echo "$CPM_REPO_URL" | $SUDO tee "$ROOTFS_DIR/etc/cpm/repo.url" >/dev/null
    $SUDO install -m 0755 "$CPM_HOST" "$ROOTFS_DIR/usr/local/bin/cpm"

    info "  hostname carpatos"
    echo "carpatos" | $SUDO tee "$ROOTFS_DIR/etc/hostname" >/dev/null
}

# ---- 5. chroot hooks ----
ruleaza_hooks() {
    info "[5/8] Hooks finale in chroot"
    chroot_mount

    $SUDO chroot "$ROOTFS_DIR" /bin/bash -eu <<'CHROOT_EOF'
        echo "[chroot] glib-compile-schemas"
        glib-compile-schemas /usr/share/glib-2.0/schemas/ || true

        echo "[chroot] dconf update"
        if [ -d /etc/dconf/db ]; then dconf update || true; fi

        echo "[chroot] plymouth-set-default-theme carpatos"
        plymouth-set-default-theme -R carpatos

        echo "[chroot] update-initramfs (initrd cu plymouth carpatos)"
        update-initramfs -u -k all

        echo "[chroot] live-config: setup live user"
        # live-config creeaza userul "user" automat la live boot
        # noi schimbam numele in "carpatos"
        cat > /etc/live/config.conf.d/carpatos.conf <<EOF2
LIVE_USERNAME=carpatos
LIVE_USER_FULLNAME="CarpatOS Live"
LIVE_HOSTNAME=carpatos
LIVE_LOCALES="en_US.UTF-8 ro_RO.UTF-8"
LIVE_KEYBOARD_LAYOUTS="us"
EOF2

        echo "[chroot] enable live-config.service (CRITICAL — fara asta nu creaza user)"
        # systemctl enable in chroot poate sa hang pe dbus, cream symlinkul direct
        mkdir -p /etc/systemd/system/multi-user.target.wants
        ln -sf /lib/systemd/system/live-config.service \
            /etc/systemd/system/multi-user.target.wants/live-config.service
        # Sterg branding Calamares Debian (avem carpatos)
        rm -rf /etc/calamares/branding/debian

        echo "[chroot] GDM autologin pentru live user"
        mkdir -p /etc/gdm3
        cat > /etc/gdm3/daemon.conf <<EOF2
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=carpatos

[security]

[xdmcp]

[chooser]

[debug]
EOF2

        echo "[chroot] terminat"
CHROOT_EOF

    chroot_umount
}

# ---- 6. configureaza Calamares cu branding carpatos ----
configureaza_calamares() {
    info "[6/8] Configurez Calamares (installer) cu branding carpatos"

    # Branding directory
    local brand="$ROOTFS_DIR/etc/calamares/branding/carpatos"
    $SUDO mkdir -p "$brand"

    # branding.desc — config principal
    $SUDO tee "$brand/branding.desc" >/dev/null <<'EOF'
---
componentName: carpatos

welcomeStyleCalamares: true
welcomeExpandingLogo: true

windowExpanding: normal
windowSize: 800px,520px
windowPlacement: center

strings:
    productName:         CarpatOS Desktop
    shortProductName:    CarpatOS
    version:             1.0
    shortVersion:        1.0
    versionedName:       CarpatOS Desktop 1.0
    shortVersionedName:  CarpatOS 1.0
    bootloaderEntryName: CarpatOS
    productUrl:          https://github.com/devopsyields/carpatos
    supportUrl:          https://github.com/devopsyields/carpatos/issues
    knownIssuesUrl:      https://github.com/devopsyields/carpatos/issues
    releaseNotesUrl:     https://github.com/devopsyields/carpatos/releases

images:
    productLogo:         "carpatos-logo.png"
    productIcon:         "carpatos-logo.png"
    productWelcome:      "carpatos-welcome.png"

slideshow:               "show.qml"

style:
   sidebarBackground:    "#1c2a4a"
   sidebarText:          "#f5e6d3"
   sidebarTextSelect:    "#d4a04a"
   sidebarTextHighlight: "#d4a04a"
EOF

    # Logo / welcome image — pentru moment placeholder (PNG 1x1) plus copy
    # din carpatos-wallpapers daca exista. Se inlocuieste cu artwork final.
    if [ -f "$ROOTFS_DIR/usr/share/pixmaps/carpatos.svg" ]; then
        # Calamares vrea PNG, dar SVG poate fi fallback prin rsvg
        $SUDO cp "$ROOTFS_DIR/usr/share/pixmaps/carpatos.svg" "$brand/carpatos-logo.svg"
    fi
    # PNG placeholder (1x1 transparent), inlocuit ulterior cu real PNG
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82' \
        | $SUDO tee "$brand/carpatos-logo.png" >/dev/null
    cp "$brand/carpatos-logo.png" "$brand/carpatos-welcome.png" 2>/dev/null || \
        $SUDO cp "$brand/carpatos-logo.png" "$brand/carpatos-welcome.png"

    # Slideshow QML (afisat in timpul instalarii)
    $SUDO tee "$brand/show.qml" >/dev/null <<'EOF'
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation
    Slide {
        Image {
            id: background
            source: "carpatos-welcome.png"
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
        }
        Text {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 50
            text: "Bun venit la CarpatOS Desktop 1.0"
            font.pixelSize: 22
            color: "#f5e6d3"
        }
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: presentation.advance() }
}
EOF

    # settings.conf — spune ce branding sa foloseasca + module list
    $SUDO mkdir -p "$ROOTFS_DIR/etc/calamares"
    $SUDO tee "$ROOTFS_DIR/etc/calamares/settings.conf" >/dev/null <<'EOF'
---
modules-search: [ local, /usr/lib/calamares/modules ]

instances: []

sequence:
- show:
  - welcome
  - locale
  - keyboard
  - partition
  - users
  - summary
- exec:
  - partition
  - mount
  - unpackfs
  - machineid
  - fstab
  - locale
  - keyboard
  - localecfg
  - users
  - hostname
  - networkcfg
  - hwclock
  - services-systemd
  - bootloader
  - grubcfg
  - umount
- show:
  - finished

branding: carpatos

prompt-install: true
dont-chroot: false
EOF

    # Calamares .desktop entry — afisat in dock/menu
    $SUDO tee "$ROOTFS_DIR/usr/share/applications/calamares.desktop" >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Instaleaza CarpatOS
Name[ro]=Instaleaza CarpatOS
GenericName=System Installer
Comment=Instaleaza CarpatOS Desktop pe disk
Comment[ro]=Instaleaza CarpatOS Desktop pe disk
Exec=pkexec calamares
Icon=carpatos
Terminal=false
StartupNotify=true
Categories=Qt;System;
EOF
}

# ---- 7. squashfs + ISO assembly ----
construieste_squashfs() {
    info "[7/8] Squashfs rootfs"
    mkdir -p "$ISO_DIR/live"
    $SUDO rm -f "$ISO_DIR/live/filesystem.squashfs"
    $SUDO mksquashfs "$ROOTFS_DIR" "$ISO_DIR/live/filesystem.squashfs" \
        -comp xz -b 1M -no-progress \
        -e boot 2>&1 | tail -3
    info "  squashfs: $(du -h "$ISO_DIR/live/filesystem.squashfs" | cut -f1)"

    info "  copy kernel + initrd"
    local kernel_file initrd_file
    kernel_file="$($SUDO ls "$ROOTFS_DIR/boot"/vmlinuz-* 2>/dev/null | sort -V | tail -1)"
    initrd_file="$($SUDO ls "$ROOTFS_DIR/boot"/initrd.img-* 2>/dev/null | sort -V | tail -1)"
    [ -n "$kernel_file" ] || fatal "nu gasesc kernel in rootfs/boot"
    [ -n "$initrd_file" ] || fatal "nu gasesc initrd in rootfs/boot"
    $SUDO cp "$kernel_file" "$ISO_DIR/live/vmlinuz"
    $SUDO cp "$initrd_file" "$ISO_DIR/live/initrd.img"
    $SUDO chown -R "$(id -u):$(id -g)" "$ISO_DIR/live/" 2>/dev/null || true
}

construieste_iso() {
    info "[8/8] Construiesc ISO bootable cu GRUB EFI arm64"

    # Live-boot signatures — fara astea, scripts/live in initrd nu
    # detecteaza ISO-ul ca live media si pica la busybox shell.
    info "  scriu live-boot signature files (.disk/info, filesystem.packages/.size)"
    $SUDO mkdir -p "$ISO_DIR/.disk"
    echo "CarpatOS Desktop ${CARPATOS_VERSION} ${DEBIAN_ARH}" \
        | $SUDO tee "$ISO_DIR/.disk/info" >/dev/null
    echo "full_cd/single" | $SUDO tee "$ISO_DIR/.disk/cd_type" >/dev/null
    $SUDO chroot "$ROOTFS_DIR" dpkg-query -W \
        --showformat='${Package} ${Version}\n' \
        | $SUDO tee "$ISO_DIR/live/filesystem.packages" >/dev/null
    $SUDO du -sx --block-size=1 "$ROOTFS_DIR" 2>/dev/null \
        | cut -f1 | $SUDO tee "$ISO_DIR/live/filesystem.size" >/dev/null

    # GRUB config in ISO — live-media-path=/live explicit, plus verbose
    # mode pentru debug (text mode, vad mesajele live-boot).
    mkdir -p "$ISO_DIR/boot/grub"
    cat > "$ISO_DIR/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0
loadfont unicode

menuentry "CarpatOS Desktop ${CARPATOS_VERSION} (live)" {
    linux  /live/vmlinuz boot=live components splash quiet live-media-path=/live
    initrd /live/initrd.img
}

menuentry "CarpatOS Desktop ${CARPATOS_VERSION} (live, modul safe)" {
    linux  /live/vmlinuz boot=live components quiet splash nomodeset live-media-path=/live
    initrd /live/initrd.img
}

menuentry "CarpatOS Desktop ${CARPATOS_VERSION} (debug verbose)" {
    linux  /live/vmlinuz boot=live components verbose live-media-path=/live
    initrd /live/initrd.img
}
EOF

    # Construiesc EFI image (FAT) cu GRUB AA64 standalone
    info "  build EFI standalone (grub-mkstandalone)"
    local efi_img="$WORK/efi.img"
    rm -f "$efi_img"

    # Trebuie sa avem grub modules disponibile pe host
    if [ ! -d /usr/lib/grub/arm64-efi ]; then
        info "  grub-efi-arm64 modules absent pe host — extragem din rootfs"
        $SUDO mkdir -p "$WORK/grub-modules"
        $SUDO cp -r "$ROOTFS_DIR/usr/lib/grub/arm64-efi/." "$WORK/grub-modules/"
        export GRUB_MODULES_DIR="$WORK/grub-modules"
    else
        export GRUB_MODULES_DIR="/usr/lib/grub/arm64-efi"
    fi

    # grub-mkstandalone care ruleaza fie pe host, fie via chroot
    $SUDO chroot "$ROOTFS_DIR" /bin/bash -c '
        grub-mkstandalone -O arm64-efi \
            -o /tmp/bootaa64.efi \
            --modules="part_gpt part_msdos fat ext2 normal boot linux echo all_video gfxterm font terminal configfile loadenv minicmd test sleep" \
            "boot/grub/grub.cfg=/tmp/grub-stub.cfg"
    ' 2>&1 | tail -3 || {
        # Fallback: stub config
        echo "search --no-floppy --label CARPATOS --set=root" \
            > "$ROOTFS_DIR/tmp/grub-stub.cfg"
        echo "configfile (\$root)/boot/grub/grub.cfg" \
            >> "$ROOTFS_DIR/tmp/grub-stub.cfg"
        $SUDO chroot "$ROOTFS_DIR" grub-mkstandalone -O arm64-efi \
            -o /tmp/bootaa64.efi \
            --modules="part_gpt part_msdos fat ext2 iso9660 udf normal boot linux echo all_video gfxterm font terminal configfile loadenv search search_label minicmd test sleep" \
            "boot/grub/grub.cfg=/tmp/grub-stub.cfg"
    }

    # Construim FAT image cu /EFI/BOOT/BOOTAA64.EFI
    # GRUB EFI standalone arm64 = ~11 MB, asa 32 MB FAT16 e necesar.
    # Label max 11 chars (FAT limitation).
    info "  pack EFI partition (32 MB FAT16)"
    dd if=/dev/zero of="$efi_img" bs=1M count=32 2>/dev/null
    mkfs.fat -F 16 -n CARPATOSEFI "$efi_img" >/dev/null
    mmd -i "$efi_img" ::/EFI ::/EFI/BOOT
    $SUDO mcopy -i "$efi_img" "$ROOTFS_DIR/tmp/bootaa64.efi" ::/EFI/BOOT/BOOTAA64.EFI

    # Build ISO cu xorriso (UEFI hybrid)
    info "  xorriso -> $OUT"
    $SUDO rm -f "$OUT"
    $SUDO xorriso -as mkisofs \
        -V "$CARPATOS_VOLID" \
        -volid "CARPATOS" \
        -o "$OUT" \
        -J -joliet-long -r \
        -iso-level 3 \
        -partition_offset 16 \
        --protective-msdos-label \
        -append_partition 2 0xef "$efi_img" \
        -appended_part_as_gpt \
        -e '--interval:appended_partition_2:::' -no-emul-boot \
        "$ISO_DIR" 2>&1 | tail -5

    $SUDO chown "$(id -u):$(id -g)" "$OUT" 2>/dev/null || true
    info "ISO gata: $OUT ($(du -h "$OUT" | cut -f1))"
}

# ---- main ----
preflight
debootstrap_rootfs
configure_apt_si_install
PKG_DIR=$(construieste_pachete)
aplica_overlay "$PKG_DIR"
ruleaza_hooks
configureaza_calamares
construieste_squashfs
construieste_iso

info ""
info "=== ISO Debian-based gata ==="
info "Path:   $OUT"
info "Marime: $(du -h "$OUT" | cut -f1)"
info ""
info "Boot in UTM (Apple Silicon): New VM > Linux > arm64 > select ISO."
info "Boot in QEMU: qemu-system-aarch64 -M virt -cpu max -m 4G -bios AAVMF_CODE.fd -cdrom $OUT"
