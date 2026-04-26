# CarpatOS — Ghid de context pentru Claude

## Ce e CarpatOS

O distributie Linux pentru aarch64 (Apple Silicon + Raspberry Pi 5 + alte
ARM64). Proiect personal al user-ului **Catalin Popescu**.

Directiva actuala: **CarpatOS = overlay peste Ubuntu Desktop 24.04 LTS
aarch64**. Identitatea CarpatOS sta in:
- `cpm` — package manager scris de la zero in C (statically linked)
- Pachete `.cpm` native (format propriu: header 16 bytes + manifest + tar)
- Branding propriu (wallpaper, banner ASCII, GDM greeter, icon theme)
- Repo propriu `.cpm` care serveste ca primary package manager
- `apt` ramane in sistem ca backend de fallback si pentru dependente deb

## Starea actuala (2026-04-26)

Abordarea "OS from-scratch" (kernel custom + init.c + msh shell) a fost
abandonata. Inainte eram pe pivot Alpine-based; acum sunt pe Ubuntu Desktop
24.04 LTS arm64 ca baza tehnica + overlay CarpatOS deasupra.

**Faza 4 — DONE (2026-04-25)**: deb2cpm + build-cpm-repo + cpm HTTP +
GitHub Actions. Vezi `scripts/deb2cpm.py`, `scripts/build-cpm-repo.py`,
`initramfs/src/cpm/{http,sha256}.c`, `.github/workflows/` in carpatos-repo.

**Faza 5 — in curs (2026-04-26)**: branding + ISO CarpatOS Desktop.
- ✓ 6 pachete `packages/carpatos-*` (os-release, banner, wallpapers cu
  SVG-uri proprii + logo, gnome-defaults gschema overrides, plymouth-theme,
  gdm-theme)
- ✓ `scripts/build-iso-carpatos.sh` (Ubuntu Desktop ISO -> CarpatOS ISO)
  — neconfirmat la rulare (necesita Linux arm64 + sudo)
- ⏭ Workflow GitHub Actions pentru build ISO automat (runner arm64)

**Repo distributie**: https://github.com/devopsyields/carpatos-repo
- Tag `v0.2-essentials`: ubuntu-desktop-minimal + tools dev = ~850 pachete
- Tag `latest-weekly`: rebuild Sambata 04:00 UTC (cron in workflow)

## Comunicare cu user

- **Limba**: romana fara diacritice (ASCII-safe). Toate mesajele, comentariile,
  output-ul binarelor — in romana simpla.
- **Identificatori cod**: engleza (POSIX + toolchain compatibility).
- **Stil**: user e expert tehnic. Raspunsuri scurte, concrete, directe. Nu
  explicatii lungi de concepte de baza (musl, initramfs, UEFI, framebuffer).
- **Autorizare comenzi**: user a permis rularea fara confirmare pentru a
  merge mai repede. Aplicat deja la acest proiect.

## Ce tine CarpatOS distinct

1. **`cpm`** — package manager C (initramfs/src/cpm/). Comenzi: install,
   remove, local, list, search, info, update, build. Format pachet:
   - Antet 16 bytes: magic 0x004d5043 "CPM\0" + versiune format + manifest_len + payload_len
   - Manifest text key=value (nume, versiune, arhitectura, descriere, depinde)
   - Payload: tar USTAR necomprimata
2. **Variabila env `CPM_ROOT`** — prefixeaza path-urile DIR_* cu un directory
   (pentru build cu staged rootfs)
3. **`CPMBUILD`** — fisier manifest per pachet sursa (similar PKGBUILD Arch)
4. **Pachetele demo**: `hello`, `adevarat` (exit 0), `fals` (exit 1), `ecou`
   (echo in C)

## Structura proiect

```
carpatos/
├── initramfs/src/cpm/    # package manager C (principal contributie CarpatOS)
├── initramfs/src/init/   # init.c MVP (legacy, neutilizat dupa pivot)
├── initramfs/src/msh/    # shell minimal (legacy)
├── packages/             # pachete demo + LUPBUILD (acum CPMBUILD)
├── kernel/               # kernel custom (LEGACY — nu mai folosim)
├── boot/limine.conf      # Limine config (LEGACY)
├── scripts/              # build-packages.sh, build-iso.sh, build-disk.sh
├── alpine-based/         # experiment 23 apr — pivot Alpine (semi-abandonat
│                         #   in favoarea Ubuntu, dar scripts de referinta
│                         #   pentru apkovl/xorriso)
├── toolchain/Dockerfile  # cross-compiler aarch64-linux-musl + Limine +
│                         # xorriso + gdisk + mtools
├── docs/                 # CONSTRUIRE.md, ARHITECTURA.md, PARALLELS.md, CPMBUILD.md
└── PROMPT-CLAUDE-CODE.md # spec format .cpm + comenzile cpm
```

