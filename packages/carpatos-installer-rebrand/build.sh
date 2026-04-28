#!/bin/sh
# build.sh — rebrand vizibil installer Ubuntu -> CarpatOS
#
# .desktop files (rulate la apasarea pe icon): suprascriem Name + Comment +
# Icon ca sa zica CarpatOS. Stringurile din wizard-ul GUI insusi (titlul
# ferestrei, butoanele) raman Ubuntu — patchul lor e in /usr/share/ubiquity
# si necesita modificari Python+Glade. Acceptat ca trade-off MVP.
set -eu

install -d "$DESTDIR/usr/share/applications"
install -d "$DESTDIR/etc/xdg/autostart"

# install-debian.desktop — link de pe desktop pentru "Install ..."
cat > "$DESTDIR/usr/share/applications/install-debian.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Name=Instaleaza CarpatOS
Name[ro]=Instaleaza CarpatOS
Comment=Porneste instalarea CarpatOS Desktop pe disk
Exec=ubiquity gtk_ui
Icon=carpatos
Terminal=false
Type=Application
Categories=GTK;System;
StartupNotify=true
EOF

# ubiquity.desktop — versiunea alternativa folosita de unele variante
cat > "$DESTDIR/usr/share/applications/ubiquity.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Name=Instaleaza CarpatOS
Name[ro]=Instaleaza CarpatOS
Comment=Porneste instalarea CarpatOS Desktop pe disk
Exec=ubiquity gtk_ui
Icon=carpatos
Terminal=false
Type=Application
Categories=GTK;System;
StartupNotify=true
EOF

# Suprascriem si scurtatura "Live system installer" cu acelasi text
cat > "$DESTDIR/usr/share/applications/casper-launcher.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Name=Instaleaza CarpatOS
Name[ro]=Instaleaza CarpatOS
Comment=Porneste instalarea CarpatOS Desktop pe disk
Exec=ubiquity gtk_ui
Icon=carpatos
Terminal=false
Type=Application
Categories=GTK;System;
NoDisplay=false
EOF

# Welcome screen (gnome-initial-setup) ruleaza la primul login dupa
# instalare. Are texte "Welcome to Ubuntu" hardcoded in pachet —
# greu de patch fara recompilare. Solutie minimala: dezactivam autostart
# ca utilizatorul sa sara peste el direct la desktop.
install -m 0644 /dev/null "$DESTDIR/etc/xdg/autostart/gnome-initial-setup-first-login.desktop"
install -m 0644 /dev/null "$DESTDIR/etc/xdg/autostart/gnome-initial-setup-copy-worker.desktop"

# Suprascriem si "First Launch" / Welcome al Ubuntu (daca exista)
install -m 0644 /dev/null "$DESTDIR/etc/xdg/autostart/ubuntu-welcome.desktop" 2>/dev/null || true

# GNOME Tour — Welcome wizard care apare la primul login si zice
# "Welcome to Ubuntu". Numele real e `org.gnome.Tour.desktop`. Dezactivat
# prin xdg autostart vid + .desktop NoDisplay + sterge state file.
install -m 0644 /dev/null "$DESTDIR/etc/xdg/autostart/gnome-tour.desktop"
install -m 0644 /dev/null "$DESTDIR/etc/xdg/autostart/org.gnome.Tour.desktop"
cat > "$DESTDIR/usr/share/applications/org.gnome.Tour.desktop" <<'EOF'
[Desktop Entry]
Name=GNOME Tour
NoDisplay=true
Hidden=true
Type=Application
EOF
cat > "$DESTDIR/usr/share/applications/gnome-tour.desktop" <<'EOF'
[Desktop Entry]
Name=GNOME Tour
NoDisplay=true
Hidden=true
Type=Application
EOF
# Marcheaza tour-ul ca rulat deja prin gsettings persistat
install -d "$DESTDIR/usr/share/glib-2.0/schemas"
cat > "$DESTDIR/usr/share/glib-2.0/schemas/95_carpatos-no-tour.gschema.override" <<'EOF'
# Disable GNOME Tour Welcome wizard la live boot.
[org.gnome.shell]
welcome-dialog-last-shown-version='99.99'
EOF

chmod 0644 "$DESTDIR/usr/share/applications"/*.desktop

# gnome-initial-setup este de fapt declansat de systemd USER services,
# NU de xdg autostart. xdg autostart .desktop empty nu opreste nimic.
# Mask-uim serviciile prin symlink la /dev/null (systemd skip-uieste).
install -d "$DESTDIR/etc/systemd/user"
for svc in gnome-initial-setup-copy-worker.service \
           gnome-initial-setup-first-login.service \
           org.gnome.Shell.Welcome.target \
           gnome-session@gnome-initial-setup.target; do
    ln -sf /dev/null "$DESTDIR/etc/systemd/user/$svc"
done

# Pentru Welcome at /usr/share/ubuntu/applications/gnome-initial-setup.desktop
# (cale specifica Ubuntu), suprascriem cu NoDisplay=true ca shell-ul sa nu-l
# afiseze niciunde.
install -d "$DESTDIR/usr/share/ubuntu/applications"
cat > "$DESTDIR/usr/share/ubuntu/applications/gnome-initial-setup.desktop" <<'EOF'
[Desktop Entry]
Name=Welcome
NoDisplay=true
Hidden=true
Type=Application
EOF

# Logo ubiquity — suprascriem cu logo-ul carpatos. Ubiquity citeste
# /usr/share/ubiquity/pixmaps/{logo,icon-fullcolor}.png si afiseaza in
# titlul ferestrei. Inlocuim cu logo-ul nostru SVG (rsvg compatible).
install -d "$DESTDIR/usr/share/ubiquity/pixmaps"
# Pentru a folosi SVG-ul nostru ca PNG, trebuie sa-l rasterizam.
# Aici punem un PNG dummy minimal (1x1 pixel transparent) — ubiquity
# afiseaza tot textul "Instaleaza CarpatOS" din .desktop, doar logo-ul
# vizual din wizard ramane fără. TODO: rasterizare SVG -> PNG la build.
# Continut PNG 1x1 transparent (binary safe via printf hex):
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82' \
    > "$DESTDIR/usr/share/ubiquity/pixmaps/logo.png" 2>/dev/null || true

# In Ubuntu noble desktop: gnome-shell-extension-ubuntu-dock are
# branding "Ubuntu Dock" la setari. Dezactivam complet (am pus dock
# customizat in carpatos-gnome-defaults).
install -m 0644 /dev/null "$DESTDIR/etc/xdg/autostart/ubuntu-dock.desktop" 2>/dev/null || true
