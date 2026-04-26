#!/usr/bin/env python3
"""build-cpm-repo — construieste un repo .cpm din Ubuntu ports.

Flux:
  1. Descarca Packages.gz pt fiecare component (main / universe / etc.).
  2. BFS prin Pre-Depends + Depends pornind de la lista de seed.
  3. Descarca fiecare .deb (cu cache pe disc).
  4. Converteste fiecare prin deb2cpm (modul scripts/deb2cpm.py).
  5. Scrie repo.index in formatul cpm (7 campuri, sha256 inclus).

Utilizare:
  build-cpm-repo.py [-o OUT] [-r noble] [-c main,universe]
                    [--seed-file FILE] [seed_pkg ...]

Output:
  OUT/pool/<nume>.cpm
  OUT/repo.index
  OUT/cache/<*.deb>     (pastrat pentru re-rulari rapide)
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import lzma
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Reuse logica deb2cpm
sys.path.insert(0, str(Path(__file__).parent))
from deb2cpm import converteste_deb  # noqa: E402

UBUNTU_BASE = "http://ports.ubuntu.com"
DEFAULT_RELEASE = "noble"          # Ubuntu 24.04 LTS
DEFAULT_ARH_DEB = "arm64"          # cpm: aarch64
DEFAULT_COMPONENTS = ["main"]
DEFAULT_USER_AGENT = "build-cpm-repo/0.1"

# Lista esentiala default (din CLAUDE.md). Se poate suprascrie cu argv
# sau cu --seed-file.
SEED_DEFAULT = [
    "bash", "coreutils", "grep", "sed", "gawk", "findutils",
    "tar", "gzip", "xz-utils", "less", "nano", "vim-tiny",
    "wget", "curl", "iproute2", "iputils-ping",
    "openssh-client", "openssh-server", "dnsutils",
    "ca-certificates", "git", "make", "gcc", "python3",
    "python3-pip", "build-essential",
]


# -------- HTTP --------

def fetch(url: str, *, timeout: float = 60.0) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": DEFAULT_USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def descarca_la(url: str, cale: Path, *, timeout: float = 120.0) -> None:
    """Descarca url -> cale, atomic (scrie .part apoi rename)."""
    cale.parent.mkdir(parents=True, exist_ok=True)
    tmp = cale.with_suffix(cale.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": DEFAULT_USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        with tmp.open("wb") as f:
            while True:
                chunk = r.read(64 * 1024)
                if not chunk:
                    break
                f.write(chunk)
    tmp.replace(cale)


# -------- Packages index --------

def descarca_packages(release: str, comp: str, arh: str,
                      cache_dir: Path) -> str:
    url = f"{UBUNTU_BASE}/dists/{release}/{comp}/binary-{arh}/Packages.gz"
    cache = cache_dir / f"Packages-{release}-{comp}-{arh}.gz"
    if not cache.exists():
        cache.parent.mkdir(parents=True, exist_ok=True)
        print(f"[idx] {url}", file=sys.stderr)
        descarca_la(url, cache)
    return gzip.decompress(cache.read_bytes()).decode("utf-8", errors="replace")


def parseaza_packages(text: str) -> dict[str, dict[str, str]]:
    """Parseaza fisierul Packages Debian -> {nume_pkg: {camp: val}}.

    Daca apar duplicate (pachete existente in mai multe versiuni), pastreaza
    ultima intrare (Packages e in general sortat cu cel mai nou la final)."""
    rezultat: dict[str, dict[str, str]] = {}
    for paragraph in text.split("\n\n"):
        if not paragraph.strip():
            continue
        fields: dict[str, str] = {}
        cheie: str | None = None
        for linie in paragraph.splitlines():
            if not linie:
                continue
            if linie[0] in (" ", "\t"):
                if cheie:
                    fields[cheie] += "\n" + linie.strip()
                continue
            m = re.match(r"([A-Za-z0-9\-]+)\s*:\s*(.*)", linie)
            if m:
                cheie = m.group(1)
                fields[cheie] = m.group(2)
        nume = fields.get("Package")
        if nume:
            rezultat[nume] = fields
    return rezultat


def construieste_index(release: str, components: list[str], arh: str,
                        cache_dir: Path) -> dict[str, dict[str, str]]:
    """Une-ste Packages din mai multe componente; in caz de coliziune,
    component-ul citat ultim castiga."""
    index: dict[str, dict[str, str]] = {}
    for comp in components:
        text = descarca_packages(release, comp, arh, cache_dir)
        index.update(parseaza_packages(text))
    return index


def construieste_provides(index: dict[str, dict[str, str]]) -> dict[str, list[str]]:
    """Mapa nume_virtual -> [pachete care il furnizeaza].

    Format Debian Provides:
      Provides: pkg-virtual1, pkg-virtual2 (= 1.0)
    Stripeaza version constraints. Pachete reale sunt mereu cuprinse in
    propriul nume (un pkg `bash` Provides-uieste implicit `bash`)."""
    provides: dict[str, list[str]] = {}
    for nume, camp in index.items():
        prov_raw = camp.get("Provides", "")
        if not prov_raw.strip():
            continue
        for v in parseaza_deps(prov_raw):  # stripeaza (= 1.0) etc.
            provides.setdefault(v, []).append(nume)
    return provides


# -------- Deps resolver --------

def parseaza_deps(raw: str) -> list[str]:
    """'libc6 (>= 2.34), x | y (>= 1.0)' -> ['libc6', 'x']."""
    iesire: list[str] = []
    if not raw.strip():
        return iesire
    for bucata in raw.split(","):
        alt = bucata.split("|", 1)[0].strip()
        alt = re.sub(r"\s*\(.*?\)", "", alt).strip()
        alt = alt.split(":", 1)[0].strip()
        if alt:
            iesire.append(alt)
    return iesire


def colecteaza_deps(seeds: list[str],
                    index: dict[str, dict[str, str]],
                    provides: dict[str, list[str]] | None = None,
                    ) -> tuple[set[str], set[str]]:
    """BFS. Cand un dep nu e in index, incercam sa-l rezolvam ca virtual
    via map-ul Provides (preferand primul provider in ordine alfabetica
    pentru determinism). Returneaza (gasite, lipsa)."""
    if provides is None:
        provides = {}
    gasite: set[str] = set()
    lipsa: set[str] = set()
    coada = list(seeds)
    while coada:
        nume = coada.pop(0)
        if nume in gasite or nume in lipsa:
            continue
        if nume not in index:
            # Incearca rezolvare ca virtual prin Provides
            cand = provides.get(nume)
            if cand:
                ales = sorted(cand)[0]  # determinism
                if ales not in gasite and ales not in lipsa:
                    coada.append(ales)
                continue
            lipsa.add(nume)
            continue
        gasite.add(nume)
        camp = index[nume]
        deps_brut = ", ".join(
            x for x in (camp.get("Pre-Depends", ""), camp.get("Depends", ""))
            if x.strip()
        )
        for d in parseaza_deps(deps_brut):
            if d not in gasite and d not in lipsa:
                coada.append(d)
    return gasite, lipsa


# -------- Download + convert --------

def descarca_deb(camp: dict[str, str], cache_dir: Path) -> Path:
    """Descarca .deb (sau foloseste cache); valideaza SHA256 din index."""
    rel_path = camp["Filename"]  # ex: pool/main/h/hello/hello_2.10..._arm64.deb
    cache = cache_dir / Path(rel_path).name
    sha_asteptat = camp.get("SHA256", "")

    if cache.exists() and sha_asteptat:
        h = hashlib.sha256(cache.read_bytes()).hexdigest()
        if h == sha_asteptat:
            return cache
        print(f"[warn] sha256 cache stricat pt {cache.name}, rede­scarc",
              file=sys.stderr)
        cache.unlink()

    if not cache.exists():
        url = f"{UBUNTU_BASE}/{rel_path}"
        print(f"[get] {camp['Package']} -> {cache.name}", file=sys.stderr)
        descarca_la(url, cache)

    if sha_asteptat:
        h = hashlib.sha256(cache.read_bytes()).hexdigest()
        if h != sha_asteptat:
            raise RuntimeError(
                f"sha256 nu match dupa download: {cache.name}\n"
                f"  asteptat: {sha_asteptat}\n  obtinut: {h}")
    return cache


# -------- Filename sanitization --------

# GitHub Releases inlocuieste tildele si alte caractere ne-standard din
# asset names cu '.'. Sanitizam noi filename-ul .cpm la generare ca
# m["fisier"] din repo.index sa pointeze la fisierul real de pe GitHub.
_FILENAME_SAFE = re.compile(r"[^a-zA-Z0-9._+-]")

def sanitize_filename(nume: str) -> str:
    return _FILENAME_SAFE.sub(".", nume)


# -------- Repo writing --------

def deps_concrete(nume: str,
                  index: dict[str, dict[str, str]],
                  provides: dict[str, list[str]],
                  gasite: set[str]) -> list[str]:
    """Pentru `nume`, returneaza lista de deps direct (Pre-Depends + Depends)
    cu virtualele inlocuite cu pachetul concret ales (cel din `gasite`).

    Daca un virtual are mai multi candidati, ales = primul (alfabetic) care
    e in `gasite`. Daca nimic nu match-ueste, dep-ul e omis."""
    if nume not in index:
        return []
    camp = index[nume]
    deps_brut = ", ".join(
        x for x in (camp.get("Pre-Depends", ""), camp.get("Depends", ""))
        if x.strip()
    )
    rezultat: list[str] = []
    for d in parseaza_deps(deps_brut):
        if d in gasite:
            rezultat.append(d)
        elif d in provides:
            for c in sorted(provides[d]):
                if c in gasite:
                    rezultat.append(c)
                    break
    return rezultat


def serializeaza_intrare_index(nume_pkg: str, m: dict[str, str],
                                cale_cpm: Path,
                                deps_override: list[str] | None = None) -> str:
    """O linie repo.index. Daca deps_override e dat, foloseste-l in locul
    lui m['depinde'] (dupa rezolvarea virtualelor)."""
    h = hashlib.sha256(cale_cpm.read_bytes()).hexdigest()
    dep = ",".join(deps_override) if deps_override is not None else m["depinde"]
    return "{nume}|{ver}|{arh}|{desc}|{dep}|{file}|{sha}\n".format(
        nume=m["nume"], ver=m["versiune"], arh=m["arhitectura"],
        desc=m["descriere"], dep=dep, file=cale_cpm.name, sha=h,
    )


def citeste_manifest_din_cpm(cale: Path) -> dict[str, str]:
    """Re-citeste manifestul scris de deb2cpm (parsare key=value)."""
    import struct
    date = cale.read_bytes()
    _, _, mlen, _ = struct.unpack("<IIII", date[:16])
    text = date[16:16 + mlen].decode("utf-8", errors="replace")
    rez: dict[str, str] = {}
    for ln in text.splitlines():
        if "=" in ln:
            k, _, v = ln.partition("=")
            rez[k.strip()] = v.strip()
    return rez


# -------- Main --------

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Construieste repo .cpm din Ubuntu ports")
    p.add_argument("seeds", nargs="*", help="pachete seed (override default)")
    p.add_argument("-o", "--output", default="build/cpm-repo",
                   help="director de output (default: build/cpm-repo)")
    p.add_argument("-r", "--release", default=DEFAULT_RELEASE)
    p.add_argument("-c", "--components", default=",".join(DEFAULT_COMPONENTS),
                   help="componente separate cu virgula")
    p.add_argument("-a", "--arh-deb", default=DEFAULT_ARH_DEB,
                   help="arhitectura Debian (default: arm64)")
    p.add_argument("--seed-file",
                   help="fisier cu un pachet seed pe linie (# = comentariu)")
    p.add_argument("--limit", type=int, default=0,
                   help="opreste dupa N pachete convertite (pentru teste)")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args(argv)

    out = Path(args.output).resolve()
    cache_dir = out / "cache"
    pool_dir = out / "pool"
    pool_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)

    seeds: list[str] = []
    if args.seeds:
        seeds = list(args.seeds)
    elif args.seed_file:
        for ln in Path(args.seed_file).read_text().splitlines():
            ln = ln.strip()
            if ln and not ln.startswith("#"):
                seeds.append(ln)
    else:
        seeds = list(SEED_DEFAULT)

    print(f"[info] seed: {len(seeds)} pachete", file=sys.stderr)
    components = [c.strip() for c in args.components.split(",") if c.strip()]
    index = construieste_index(args.release, components, args.arh_deb, cache_dir)
    provides = construieste_provides(index)
    print(f"[info] index: {len(index)} pachete in {components}, "
          f"{len(provides)} nume virtuale", file=sys.stderr)

    gasite, lipsa = colecteaza_deps(seeds, index, provides)
    print(f"[info] dupa BFS: {len(gasite)} pachete necesare", file=sys.stderr)
    if lipsa:
        print(f"[warn] {len(lipsa)} lipsa din index (provides/virtual?):",
              file=sys.stderr)
        for x in sorted(lipsa):
            print(f"       - {x}", file=sys.stderr)

    pachete_sortate = sorted(gasite)
    if args.limit:
        pachete_sortate = pachete_sortate[:args.limit]
        print(f"[info] limita activa: doar primele {args.limit}", file=sys.stderr)

    intrari_idx: list[str] = []
    erori: list[tuple[str, str]] = []
    for i, nume in enumerate(pachete_sortate, 1):
        try:
            cale_deb = descarca_deb(index[nume], cache_dir)
            cale_cpm = pool_dir / sanitize_filename(f"{cale_deb.stem}.cpm")
            if not cale_cpm.exists():
                converteste_deb(cale_deb, cale_cpm)
            m = citeste_manifest_din_cpm(cale_cpm)
            # Rescriem deps-urile cu cele concrete (virtuale rezolvate),
            # ca cpm install sa le poata trata fara cunostinte de Provides.
            deps = deps_concrete(nume, index, provides, gasite)
            intrari_idx.append(serializeaza_intrare_index(nume, m, cale_cpm, deps))
            if args.verbose:
                print(f"[{i}/{len(pachete_sortate)}] OK {nume} -> {cale_cpm.name}",
                      file=sys.stderr)
        except Exception as e:
            erori.append((nume, str(e)))
            print(f"[err] {nume}: {e}", file=sys.stderr)

    idx_path = out / "repo.index"
    idx_path.write_text("".join(sorted(intrari_idx)), encoding="utf-8")
    print(f"[done] {len(intrari_idx)} pachete in {idx_path}", file=sys.stderr)
    if erori:
        print(f"[done] {len(erori)} erori:", file=sys.stderr)
        for n, e in erori:
            print(f"       - {n}: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
