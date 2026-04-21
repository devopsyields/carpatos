# Makefile — CarpatOS (top-level)
#
# Tinte:
#   make              — construieste tot (kernel + initramfs + ISO)
#   make kernel       — doar kernelul
#   make initramfs    — doar initramfs
#   make iso          — construieste ISO-ul
#   make run          — ruleaza in QEMU (boot direct, fara ISO)
#   make run-iso      — ruleaza ISO-ul in QEMU (BIOS)
#   make run-uefi     — ruleaza ISO-ul in QEMU (UEFI)
#   make clean        — sterge artefacte de build
#   make distclean    — sterge tot, inclusiv sursa kernelului
#
# Toolchain recomandat: ruleaza din containerul toolchain/
#   docker build -t carpatos-toolchain toolchain/
#   docker run --rm -it -v $(pwd):/src -w /src carpatos-toolchain
#   (in container:) make

.PHONY: all kernel initramfs iso run run-iso run-uefi clean distclean help

all: kernel initramfs iso

kernel:
	$(MAKE) -C kernel

initramfs:
	$(MAKE) -C initramfs

iso: kernel initramfs
	./scripts/build-iso.sh

run: kernel initramfs
	./scripts/run-qemu.sh direct

run-iso: iso
	./scripts/run-qemu.sh iso

run-uefi: iso
	./scripts/run-qemu.sh uefi

clean:
	$(MAKE) -C kernel clean
	$(MAKE) -C initramfs clean
	rm -rf build

distclean:
	$(MAKE) -C kernel distclean
	$(MAKE) -C initramfs clean
	rm -rf build

help:
	@echo "CarpatOS — tinte disponibile:"
	@echo "  make              — construieste tot"
	@echo "  make kernel       — doar kernelul Linux"
	@echo "  make initramfs    — doar initramfs"
	@echo "  make iso          — genereaza ISO-ul bootabil"
	@echo "  make run          — ruleaza direct in QEMU (rapid)"
	@echo "  make run-iso      — ruleaza ISO in QEMU (BIOS)"
	@echo "  make run-uefi     — ruleaza ISO in QEMU (UEFI)"
	@echo "  make clean        — sterge artefactele de build"
	@echo "  make distclean    — sterge tot"
