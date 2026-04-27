# Dockerfile — Toolchain CarpatOS (multi-arch: x86_64 + aarch64)
#
# Contine:
#   - cross-compiler x86_64-linux-musl + aarch64-linux-musl (de la musl.cc)
#   - tool-urile Limine (bootloader BIOS/UEFI x86 + UEFI aarch64)
#   - dependinte pentru build-ul kernelului Linux
#   - QEMU pentru testare (system-x86 + system-aarch64)
#   - firmware UEFI: OVMF (x86) + AAVMF (aarch64)
#   - xorriso pentru generare ISO
#
# Utilizare:
#   docker build -t carpatos-toolchain toolchain/
#   docker run --rm -it -v $(pwd):/src -w /src carpatos-toolchain

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/toolchain/x86_64-linux-musl-cross/bin:/opt/toolchain/aarch64-linux-musl-cross/bin:/opt/limine:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        # Build essentials
        build-essential \
        make \
        git \
        wget \
        ca-certificates \
        xz-utils \
        cpio \
        gzip \
        # Kernel build deps
        flex \
        bison \
        libssl-dev \
        libelf-dev \
        bc \
        kmod \
        # ISO creation
        xorriso \
        mtools \
        squashfs-tools \
        zstd \
        cpio \
        initramfs-tools-core \
        # GPT disk creation (pentru .img raw cu ESP)
        gdisk \
        dosfstools \
        # Testing — QEMU pentru ambele arhitecturi
        qemu-system-x86 \
        qemu-system-arm \
        # Firmware UEFI
        ovmf \
        qemu-efi-aarch64 \
        # Utilitare
        file \
        python3 \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Cross-compilers musl (prebuilt de la musl.cc) — pentru ambele arhitecturi
ARG MUSL_X86_URL="https://musl.cc/x86_64-linux-musl-cross.tgz"
ARG MUSL_ARM_URL="https://musl.cc/aarch64-linux-musl-cross.tgz"
RUN mkdir -p /opt/toolchain && cd /opt/toolchain \
    && wget -q "$MUSL_X86_URL" -O musl-x86.tgz \
    && tar -xzf musl-x86.tgz \
    && rm musl-x86.tgz \
    && wget -q "$MUSL_ARM_URL" -O musl-arm.tgz \
    && tar -xzf musl-arm.tgz \
    && rm musl-arm.tgz \
    && ls /opt/toolchain/

# Limine bootloader (binare prebuilt — include BOOTX64.EFI + BOOTAA64.EFI)
ARG LIMINE_VERSION="v9.3.2-binary"
RUN mkdir -p /opt \
    && git clone --depth 1 --branch "$LIMINE_VERSION" \
       https://github.com/limine-bootloader/limine.git /opt/limine \
    && make -C /opt/limine

# Symlinks de conveniente pentru firmware
RUN ln -sf /usr/share/ovmf/OVMF.fd                /opt/ovmf.fd \
    && ln -sf /usr/share/AAVMF/AAVMF_CODE.fd      /opt/aavmf-code.fd \
    && ln -sf /usr/share/AAVMF/AAVMF_VARS.fd      /opt/aavmf-vars.fd

# Verificari finale
RUN x86_64-linux-musl-gcc --version \
    && aarch64-linux-musl-gcc --version \
    && /opt/limine/limine version \
    && qemu-system-x86_64 --version \
    && qemu-system-aarch64 --version \
    && test -f /opt/ovmf.fd \
    && test -f /opt/aavmf-code.fd \
    && test -f /opt/aavmf-vars.fd \
    && test -f /opt/limine/BOOTX64.EFI \
    && test -f /opt/limine/BOOTAA64.EFI

WORKDIR /src

RUN echo '#!/bin/bash\n\
echo "================================================"\n\
echo " Mediu de build CarpatOS (multi-arch)"\n\
echo "================================================"\n\
echo " Cross-compilers:"\n\
echo "   x86_64-linux-musl-gcc"\n\
echo "   aarch64-linux-musl-gcc"\n\
echo " Limine:    /opt/limine"\n\
echo " Firmware:  /opt/ovmf.fd  /opt/aavmf-code.fd"\n\
echo " QEMU:      qemu-system-x86_64  qemu-system-aarch64"\n\
echo "================================================"\n\
echo " Build implicit (x86_64):  make"\n\
echo " Build aarch64:            make ARCH=aarch64"\n\
echo "================================================"\n\
exec "$@"' > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
