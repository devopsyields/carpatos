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
