# Dockerfile — Toolchain CarpatOS
#
# Contine tot ce-ti trebuie pentru a construi CarpatOS:
#   - cross-compiler x86_64-linux-musl (de la musl.cc)
#   - tool-urile Limine (bootloader + limine CLI)
#   - dependinte pentru build-ul kernelului Linux
#   - QEMU pentru testare
#   - xorriso pentru ISO
#
# Utilizare:
#   docker build -t carpatos-toolchain toolchain/
#   docker run --rm -it -v $(pwd):/src -w /src carpatos-toolchain

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/toolchain/x86_64-linux-musl-cross/bin:/opt/limine:${PATH}"

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
        # Testing
        qemu-system-x86 \
        ovmf \
        # Utilitare
        file \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Cross-compiler musl (prebuilt de la musl.cc)
ARG MUSL_CROSS_URL="https://musl.cc/x86_64-linux-musl-cross.tgz"
RUN mkdir -p /opt/toolchain && cd /opt/toolchain \
    && wget -q "$MUSL_CROSS_URL" -O musl-cross.tgz \
    && tar -xzf musl-cross.tgz \
    && rm musl-cross.tgz \
    && ls /opt/toolchain/x86_64-linux-musl-cross/bin/

# Limine bootloader (binare prebuilt)
ARG LIMINE_VERSION="v9.3.2-binary"
RUN mkdir -p /opt \
    && git clone --depth 1 --branch "$LIMINE_VERSION" \
       https://github.com/limine-bootloader/limine.git /opt/limine \
    && make -C /opt/limine

# Verificari
RUN x86_64-linux-musl-gcc --version \
    && /opt/limine/limine version \
    && qemu-system-x86_64 --version

WORKDIR /src

# Mesaj la intrarea in container
RUN echo '#!/bin/bash\n\
echo "================================================"\n\
echo " Mediu de build CarpatOS"\n\
echo "================================================"\n\
echo " Cross-compiler: x86_64-linux-musl-gcc"\n\
echo " Limine:         /opt/limine"\n\
echo " QEMU:           qemu-system-x86_64"\n\
echo "================================================"\n\
exec "$@"' > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
