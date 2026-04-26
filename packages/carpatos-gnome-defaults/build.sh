#!/bin/sh
# build.sh — instaleaza override-uri gschema pentru GNOME defaults
# (wallpaper, dock pinned apps, accent color, dark mode auto)
set -eu

SCHEMA_DIR="$DESTDIR/usr/share/glib-2.0/schemas"
install -d "$SCHEMA_DIR"

# Prefix "90_" — ordinea alfabetica face acest override sa-l bata pe
# 10_ubuntu-settings.gschema.override de la ubuntu-settings (acela ar
# putea pune wallpaper-ul Ubuntu yaru-purple).
cat > "$SCHEMA_DIR/90_carpatos-defaults.gschema.override" <<'EOF'
# CarpatOS Desktop default settings.
# Aplicat dupa glib-compile-schemas /usr/share/glib-2.0/schemas/

[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/carpatos/carpatos-default.svg'
picture-uri-dark='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-options='zoom'
primary-color='#1c2a4a'

[org.gnome.desktop.screensaver]
picture-uri='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-options='zoom'

[org.gnome.desktop.interface]
color-scheme='prefer-dark'
accent-color='blue'
icon-theme='Yaru'
cursor-theme='Yaru'

[org.gnome.shell]
favorite-apps=['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.Settings.desktop']

[org.gnome.shell.extensions.dash-to-dock]
dock-position='BOTTOM'
extend-height=false
dock-fixed=false
custom-theme-shrink=true
EOF

chmod 0644 "$SCHEMA_DIR/90_carpatos-defaults.gschema.override"
