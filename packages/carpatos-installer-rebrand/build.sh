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

chmod 0644 "$DESTDIR/usr/share/applications"/*.desktop
