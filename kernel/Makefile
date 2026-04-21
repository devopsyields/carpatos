# Makefile — Kernel Linux pentru CarpatOS
#
# Descarca sursa kernelului, aplica configul nostru custom
# (bazat pe tinyconfig + fragmente) si compileaza.

KERNEL_VERSION ?= 6.12.7
KERNEL_MAJOR   := $(shell echo $(KERNEL_VERSION) | cut -d. -f1)
KERNEL_TARBALL := linux-$(KERNEL_VERSION).tar.xz
KERNEL_URL     := https://cdn.kernel.org/pub/linux/kernel/v$(KERNEL_MAJOR).x/$(KERNEL_TARBALL)
KERNEL_DIR     := linux-$(KERNEL_VERSION)

BUILD          := $(CURDIR)/build
OUTPUT         := $(BUILD)/vmlinuz
JOBS           ?= $(shell nproc)

.PHONY: all fetch configure build clean distclean

all: $(OUTPUT)

# Descarca sursa kernelului daca nu exista
$(KERNEL_TARBALL):
	@echo "==> Descarc sursa kernelului Linux $(KERNEL_VERSION)..."
	wget -q --show-progress $(KERNEL_URL) -O $@.tmp
	mv $@.tmp $@

# Extrage sursa
$(KERNEL_DIR)/Makefile: $(KERNEL_TARBALL)
	@echo "==> Extrag sursa kernelului..."
	tar -xf $(KERNEL_TARBALL)
	touch $@

fetch: $(KERNEL_DIR)/Makefile

# Aplica configuratia noastra: defconfig + fragmente custom
configure: fetch
	@echo "==> Configurez kernelul (defconfig + fragmente CarpatOS)..."
	$(MAKE) -C $(KERNEL_DIR) defconfig
	./scripts/config --file $(KERNEL_DIR)/.config \
	  --enable  CONFIG_BLK_DEV_INITRD \
	  --enable  CONFIG_RD_GZIP \
	  --enable  CONFIG_DEVTMPFS \
	  --enable  CONFIG_DEVTMPFS_MOUNT \
	  --enable  CONFIG_TMPFS \
	  --enable  CONFIG_SERIAL_8250 \
	  --enable  CONFIG_SERIAL_8250_CONSOLE \
	  --enable  CONFIG_PRINTK \
	  --enable  CONFIG_FB \
	  --enable  CONFIG_FB_VESA \
	  --enable  CONFIG_FRAMEBUFFER_CONSOLE \
	  --enable  CONFIG_VIRTIO_BLK \
	  --enable  CONFIG_VIRTIO_NET \
	  --enable  CONFIG_VIRTIO_CONSOLE \
	  --enable  CONFIG_EXT4_FS \
	  --enable  CONFIG_ISO9660_FS
	$(MAKE) -C $(KERNEL_DIR) olddefconfig

# Scriptul scripts/config vine cu sursa kernelului, fac un shim local
./scripts/config: fetch
	mkdir -p ./scripts
	cp $(KERNEL_DIR)/scripts/config ./scripts/config
	chmod +x ./scripts/config

build: configure
	@echo "==> Compilez kernelul (jobs=$(JOBS))..."
	$(MAKE) -C $(KERNEL_DIR) -j$(JOBS) bzImage

$(OUTPUT): build
	mkdir -p $(BUILD)
	cp $(KERNEL_DIR)/arch/x86/boot/bzImage $(OUTPUT)
	@echo ""
	@echo "==> Kernel construit: $(OUTPUT)"
	@ls -lh $(OUTPUT)

clean:
	-$(MAKE) -C $(KERNEL_DIR) clean
	rm -rf $(BUILD)

distclean:
	rm -rf $(KERNEL_DIR) $(KERNEL_TARBALL) $(BUILD) ./scripts