## Infrastructura build

- **Toolchain Docker**: `docker build -t carpatos-toolchain toolchain/`
  (contine cross-compiler musl aarch64, xorriso, gdisk, mtools). Imagine
  ~2 GB.
- **Build**: `docker run --rm -v "$(pwd):/src" -w /src carpatos-toolchain <cmd>`

## Partea macvm — proiect separat

User are la `~/projects/macvm/` o aplicatie Swift proprie bazata pe Apple
Virtualization.framework (SwiftUI + AppKit).

**Blocant confirmat pe macOS 26 Tahoe**: keyboard + mouse nu ajung la guest
in macvm (tot USB HID path broken), dar merg perfect in **UTM cu Apple Vz**
pe aceeasi masina. Concluzie: bug in macvm-ul user-ului, nu Apple Vz
framework. Fix-uri aplicate pana acum: security scope pentru ISO, auto-focus,
NSEvent monitor local, AppDelegate cu NSWindow AppKit pur — toate n-au
rezolvat. Fisiere cheie: `Packages/MacVMCore/Sources/MacVMCore/VM/VMManager.swift`,
`MacVMApp/Views/VMDisplayView.swift`, `MacVMApp/AppDelegate.swift`.

**Pentru dezvoltare CarpatOS, folosim UTM, nu macvm**.

## Plan FAZA 4 — conversie deb → cpm + repo

### Tool `deb2cpm`
- Python 3 script, takes `.deb`, outputs `.cpm`
- Parse ar archive: `debian-binary`, `control.tar.*`, `data.tar.*`
- Map Debian control → cpm manifest
- Recomprima data.tar.* ca tar USTAR simplu
- Preserveaza dependente (format: `depinde=pkg1,pkg2`)

### Tool `build-cpm-repo`
- Input: lista de nume pachete essentials Ubuntu
- Descarca `.deb` de la `http://ports.ubuntu.com/pool/main/.../` pentru arm64
- Resolve deps transitive (recursiv)
- Convert fiecare cu `deb2cpm`
- Genereaza `repo.index` — format cpm existent
- Output: `pool/*.cpm` + `repo.index`

### Extindere cpm cu remote
- `cpm update` descarca `https://repo.carpatos.ORG/repo.index` la `/var/cpm/db/`
- `cpm install <nume>` — cauta in index, HTTP GET, unpack + verify sha256
- Cache in `/var/cpm/cache/`
- Adaug field sha256 in manifest + repo.index

### Hosting
- Initial: **GitHub Releases** (2 GB/release limit — OK pentru initial ~50 pachete)
- Apoi: domeniu propriu (user vrea `.org`, nu `.ro` — probabil `carpatos.org`)
- Build automation: GitHub Actions care ruleaza `build-cpm-repo` la fiecare release

### Lista initiala essentials (~50 pachete varf, ~500 cu deps)
```
bash, coreutils, grep, sed, gawk, findutils, tar, gzip, xz-utils, less,
nano, vim-tiny, wget, curl, iproute2, iputils-ping, openssh-client,
openssh-server, dnsutils, ca-certificates, git, make, gcc, python3,
python3-pip, build-essential, gnome-terminal, nautilus, gedit, eog,
firefox, libreoffice, vlc, code
```

## Cerinte spatiu

- Ubuntu Desktop 24.04 ISO: ~5 GB
- Rootfs unsquashed pentru modificari: ~15-20 GB
- `.deb` essentials descarcate: ~5-8 GB
- `.cpm` output: ~5-8 GB
- Working space ISO rebuild: ~10 GB
- **Total working**: ~40-50 GB
- Git repo + sources: ~5-10 GB

Pe Mac-ul principal al user-ului **nu incape** (3.1 GB liber din 228 GB la
2026-04-24). Munca e planificata sa continue pe laptop cu mai mult spatiu.

## Instructiuni specifice comportament

- NU scrie documentatie cu diacritice
- NU sugera rewrite-uri din senin
- NU propune abordari "sa rescriu totul in X" fara sa intreb
- CONFIRMA cand ai ambiguitate
- La decizii majore arhitecturale (ex: pivot Alpine → Ubuntu), explicam
  trade-off-urile si astept acord
- User nu vrea confirmari la fiecare comanda individual (permisiune data)
- Daca ruleaza lung (>1 min), pune in background cu notificare la final

## Referinte externe

- Ubuntu 24.04 aarch64 ISOs: https://cdimage.ubuntu.com/releases/24.04/release/
- Ubuntu archive ports (aarch64): http://ports.ubuntu.com/pool/
- Apple Virtualization.framework docs
- UTM: https://getutm.app/ (open source, Apple Vz + QEMU)
- Alpine Linux live scripts: /tmp/alp-init/init (extract initramfs-virt)
