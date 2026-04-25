#!/usr/bin/env python3
"""deb2cpm — convertor Debian .deb -> CarpatOS .cpm.

Utilizare CLI:
    deb2cpm.py <intrare.deb> [-o <iesire.cpm>]

Poate fi folosit si ca modul: `from deb2cpm import converteste_deb`.

Format .deb: arhiva ar cu debian-binary, control.tar.<comp>, data.tar.<comp>.
Format .cpm: antet 16B (magic+ver+mlen+plen) + manifest text + tar USTAR.
"""
from __future__ import annotations

import argparse
import gzip
import io
import lzma
import os
import re
import struct
import subprocess
import sys
import tarfile
from pathlib import Path
from typing import Iterable

CPM_MAGIC = 0x004D5043  # "CPM\0"
CPM_FORMAT_VER = 1

ARCH_MAP = {
    "arm64": "aarch64",
    "amd64": "x86_64",
    "i386": "i386",
    "armhf": "armv7",
    "all": "any",
}


# -------- ar archive reader ---------------------------------------------------

class ArError(Exception):
    pass


def ar_iter(data: bytes) -> Iterable[tuple[str, bytes]]:
    """Itereaza prin membrii unei arhive ar, producand (nume, continut)."""
    if data[:8] != b"!<arch>\n":
        raise ArError("lipseste semnatura ar '!<arch>'")
    off = 8
    while off < len(data):
        if len(data) - off < 60:
            raise ArError("header ar trunchiat")
        name = data[off:off + 16].rstrip(b" ").decode("ascii", errors="replace")
        size_str = data[off + 48:off + 58].rstrip(b" ").decode("ascii", errors="replace")
        magic = data[off + 58:off + 60]
        if magic != b"`\n":
            raise ArError(f"magic sfarsit-header incorect: {magic!r}")
        try:
            size = int(size_str)
        except ValueError as e:
            raise ArError(f"dimensiune invalida '{size_str}'") from e
        body_off = off + 60
        body_end = body_off + size
        if body_end > len(data):
            raise ArError("corp membru trunchiat")
        # Debian foloseste nume terminate in '/', fara tabela lunga GNU.
        clean = name.rstrip("/")
        yield clean, data[body_off:body_end]
        # padding la numar par de octeti
        off = body_end + (body_end & 1)


# -------- decompression -------------------------------------------------------

def decompreseaza(nume: str, date: bytes) -> bytes:
    if nume.endswith(".tar"):
        return date
    if nume.endswith(".tar.gz") or nume.endswith(".tar.gzip"):
        return gzip.decompress(date)
    if nume.endswith(".tar.xz"):
        return lzma.decompress(date)
    if nume.endswith(".tar.zst") or nume.endswith(".tar.zstd"):
        return zstd_decompress(date)
    raise ValueError(f"compresie necunoscuta pentru {nume}")


def zstd_decompress(date: bytes) -> bytes:
    """Ruleaza `zstd -d` ca subproces. Evita dependenta Python `zstandard`."""
    try:
        rez = subprocess.run(
            ["zstd", "-d", "-q", "--stdout"],
            input=date, capture_output=True, check=True,
        )
    except FileNotFoundError as e:
        raise RuntimeError("binarul 'zstd' lipseste din PATH") from e
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"zstd a esuat: {e.stderr!r}") from e
    return rez.stdout


# -------- Debian control parsing ---------------------------------------------

def parseaza_control(text: str) -> dict[str, str]:
    """Parseaza un camp control Debian simplu in dict. Campurile continuate
    (linii ce incep cu spatiu) sunt alipite — primul paragraph este cel
    relevant pentru pachetul binar (chiar daca .deb contine si Source)."""
    campuri: dict[str, str] = {}
    cheie_curenta: str | None = None
    for linie in text.splitlines():
        if not linie.strip():
            # paragraph terminat — primul paragraph e cel care ne intereseaza
            if campuri:
                break
            continue
        if linie[0] in " \t":
            if cheie_curenta is not None:
                campuri[cheie_curenta] += "\n" + linie.strip()
            continue
        m = re.match(r"([A-Za-z0-9\-]+)\s*:\s*(.*)", linie)
        if not m:
            continue
        cheie_curenta = m.group(1)
        campuri[cheie_curenta] = m.group(2)
    return campuri


def mapeaza_arh(arh_deb: str) -> str:
    return ARCH_MAP.get(arh_deb, arh_deb)


def extrage_descriere_scurta(descriere_raw: str) -> str:
    # Debian Description: prima linie = short, apoi continuari cu spatii.
    prima = descriere_raw.split("\n", 1)[0].strip()
    # Cpm MAX_DESCRIERE = 256 — pastram scurta
    return prima[:250]


def normalizeaza_depinde(depinde_raw: str) -> str:
    """Transforma 'libc6 (>= 2.34), libgcc-s1 (>= 3.0) | other' -> 'libc6,libgcc-s1'.
    Stripeaza calificative versiune si de arhitectura (':any', ':amd64')."""
    if not depinde_raw.strip():
        return ""
    rezultat: list[str] = []
    for bucata in depinde_raw.split(","):
        # alternativele "a | b" — luam prima
        alt = bucata.split("|", 1)[0].strip()
        # strip "(constraint)"
        alt = re.sub(r"\s*\(.*?\)", "", alt).strip()
        # strip ":arch"
        alt = alt.split(":", 1)[0].strip()
        if alt:
            rezultat.append(alt)
    return ",".join(rezultat)


