#!/bin/sh
# build.sh — instaleaza hello ca script shell executabil
set -eu

install -d "$DESTDIR/bin"
cat > "$DESTDIR/bin/hello" <<'EOF'
#!/bin/msh
echo Salut din CarpatOS!
EOF
chmod 0755 "$DESTDIR/bin/hello"
