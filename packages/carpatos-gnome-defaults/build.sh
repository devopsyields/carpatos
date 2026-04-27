#!/bin/sh
# build.sh — instaleaza override-uri gschema pentru GNOME defaults
# (wallpaper, dock pinned apps, accent color, dark mode auto)
set -eu

SCHEMA_DIR="$DESTDIR/usr/share/glib-2.0/schemas"
install -d "$SCHEMA_DIR"

# Prefix "90_" face ca override-ul nostru sa fie procesat dupa
# 10_ubuntu-settings.gschema.override (ordine alfabetica).
#
# IMPORTANT: Ubuntu foloseste sintaxa PER-PROFILE [schema:profile].
# `:ubuntu` se aplica utilizatorului `ubuntu` (live session autologin),
# `:GNOME-Greeter` se aplica greeterului GDM. Trebuie sa suprasrim
# explicit aceste profile-uri, nu doar default-ul global. Altfel
# Ubuntu's per-profile override castiga.
cat > "$SCHEMA_DIR/90_carpatos-defaults.gschema.override" <<'EOF'
# CarpatOS Desktop default settings.
# Aplicat dupa glib-compile-schemas /usr/share/glib-2.0/schemas/

# --- Default global (orice profil) ---
[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/carpatos/carpatos-default.svg'
picture-uri-dark='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-options='zoom'
primary-color='#1c2a4a'

# --- Profile `ubuntu` (live session autologin user) ---
[org.gnome.desktop.background:ubuntu]
picture-uri='file:///usr/share/backgrounds/carpatos/carpatos-default.svg'
picture-uri-dark='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-options='zoom'
primary-color='#1c2a4a'
show-desktop-icons=true

# --- Profile `GNOME-Greeter` (login screen) ---
[org.gnome.desktop.background:GNOME-Greeter]
picture-uri='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-uri-dark='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-options='zoom'
primary-color='#0a0e1a'
show-desktop-icons=false

# --- Screensaver ---
[org.gnome.desktop.screensaver]
picture-uri='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-options='zoom'

[org.gnome.desktop.screensaver:ubuntu]
picture-uri='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-options='zoom'

# --- Tema interfata (toate profilele) ---
[org.gnome.desktop.interface]
color-scheme='prefer-dark'
icon-theme='Adwaita'
cursor-theme='Adwaita'

[org.gnome.desktop.interface:ubuntu]
color-scheme='prefer-dark'
icon-theme='Adwaita'
cursor-theme='Adwaita'

# --- gnome-shell favorite apps ---
[org.gnome.shell]
favorite-apps=['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.Settings.desktop']

[org.gnome.shell:ubuntu]
favorite-apps=['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.Settings.desktop']

# --- dash-to-dock pozitie ---
[org.gnome.shell.extensions.dash-to-dock]
dock-position='BOTTOM'
extend-height=false
dock-fixed=false
custom-theme-shrink=true

[org.gnome.shell.extensions.dash-to-dock:ubuntu]
dock-position='BOTTOM'
extend-height=false
dock-fixed=false
custom-theme-shrink=true
EOF

chmod 0644 "$SCHEMA_DIR/90_carpatos-defaults.gschema.override"
