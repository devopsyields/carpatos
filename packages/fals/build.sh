#!/bin/sh
# build.sh — compileaza fals static pentru PKG_ARH
set -eu

: "${PKG_ARH:?PKG_ARH lipseste}"
: "${DESTDIR:?DESTDIR lipseste}"

CC="${CC:-${PKG_ARH}-linux-musl-gcc}"
CFLAGS="${CFLAGS:--O2 -Wall -Wextra -static -s}"

install -d "$DESTDIR/bin"
$CC $CFLAGS -o "$DESTDIR/bin/fals" fals.c
