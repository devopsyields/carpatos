#!/bin/sh
# build.sh — instaleaza banner-uri pentru /etc/issue, issue.net, motd
set -eu

install -d "$DESTDIR/etc"

# /etc/motd — afisat dupa login. Foloseste box-drawing (UTF-8) +
# stilizare cu munti pentru tema Carpati. Functioneaza pe orice
# console UTF-8 (default in Ubuntu/CarpatOS).
cat > "$DESTDIR/etc/motd" <<'EOF'

       /\           /\           /\           /\
      /  \         /  \         /  \         /  \
     / /\ \       / /\ \       / /\ \       / /\ \
    / /  \ \     / /  \ \     / /  \ \     / /  \ \
   /_/    \_\   /_/    \_\   /_/    \_\   /_/    \_\

      ╔═══════════════════════════════════╗
      ║         CarpatOS Desktop          ║
      ║              v1.0                 ║
      ╚═══════════════════════════════════╝

   Bun venit. Proiect personal Catalin Popescu.
   https://github.com/devopsyields/carpatos

EOF

# /etc/issue — afisat inainte de prompt-ul de login pe TTY.
# Escape-uri getty: \n=hostname, \l=tty
cat > "$DESTDIR/etc/issue" <<'EOF'

      CarpatOS Desktop 1.0
      \n  (\l)

EOF

# /etc/issue.net — login retea (telnet/ssh banner). Fara escape-uri.
cat > "$DESTDIR/etc/issue.net" <<'EOF'
CarpatOS Desktop 1.0
EOF

chmod 0644 "$DESTDIR/etc/motd" "$DESTDIR/etc/issue" "$DESTDIR/etc/issue.net"

# /etc/legal — Ubuntu pune un text "The programs included with the Ubuntu
# system are free software; ...". Suprascriem cu un text scurt CarpatOS.
cat > "$DESTDIR/etc/legal" <<'EOF'
CarpatOS Desktop — distributie Linux peste Ubuntu LTS.
Toate pachetele incluse au licente proprii — vezi /usr/share/doc/<pachet>.
EOF
chmod 0644 "$DESTDIR/etc/legal"

# /etc/update-motd.d — script-uri executabile rulate la SSH/TTY login.
# Ubuntu pune aici "Welcome to Ubuntu", "documentation: https://help.ubuntu.com",
# "esm-apps", "release-upgrade", etc. Le suprascriem cu fisiere goale
# (fara executable bit) ca sa nu mai ruleze.
install -d "$DESTDIR/etc/update-motd.d"
for f in 00-header 10-help-text 50-motd-news 90-updates-available \
         91-contract-ubuntu-support 91-release-upgrade 95-hwe-eol \
         98-fsck-at-reboot 98-reboot-required; do
    install -m 0644 /dev/null "$DESTDIR/etc/update-motd.d/$f"
done

# Adaug propriul nostru header carpatos (executat la login interactiv)
cat > "$DESTDIR/etc/update-motd.d/01-carpatos" <<'EOF'
#!/bin/sh
# 01-carpatos — header dinamic la login.
echo
echo "  CarpatOS Desktop 1.0  ($(uname -m))"
echo "  https://github.com/devopsyields/carpatos"
echo
EOF
chmod 0755 "$DESTDIR/etc/update-motd.d/01-carpatos"

# Shell prompt CarpatOS — overlay peste /etc/bash.bashrc default Ubuntu.
# Activeaza un PS1 distinctiv (verde/auriu in loc de verde/albastru Ubuntu)
# pentru orice shell interactiv. Nume gazda colorat in auriu Carpati.
install -d "$DESTDIR/etc/profile.d"
cat > "$DESTDIR/etc/profile.d/carpatos-prompt.sh" <<'EOF'
# carpatos-prompt — PS1 distinctiv pentru CarpatOS, overlay peste default
# Ubuntu. Sourceat la fiecare login interactiv prin /etc/profile sau
# bash invokat ca login shell.
if [ -n "$BASH_VERSION" ] && [ "${PS1:-}" ] && case "$TERM" in xterm*|rxvt*|screen*|tmux*|linux) true ;; *) false ;; esac; then
    # Verde mai inchis (mountains green) + galben auriu (Carpati sunset)
    PS1='\[\033[01;32m\]\u\[\033[00m\]@\[\033[01;33m\]\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi
EOF
chmod 0644 "$DESTDIR/etc/profile.d/carpatos-prompt.sh"
