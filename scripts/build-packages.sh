#!/usr/bin/env bash
# build-packages.sh — construieste pachetele demo CarpatOS
#
# Folosire:
#   ./scripts/build-packages.sh [arch]
#     arch: x86_64 (implicit) | aarch64 | any
#
# Iesire: packages/build/<arch>/<nume>-<ver>-<arh>.cpm
#
# Dependente: `cpm` compilat pentru host (nu pentru tinta) si
# toolchain-ul cross `<arch>-linux-musl-gcc` pentru pachetele native.
# Pachetul `hello` (arh=any) nu are nevoie de cross-compiler.
set -euo pipefail

ARCH="${1:-x86_64}"

case "$ARCH" in
    x86_64|aarch64|any) ;;
    *)
        echo "EROARE: ARCH necunoscut: $ARCH (suportat: x86_64, aarch64, any)" >&2
        exit 1
        ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CPM_SRC="$ROOT/initramfs/src/cpm"
OUT_DIR="$ROOT/packages/build/$ARCH"
CPM_BIN="$CPM_SRC/cpm_host"

mkdir -p "$OUT_DIR"

# Compileaza `cpm` pentru host daca nu exista deja
if [[ ! -x "$CPM_BIN" ]]; then
    echo "==> Construiesc cpm pentru host (pentru operatii de build)"
    (
        cd "$CPM_SRC"
        cc -std=c11 -Wall -Wextra -O2 -I../common \
           -o cpm_host main.c util.c manifest.c tar.c pkg.c db.c repo.c \
           cmd_install.c cmd_remove.c cmd_query.c cmd_build.c
    )
fi

construieste() {
    local pachet="$1"
    local override_arh="${2:-}"
    local dir="$ROOT/packages/$pachet"
    [[ -d "$dir" ]] || { echo "Pachet lipsa: $dir" >&2; exit 1; }

    echo "==> Construiesc $pachet (arh=${override_arh:-<din CPMBUILD>})"
    local argv=("$dir")
    if [[ -n "$override_arh" ]]; then
        argv+=("--arch" "$override_arh")
    fi
    (
        cd "$OUT_DIR"
        "$CPM_BIN" build "${argv[@]}"
    )
}

# hello e script, arh=any din CPMBUILD — fara override
construieste hello

# Pachetele native: override daca ARCH != x86_64 (implicit in CPMBUILD)
# Daca ARCH=any (edge-case), le sarim peste — n-are sens fara cross.
if [[ "$ARCH" != "any" ]]; then
    construieste adevarat "$ARCH"
    construieste fals     "$ARCH"
    construieste ecou     "$ARCH"
fi

echo "==> Gata. Pachete in $OUT_DIR:"
ls -la "$OUT_DIR"
