# Makefile — Kernel Linux pentru CarpatOS (multi-arch)
#
# Folosire:
#   make ARCH=x86_64    (implicit)
#   make ARCH=aarch64
#
# Descarca sursa kernelului, aplica configul nostru (defconfig + fragmente
# CarpatOS) si compileaza out-of-tree in build/$(ARCH)/kbuild.

ARCH           ?= x86_64
KERNEL_VERSION ?= 6.12.7
KERNEL_MAJOR   := $(shell echo $(KERNEL_VERSION) | cut -d. -f1)
KERNEL_TARBALL := linux-$(KERNEL_VERSION).tar.xz
KERNEL_URL     := https://cdn.kernel.org/pub/linux/kernel/v$(KERNEL_MAJOR).x/$(KERNEL_TARBALL)
KERNEL_DIR     := linux-$(KERNEL_VERSION)

# ---- mapare ARCH -> parametri specifici kernelului ----
ifeq ($(ARCH),x86_64)
  K_ARCH       := x86_64
  CROSS        :=
  K_TARGET     := bzImage
  K_ARTIFACT   := arch/x86/boot/bzImage
  CONFIG_ARCH_FRAGS := \
    --enable  CONFIG_SERIAL_8250 \
    --enable  CONFIG_SERIAL_8250_CONSOLE \
    --enable  CONFIG_FB \
    --enable  CONFIG_FB_VESA \
    --enable  CONFIG_FRAMEBUFFER_CONSOLE
else ifeq ($(ARCH),aarch64)
  K_ARCH       := arm64
  CROSS        := aarch64-linux-musl-
  K_TARGET     := Image.gz
  K_ARTIFACT   := arch/arm64/boot/Image.gz
  CONFIG_ARCH_FRAGS := \
    --enable  CONFIG_SERIAL_AMBA_PL011 \
    --enable  CONFIG_SERIAL_AMBA_PL011_CONSOLE \
    --enable  CONFIG_FB \
    --enable  CONFIG_FB_SIMPLE \
    --enable  CONFIG_FRAMEBUFFER_CONSOLE \
    --enable  CONFIG_PCI \
    --enable  CONFIG_PCI_HOST_GENERIC \
    --enable  CONFIG_ARM_PSCI \
    --enable  CONFIG_ARM_AMBA \
    --enable  CONFIG_OF
else
  $(error ARCH necunoscut: $(ARCH). Foloseste x86_64 sau aarch64)
endif

CONFIG_COMMON_FRAGS := \
    --enable  CONFIG_BLK_DEV_INITRD \
    --enable  CONFIG_RD_GZIP \
    --enable  CONFIG_DEVTMPFS \
    --enable  CONFIG_DEVTMPFS_MOUNT \
    --enable  CONFIG_TMPFS \
    --enable  CONFIG_PRINTK \
    --enable  CONFIG_VIRTIO_BLK \
    --enable  CONFIG_VIRTIO_NET \
    --enable  CONFIG_VIRTIO_CONSOLE \
    --enable  CONFIG_VIRTIO_PCI \
    --enable  CONFIG_VIRTIO_MMIO \
    --enable  CONFIG_EXT4_FS \
    --enable  CONFIG_ISO9660_FS

BUILD          := $(CURDIR)/build/$(ARCH)
KBUILD         := $(BUILD)/kbuild
OUTPUT         := $(BUILD)/vmlinuz
JOBS           ?= $(shell nproc 2>/dev/null || echo 4)

KMAKE := $(MAKE) -C $(KERNEL_DIR) ARCH=$(K_ARCH) CROSS_COMPILE=$(CROSS) O=$(KBUILD)

.PHONY: all fetch configure build clean distclean

all: $(OUTPUT)

# ---- descarcare + extragere sursa kernel ----
$(KERNEL_TARBALL):
	@echo "==> Descarc sursa kernelului Linux $(KERNEL_VERSION)..."
	wget -q --show-progress $(KERNEL_URL) -O $@.tmp
	mv $@.tmp $@

$(KERNEL_DIR)/Makefile: $(KERNEL_TARBALL)
	@echo "==> Extrag sursa kernelului..."
	tar -xf $(KERNEL_TARBALL)
	touch $@

fetch: $(KERNEL_DIR)/Makefile

# ---- configurare per arhitectura ----
$(KBUILD)/.config: fetch
	@echo "==> Configurez kernelul pentru $(ARCH) (defconfig + fragmente CarpatOS)..."
	mkdir -p $(KBUILD)
	$(KMAKE) defconfig
	chmod +x $(KERNEL_DIR)/scripts/config
	$(KERNEL_DIR)/scripts/config --file $(KBUILD)/.config \
	    $(CONFIG_COMMON_FRAGS) $(CONFIG_ARCH_FRAGS)
	$(KMAKE) olddefconfig

configure: $(KBUILD)/.config

# ---- compilare ----
build: configure
	@echo "==> Compilez kernelul pentru $(ARCH) (jobs=$(JOBS))..."
	$(KMAKE) -j$(JOBS) $(K_TARGET)

$(OUTPUT): build
	mkdir -p $(BUILD)
	cp $(KBUILD)/$(K_ARTIFACT) $(OUTPUT)
	@echo ""
	@echo "==> Kernel construit pentru $(ARCH): $(OUTPUT)"
	@ls -lh $(OUTPUT)

clean:
	-rm -rf $(BUILD)

distclean:
	rm -rf build $(KERNEL_DIR) $(KERNEL_TARBALL)
