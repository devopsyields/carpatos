# CarpatOS

> Distributie Linux minimalistă stil Alpine, cu package manager propriu (`lup`)
> si userland scris de la zero in C. Toata interactiunea cu utilizatorul este
> in limba romana.

## Stadiu

**Faza 1 — MVP bootabil.** Sistem care porneste in QEMU (BIOS sau UEFI),
monteaza pseudo-filesystem-urile, si prezinta un shell minim (`msh`).
Nu include inca bash, grep, ls etc — acestea vor fi adaugate ca pachete
prin `lup` in fazele urmatoare.

## Componente

| Componenta | Ce este | Unde |
|---|---|---|
| Kernel | Linux vanilla (6.12 LTS), config minimal | `kernel/` |
| Bootloader | Limine (BIOS+UEFI) | `boot/` |
| init (PID 1) | Propriu, C + musl static | `initramfs/src/init/` |
| msh | Shell minim propriu | `initramfs/src/msh/` |
| lup | Package manager (Faza 3) | — |
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
make            # kernel + initramfs + ISO
```

Prima compilare a kernelului dureaza ~5-15 minute (depinde de CPU).
Urmatoarele sunt mult mai rapide (incrementale).

### 4. Ruleaza in QEMU

```bash
make run        # boot direct kernel+initramfs (rapid)
make run-iso    # testare completa prin Limine (BIOS)
make run-uefi   # testare completa prin Limine (UEFI, necesita OVMF)
```

Pentru a iesi din QEMU: `Ctrl+A` apoi `X`.

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

carpatos# help
Builtins disponibile:
  exit       — iesire din shell
  help       — acest mesaj
  cd [dir]   — schimba directorul curent
  pwd        — afiseaza directorul curent
  echo ...   — afiseaza argumentele
  versiune   — versiunea CarpatOS
...
carpatos#
```

## Structura proiectului

```
carpatos/
├── Makefile              # orchestrare top-level
├── toolchain/            # Dockerfile + toolchain reproducibil
├── kernel/               # build Linux kernel custom
├── boot/                 # config Limine
├── initramfs/
│   ├── src/
│   │   ├── init/         # /init (PID 1)
│   │   ├── msh/          # shell minim
│   │   └── common/       # headere comune (mesaje)
│   └── rootfs/           # schelet filesystem (etc, dev, proc, etc)
├── scripts/
│   ├── build-iso.sh      # generare ISO hibrid BIOS+UEFI
│   └── run-qemu.sh       # wrapper QEMU
└── docs/
    ├── INSTALARE.md
    ├── CONSTRUIRE.md
    └── ARHITECTURA.md
```

## Roadmap

- [x] **Faza 0** — Toolchain reproducibil (Docker + musl-cross + Limine)
- [x] **Faza 1** — Boot MVP: kernel + init + msh minimal
- [ ] **Faza 2** — msh complet: pipes, redirecturi, scripturi
- [ ] **Faza 3** — Package manager `lup` + primele pachete (bash, coreutils, grep)
- [ ] **Faza 4** — Instalator TUI pentru hardware real
- [ ] **Faza 5** — Stack retea, `lup` cu repo-uri HTTP
- [ ] **Faza 6+** — Framebuffer grafic, compositor, desktop stil macOS

## Licenta

(Se va stabili ulterior — candidat: MIT pentru codul propriu, GPL-2 pentru
contributiile la kernel Linux.)

## Autor

Catalin Popescu — <https://cpopescu.dev>
