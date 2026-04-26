#!/bin/sh
# build.sh — branding GDM (login screen) pentru CarpatOS
#
# Modern GDM (Ubuntu 24.04) citeste setarile din /etc/dconf/db/gdm.d/.
# Dupa instalare, ISO build ruleaza `dconf update` ca sa compileze
# baza de date binara /etc/dconf/db/gdm.
set -eu

DCONF_DIR="$DESTDIR/etc/dconf/db/gdm.d"
PROFILE_DIR="$DESTDIR/etc/dconf/profile"
install -d "$DCONF_DIR" "$PROFILE_DIR"

# Profil GDM: spune ca sursele sunt /etc/dconf/db/gdm
cat > "$PROFILE_DIR/gdm" <<'EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF

# Override pentru greeter (login screen). Wallpaper noapte CarpatOS,
# tema dark, accent albastru.
cat > "$DCONF_DIR/01-carpatos-greeter" <<'EOF'
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-uri-dark='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'
picture-options='zoom'
primary-color='#0a0e1a'

[org/gnome/desktop/interface]
color-scheme='prefer-dark'
accent-color='blue'
icon-theme='Yaru'
cursor-theme='Yaru'

[org/gnome/desktop/screensaver]
picture-uri='file:///usr/share/backgrounds/carpatos/carpatos-night.svg'

[org/gnome/login-screen]
logo='/usr/share/pixmaps/carpatos.svg'
banner-message-enable=true
banner-message-text='CarpatOS Desktop 1.0'
EOF

chmod 0644 "$PROFILE_DIR/gdm" "$DCONF_DIR/01-carpatos-greeter"
