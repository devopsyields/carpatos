# Makefile — CarpatOS (top-level, multi-arch)
#
# Tinte:
#   make [ARCH=x86_64|aarch64]  — construieste tot pentru o arhitectura
#   make kernel                  — doar kernelul
#   make initramfs               — doar initramfs
#   make iso                     — construieste ISO-ul
#   make run                     — boot direct in QEMU (fara ISO, rapid)
#   make run-iso                 — ruleaza ISO in QEMU (BIOS pe x86, UEFI pe arm)
#   make run-uefi                — ruleaza ISO in QEMU (UEFI explicit)
#   make packages                — construieste pachetele demo
#   make clean                   — sterge artefacte de build
#   make distclean               — sterge tot, inclusiv sursa kernelului
#
# Implicit ARCH=x86_64. Pentru aarch64 ruleaza:
#   make ARCH=aarch64
#
# Toolchain recomandat: containerul toolchain/
#   docker build -t carpatos-toolchain toolchain/
#   docker run --rm -it -v $(pwd):/src -w /src carpatos-toolchain

ARCH ?= x86_64
export ARCH

.PHONY: all kernel initramfs iso run run-iso run-uefi packages clean distclean help

all: kernel initramfs iso

kernel:
	$(MAKE) -C kernel ARCH=$(ARCH)

initramfs:
	$(MAKE) -C initramfs ARCH=$(ARCH)

iso: kernel initramfs
	./scripts/build-iso.sh $(ARCH)

run: kernel initramfs
	./scripts/run-qemu.sh $(ARCH) direct

run-iso: iso
	./scripts/run-qemu.sh $(ARCH) iso

run-uefi: iso
	./scripts/run-qemu.sh $(ARCH) uefi

packages:
	./scripts/build-packages.sh $(ARCH)

clean:
	$(MAKE) -C kernel clean
	$(MAKE) -C initramfs clean
	rm -rf build packages/build

distclean:
	$(MAKE) -C kernel distclean
	$(MAKE) -C initramfs clean
	rm -rf build packages/build

help:
	@echo "CarpatOS — tinte (ARCH=$(ARCH)):"
	@echo "  make [ARCH=x86_64|aarch64]  — construieste tot"
	@echo "  make kernel                  — doar kernelul"
	@echo "  make initramfs               — doar initramfs"
	@echo "  make iso                     — genereaza ISO bootabil"
	@echo "  make run                     — boot direct in QEMU"
	@echo "  make run-iso                 — boot ISO (BIOS pe x86)"
	@echo "  make run-uefi                — boot ISO (UEFI)"
	@echo "  make packages                — construieste pachetele demo"
	@echo "  make clean                   — sterge build"
	@echo "  make distclean               — sterge tot"
