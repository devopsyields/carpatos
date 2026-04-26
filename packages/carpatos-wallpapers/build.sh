#!/bin/sh
# build.sh — instaleaza wallpapers SVG si logo CarpatOS
set -eu

SRC="$(dirname "$0")"
WP_DIR="$DESTDIR/usr/share/backgrounds/carpatos"
LOGO_DIR="$DESTDIR/usr/share/pixmaps"

install -d "$WP_DIR" "$LOGO_DIR"

install -m 0644 "$SRC/carpatos-default.svg" "$WP_DIR/carpatos-default.svg"
install -m 0644 "$SRC/carpatos-night.svg"   "$WP_DIR/carpatos-night.svg"
install -m 0644 "$SRC/carpatos-logo.svg"    "$LOGO_DIR/carpatos.svg"

# Link de conveninta — multe componente desktop cauta /usr/share/pixmaps/<id>
# unde <id> e LOGO din /etc/os-release.
ln -sf carpatos.svg "$LOGO_DIR/distributor-logo.svg"