# -------- tar rewrite ---------------------------------------------------------

def rescrie_tar_ustar(date_intrare: bytes) -> bytes:
    """Citeste un tar oarecare (USTAR/pax/gnu) si il rescrie ca USTAR pur
    necomprimat. Previne simboluri GNU LongLink si altele. Arunca ValueError
    daca un membru depaseste limita USTAR (155 prefix + 100 nume)."""
    iesire = io.BytesIO()
    with tarfile.open(fileobj=io.BytesIO(date_intrare), mode="r:*") as ti:
        with tarfile.open(fileobj=iesire, mode="w", format=tarfile.USTAR_FORMAT) as to:
            for membru in ti:
                if len(membru.name) > 255:
                    raise ValueError(
                        f"nume fisier depaseste 255 octeti (USTAR): {membru.name}")
                # Curata path-uri absolute / '../' — tarfile le normalizeaza
                # cu filter 'data' (Python 3.12+). Pe 3.11 foloseste 'data'
                # manual cand e posibil.
                if membru.issym() or membru.islnk():
                    if len(membru.linkname) > 100:
                        raise ValueError(
                            f"linkname > 100 octeti (USTAR): {membru.linkname}")
                if membru.isfile():
                    f = ti.extractfile(membru)
                    to.addfile(membru, f)
                else:
                    to.addfile(membru)
    return iesire.getvalue()


# -------- main conversion -----------------------------------------------------

def converteste_deb(cale_deb: Path, cale_cpm: Path | None = None) -> Path:
    date = cale_deb.read_bytes()

    control_date: bytes | None = None
    data_date: bytes | None = None
    control_nume = ""
    data_nume = ""
    for nume, corp in ar_iter(date):
        if nume.startswith("control.tar"):
            control_nume = nume
            control_date = corp
        elif nume.startswith("data.tar"):
            data_nume = nume
            data_date = corp
    if control_date is None:
        raise ValueError(f"{cale_deb}: lipseste control.tar.* in .deb")
    if data_date is None:
        raise ValueError(f"{cale_deb}: lipseste data.tar.* in .deb")

    control_tar = decompreseaza(control_nume, control_date)
    data_tar = decompreseaza(data_nume, data_date)

    # control.tar contine fisierul 'control' (poate la './control' sau 'control')
    control_text = ""
    with tarfile.open(fileobj=io.BytesIO(control_tar), mode="r:") as ti:
        for membru in ti:
            nume_norm = membru.name.lstrip("./")
            if nume_norm == "control" and membru.isfile():
                f = ti.extractfile(membru)
                control_text = f.read().decode("utf-8", errors="replace")
                break
    if not control_text:
        raise ValueError(f"{cale_deb}: control/control nu a fost gasit")

    campuri = parseaza_control(control_text)
    nume_pkg = campuri.get("Package", "").strip()
    if not nume_pkg:
        raise ValueError(f"{cale_deb}: camp Package absent")

    # Pre-Depends si Depends sunt ambele obligatorii la instalare in Debian.
    # Recommends/Suggests sunt optionale, le ignoram.
    deps_brut = ", ".join(
        x for x in (campuri.get("Pre-Depends", ""), campuri.get("Depends", ""))
        if x.strip()
    )

    manifest = {
        "nume": nume_pkg,
        "versiune": campuri.get("Version", "0").strip(),
        "arhitectura": mapeaza_arh(campuri.get("Architecture", "any").strip()),
        "descriere": extrage_descriere_scurta(campuri.get("Description", "")),
        "depinde": normalizeaza_depinde(deps_brut),
    }

    payload = rescrie_tar_ustar(data_tar)

    if cale_cpm is None:
        cale_cpm = cale_deb.with_suffix(".cpm")

    scrie_cpm(cale_cpm, manifest, payload)
    return cale_cpm


def serializeaza_manifest(m: dict[str, str]) -> bytes:
    linii = [
        f"nume={m['nume']}",
        f"versiune={m['versiune']}",
        f"arhitectura={m['arhitectura']}",
        f"descriere={m['descriere']}",
        f"depinde={m['depinde']}",
    ]
    return ("\n".join(linii) + "\n").encode("utf-8")


def scrie_cpm(cale: Path, manifest: dict[str, str], payload: bytes) -> None:
    mbuf = serializeaza_manifest(manifest)
    antet = struct.pack("<IIII", CPM_MAGIC, CPM_FORMAT_VER, len(mbuf), len(payload))
    with cale.open("wb") as f:
        f.write(antet)
        f.write(mbuf)
        f.write(payload)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Converteste .deb -> .cpm (CarpatOS)")
    p.add_argument("deb", help="fisierul .deb de intrare")
    p.add_argument("-o", "--output", help="fisierul .cpm de iesire")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args(argv)

    cale_deb = Path(args.deb)
    cale_cpm = Path(args.output) if args.output else None
    try:
        rezultat = converteste_deb(cale_deb, cale_cpm)
    except (ArError, ValueError, RuntimeError) as e:
        print(f"deb2cpm: eroare: {e}", file=sys.stderr)
        return 1
    if args.verbose:
        dim = rezultat.stat().st_size
        print(f"scris {rezultat} ({dim} octeti)")
    else:
        print(rezultat)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
