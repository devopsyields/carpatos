#!/bin/sh
# build.sh — instaleaza /etc/os-release si /etc/lsb-release pentru CarpatOS
set -eu

install -d "$DESTDIR/etc"

cat > "$DESTDIR/etc/os-release" <<'EOF'
NAME="CarpatOS"
VERSION="1.0"
ID=carpatos
ID_LIKE="ubuntu debian"
PRETTY_NAME="CarpatOS Desktop 1.0"
VERSION_ID="1.0"
HOME_URL="https://github.com/devopsyields/carpatos"
SUPPORT_URL="https://github.com/devopsyields/carpatos/issues"
BUG_REPORT_URL="https://github.com/devopsyields/carpatos/issues"
LOGO=carpatos
EOF

cat > "$DESTDIR/etc/lsb-release" <<'EOF'
DISTRIB_ID=CarpatOS
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=carpatos
DISTRIB_DESCRIPTION="CarpatOS Desktop 1.0"
EOF

chmod 0644 "$DESTDIR/etc/os-release" "$DESTDIR/etc/lsb-release"
