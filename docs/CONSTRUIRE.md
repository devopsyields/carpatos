# Construirea CarpatOS

Acest document descrie pasii detaliati pentru a construi CarpatOS
de la sursa pana la ISO bootabil.

## Cerinte hardware

- CPU x86_64 cu ~2 GB RAM disponibili pentru build
- ~10 GB spatiu pe disk (sursa kernel + obiecte + artefacte)
- Linux sau macOS (cu Docker) — Windows cu WSL2 ar trebui sa mearga

## Pasii de build

### Metoda recomandata: container Docker

Toolchainul este capsulat intr-un container pentru reproductibilitate.

```bash
# 1. Construieste imaginea toolchain (doar prima data, ~5 min)
docker build -t carpatos-toolchain toolchain/

# 2. Intra in container cu sursa montata
docker run --rm -it \
    -v "$(pwd):/src" \
    -w /src \
    carpatos-toolchain

# De aici, toate comenzile ruleaza in container:

# 3. Construieste tot
make

# Sau, pentru a construi bucati separat:
make kernel        # ~5-15 min pe primul build
make initramfs     # secunde
make iso           # secunde
```

### Metoda alternativa: direct pe host

Daca nu vrei Docker, trebuie sa instalezi manual:

**Debian/Ubuntu:**
```bash
sudo apt-get install -y \
    build-essential flex bison libssl-dev libelf-dev bc \
    xz-utils cpio gzip xorriso qemu-system-x86 ovmf mtools \
    wget git ca-certificates
```

**Arch Linux:**
```bash
sudo pacman -S base-devel flex bison openssl libelf bc \
    xz cpio gzip libisoburn qemu-full ovmf mtools wget git
```

Apoi:

```bash
# Cross-compiler musl
mkdir -p /opt/toolchain && cd /opt/toolchain
wget https://musl.cc/x86_64-linux-musl-cross.tgz
tar -xzf x86_64-linux-musl-cross.tgz
export PATH="/opt/toolchain/x86_64-linux-musl-cross/bin:$PATH"

# Limine
git clone --depth 1 --branch v9.3.2-binary \
    https://github.com/limine-bootloader/limine.git /opt/limine
make -C /opt/limine

# Apoi in repo-ul CarpatOS:
make
```

## Artefacte produse

Dupa un build complet:

```
kernel/build/vmlinuz                   ~15-40 MB, kernelul Linux compilat
initramfs/build/initramfs.cpio.gz      ~50-200 KB, initramfs complet
build/carpatos.iso                     ~20-50 MB, ISO bootabil
```

## Rularea in QEMU

### Boot direct (cel mai rapid pentru iteratie)

```bash
make run
```

Echivalent cu:
```bash
qemu-system-x86_64 -m 512M -nographic \
    -kernel kernel/build/vmlinuz \
    -initrd initramfs/build/initramfs.cpio.gz \
    -append "console=ttyS0,115200 rdinit=/init quiet"
```

Iesire: `Ctrl+A` apoi `X`.

### Boot din ISO (BIOS)

```bash
make run-iso
```

### Boot din ISO (UEFI)

```bash
make run-uefi
```

Necesita `OVMF.fd` instalat (pachet `ovmf` pe Debian/Ubuntu).

## Depanare

### "error: statements like this ..." la compilarea initului

Verifica ca folosesti cross-compilerul musl, nu gcc-ul de sistem.
In container, `CC` ar trebui sa fie `x86_64-linux-musl-gcc`.

### Kernelul boot-eaza dar nu ajunge la init

Controleaza argumentul `rdinit=/init` in cmdline-ul kernelului.
Verifica ca `/init` exista in initramfs si e executabil:

```bash
cd initramfs/build && zcat initramfs.cpio.gz | cpio -t | grep init
```

### QEMU se blocheaza fara output

Foloseste `-append "console=ttyS0,115200 debug earlyprintk=serial"`
pentru a vedea mesajele kernelului pe serial.

### Limine raporteaza "kernel protocol not recognized"

Verifica versiunea Limine din Dockerfile. Protocolul Linux a fost
introdus in Limine v5.x; pentru versiuni mai vechi foloseste `multiboot2`.

## Build time estimat

| Faza | Primul build | Rebuild incremental |
|---|---|---|
| Docker image | 5-10 min | — |
| Kernel | 5-15 min | 10-60 s (dupa touch) |
| initramfs | <5 s | <2 s |
| ISO | <5 s | <5 s |

Rebuild-ul kernelului dupa modificari de config e mai lent — `make olddefconfig` reconfigureaza + recompileaza.
