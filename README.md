# CarpatOS

> Distributie Linux minimalistă stil Alpine, cu package manager propriu (`cpm`)
> si userland scris de la zero in C. Toata interactiunea cu utilizatorul este
> in limba romana.

## Stadiu

**Faza 1 + package manager.** Sistem care porneste in QEMU sau
Parallels (BIOS sau UEFI), monteaza pseudo-filesystem-urile, si prezinta
un shell minim (`msh`). `cpm`, package managerul, functioneaza si are
patru pachete demo. Suport multi-arch pentru **x86_64** si **aarch64**.

## Componente

| Componenta | Ce este | Unde |
|---|---|---|
| Kernel | Linux vanilla (6.12 LTS), config minimal | `kernel/` |
| Bootloader | Limine (BIOS+UEFI pe x86_64, UEFI pe aarch64) | `boot/` |
| init (PID 1) | Propriu, C + musl static | `initramfs/src/init/` |
| msh | Shell minim (interactiv + script mode) | `initramfs/src/msh/` |
| lup | Package manager (`install`/`remove`/`build`/...) | `initramfs/src/lup/` |
| Pachete demo | `hello`, `adevarat`, `fals`, `ecou` | `packages/` |
| libc | musl, static linked | (inclus in toolchain) |

## Quick start

### 1. Construieste containerul de build (o singura data)

```bash
docker build -t carpatos-toolchain toolchain/
```

### 2. Intra in container

```bash
docker run --rm -it -v "$(pwd):/src" -w /src carpatos-toolchain
```

### 3. In container: construieste tot

```bash
make                        # kernel + initramfs + ISO (x86_64 implicit)
make ARCH=aarch64           # idem pentru aarch64
make ARCH=aarch64 packages  # construieste pachetele demo
```

Prima compilare a kernelului dureaza ~5-15 minute (depinde de CPU).
Urmatoarele sunt mult mai rapide (incrementale). Cele doua arhitecturi
au build-uri separate (`build/x86_64/`, `build/aarch64/`) care nu
se afecteaza reciproc.

### 4. Ruleaza in QEMU

```bash
make run                    # boot direct kernel+initramfs (rapid), x86_64
make ARCH=aarch64 run       # acelasi, aarch64
make run-iso                # testare completa prin Limine (BIOS pe x86_64)
make ARCH=aarch64 run-iso   # aarch64 (UEFI via AAVMF)
make run-uefi               # x86_64 explicit UEFI (OVMF)
```

Pentru a iesi din QEMU: `Ctrl+A` apoi `X`.

### 5. Parallels Desktop (Apple Silicon)

Pentru a rula ISO-ul aarch64 in Parallels pe Mac, vezi
[docs/PARALLELS.md](docs/PARALLELS.md).

## Ce ar trebui sa vezi la primul boot

```
   ____                         _    ___  ____
  / ___|__ _ _ __ _ __   __ _  | |_ / _ \/ ___|
 | |   / _` | '__| '_ \ / _` | | __| | | \___ \
 | |__| (_| | |  | |_) | (_| | | |_| |_| |___) |
  \____\__,_|_|  | .__/ \__,_|  \__|\___/|____/
                 |_|

  CarpatOS 0.1.0-mvp — versiune bootabila minima

[init] sistemul de fisiere virtuale montat
[init] faza 1: boot MVP terminat cu succes
[init] pornesc shell-ul msh...

msh — shell minim CarpatOS
Tasteaza 'help' pentru lista de comenzi.

carpatos# cpm install hello
Instalez hello-1.0 (din /var/cpm/repos/carpatos-core/hello-1.0-any.cpm)
carpatos# hello
Salut din CarpatOS!
carpatos#
```

## Structura proiectului

```
carpatos/
├── Makefile              # orchestrare top-level, ARCH=x86_64|aarch64
├── toolchain/            # Dockerfile + toolchain reproducibil (ambele arh)
├── kernel/               # build Linux kernel custom, multi-arch
├── boot/                 # config Limine
├── initramfs/
│   ├── src/
│   │   ├── init/         # /init (PID 1)
│   │   ├── msh/          # shell minim + mod script
│   │   ├── lup/          # package manager `cpm`
│   │   └── common/       # headere comune (mesaje)
│   └── rootfs/           # schelet filesystem (etc, dev, proc, etc)
├── packages/             # pachete demo (CPMBUILD + build.sh)
│   ├── hello/            # script shell
│   ├── adevarat/         # binar C: exit 0
│   ├── fals/             # binar C: exit 1
│   └── ecou/             # binar C: echo minim
├── scripts/
│   ├── build-iso.sh      # genereaza ISO (BIOS+UEFI pe x86, UEFI pe arm)
│   ├── build-packages.sh # construieste pachetele demo
│   └── run-qemu.sh       # wrapper QEMU multi-arch
└── docs/
    ├── INSTALARE.md
    ├── CONSTRUIRE.md     # multi-arch build + run
    ├── ARHITECTURA.md
    ├── CPMBUILD.md       # formatul .cpm + scrierea pachetelor
    └── PARALLELS.md      # boot in Parallels Desktop (Apple Silicon)
```

## Roadmap

- [x] **Faza 0** — Toolchain reproducibil (Docker + musl-cross + Limine)
- [x] **Faza 1** — Boot MVP: kernel + init + msh minimal
- [x] **Faza A–F** — Package manager `cpm` + pachete demo + multi-arch
- [ ] **Faza 2** — msh complet: pipes, redirecturi, variabile (partial — mod script exista)
- [ ] **Faza 3** — Port de coreutils minimal (bash, grep, ls) ca pachete `cpm`
- [ ] **Faza 4** — Instalator TUI pentru hardware real
- [ ] **Faza 5** — Stack retea, `cpm` cu repo-uri HTTP
- [ ] **Faza 6+** — Framebuffer grafic, compositor, desktop stil macOS

## Licenta

(Se va stabili ulterior — candidat: MIT pentru codul propriu, GPL-2 pentru
contributiile la kernel Linux.)

## Autor

Catalin Popescu — <https://cpopescu.dev>
