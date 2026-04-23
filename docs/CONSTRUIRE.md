# Construirea CarpatOS

Acest document descrie pasii detaliati pentru a construi CarpatOS
de la sursa pana la ISO bootabil.

## Cerinte hardware

- CPU x86_64 sau aarch64 cu ~2 GB RAM disponibili pentru build
- ~10 GB spatiu pe disk (sursa kernel + obiecte + artefacte × nr arhitecturi)
- Linux sau macOS (cu Docker) — Windows cu WSL2 ar trebui sa mearga

## Arhitecturi suportate

CarpatOS se construieste pentru mai multe arhitecturi dintr-un singur tree:

| Arhitectura | Tinte QEMU | UART | UEFI |
|---|---|---|---|
| `x86_64` | `qemu-system-x86_64` | 8250 (`ttyS0`) | OVMF |
| `aarch64` | `qemu-system-aarch64` | PL011 (`ttyAMA0`) | AAVMF |

Alegi arhitectura prin variabila `ARCH`:

```bash
make ARCH=x86_64    # implicit
make ARCH=aarch64
```

Artefactele sunt separate pe arhitectura:
- `kernel/build/<arch>/vmlinuz`
- `initramfs/build/<arch>/initramfs.cpio.gz`
- `build/<arch>/carpatos-<arch>.iso`

Deci poti tine ambele build-uri in paralel fara conflicte.

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

# 3. Construieste tot (implicit x86_64)
make

# Sau pentru aarch64:
make ARCH=aarch64

# Sau bucati separate:
make kernel                       # ~5-15 min pe primul build
make initramfs                    # secunde
make iso                          # secunde
make ARCH=aarch64 kernel initramfs iso

# Pachete demo
make packages                     # construieste hello, adevarat, fals, ecou
make ARCH=aarch64 packages        # pentru aarch64
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
# Cross-compiler musl — pentru ambele arhitecturi
mkdir -p /opt/toolchain && cd /opt/toolchain
wget https://musl.cc/x86_64-linux-musl-cross.tgz
wget https://musl.cc/aarch64-linux-musl-cross.tgz
tar -xzf x86_64-linux-musl-cross.tgz
tar -xzf aarch64-linux-musl-cross.tgz
export PATH="/opt/toolchain/x86_64-linux-musl-cross/bin:/opt/toolchain/aarch64-linux-musl-cross/bin:$PATH"

# Limine (aceleasi binare contin BOOTX64.EFI + BOOTAA64.EFI)
git clone --depth 1 --branch v9.3.2-binary \
    https://github.com/limine-bootloader/limine.git /opt/limine
make -C /opt/limine

# Apoi in repo-ul CarpatOS:
make               # x86_64
make ARCH=aarch64  # aarch64
```

## Artefacte produse

Dupa un build complet (`<arch>` = `x86_64` sau `aarch64`):

```
kernel/build/<arch>/vmlinuz                 ~15-40 MB
initramfs/build/<arch>/initramfs.cpio.gz    ~50-300 KB
build/<arch>/carpatos-<arch>.iso            ~20-50 MB
packages/build/<arch>/*.cpm                 cateva KB fiecare
```

## Rularea in QEMU

### Boot direct (cel mai rapid pentru iteratie)

```bash
make run                    # x86_64 (implicit)
make ARCH=aarch64 run       # aarch64
```

Echivalent manual (x86_64):
```bash
qemu-system-x86_64 -m 512M -nographic \
    -kernel kernel/build/x86_64/vmlinuz \
    -initrd initramfs/build/x86_64/initramfs.cpio.gz \
    -append "console=ttyS0,115200 rdinit=/init quiet"
```

Echivalent manual (aarch64):
```bash
qemu-system-aarch64 -machine virt -cpu cortex-a72 -m 512M -nographic \
    -kernel kernel/build/aarch64/vmlinuz \
    -initrd initramfs/build/aarch64/initramfs.cpio.gz \
    -append "console=ttyAMA0,115200 rdinit=/init"
```

Iesire: `Ctrl+A` apoi `X`.

### Boot din ISO

```bash
make run-iso                # x86_64 BIOS (Limine isolinux)
make ARCH=aarch64 run-iso   # aarch64 UEFI (AAVMF)
```

Pe aarch64 nu exista BIOS legacy — ISO-ul se boot-eaza obligatoriu prin UEFI.

### Boot din ISO in UEFI explicit

```bash
make run-uefi               # x86_64 cu OVMF
make ARCH=aarch64 run-uefi  # aarch64 cu AAVMF (la fel ca run-iso)
```

Necesita firmware UEFI instalat:
- x86_64: `OVMF.fd` (pachet `ovmf` pe Debian/Ubuntu; `/opt/ovmf.fd` in container)
- aarch64: `AAVMF_CODE.fd` + `AAVMF_VARS.fd` (pachet `qemu-efi-aarch64`;
  `/opt/aavmf-code.fd` + `/opt/aavmf-vars.fd` in container)

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
