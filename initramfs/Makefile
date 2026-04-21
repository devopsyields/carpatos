# Makefile — initramfs CarpatOS (multi-arch)
#
# Construieste init + msh + lup, le instaleaza intr-un rootfs staging,
# apoi impacheteaza ca arhiva cpio (newc) gzipped.
#
# Folosire:
#   make ARCH=x86_64    (implicit)
#   make ARCH=aarch64

ARCH         ?= x86_64
ROOTFS_STAGE := $(CURDIR)/build/$(ARCH)/rootfs
OUTPUT       := $(CURDIR)/build/$(ARCH)/initramfs.cpio.gz

SKELETON     := $(CURDIR)/rootfs
PACKAGES_DIR := $(CURDIR)/../packages

.PHONY: all clean init msh lup stage archive

all: $(OUTPUT)

init:
	$(MAKE) -C src/init ARCH=$(ARCH)

msh:
	$(MAKE) -C src/msh ARCH=$(ARCH)

lup:
	$(MAKE) -C src/lup ARCH=$(ARCH)

# ---- staging: copiez scheletul + binarele compilate ----
stage: init msh lup
	rm -rf $(ROOTFS_STAGE)
	mkdir -p $(ROOTFS_STAGE)
	cp -a $(SKELETON)/. $(ROOTFS_STAGE)/
	$(MAKE) -C src/init install ARCH=$(ARCH) DESTDIR=$(ROOTFS_STAGE)
	$(MAKE) -C src/msh  install ARCH=$(ARCH) DESTDIR=$(ROOTFS_STAGE)
	$(MAKE) -C src/lup  install ARCH=$(ARCH) DESTDIR=$(ROOTFS_STAGE)
	# /bin/sh -> msh (pentru compat scripturi)
	ln -sf msh $(ROOTFS_STAGE)/bin/sh
	# permisiuni pe dir-urile de sistem
	chmod 1777 $(ROOTFS_STAGE)/tmp
	chmod 1777 $(ROOTFS_STAGE)/run
	# pachete demo daca exista pentru aceasta arhitectura
	mkdir -p $(ROOTFS_STAGE)/var/lup/repos/carpatos-core
	mkdir -p $(ROOTFS_STAGE)/var/lup/db
	mkdir -p $(ROOTFS_STAGE)/var/lup/cache
	@if [ -d "$(PACKAGES_DIR)/build/$(ARCH)" ]; then \
	    echo "==> Copiez pachete demo $(ARCH) in rootfs"; \
	    cp $(PACKAGES_DIR)/build/$(ARCH)/*.lup \
	       $(ROOTFS_STAGE)/var/lup/repos/carpatos-core/ 2>/dev/null || true; \
	fi

# ---- archive: cpio (newc) + gzip ----
$(OUTPUT): stage
	mkdir -p $(dir $(OUTPUT))
	cd $(ROOTFS_STAGE) && \
	  find . -print0 | cpio --null --create --format=newc --quiet \
	  | gzip -9 > $(OUTPUT)
	@echo ""
	@echo "==> initramfs construit pentru $(ARCH): $(OUTPUT)"
	@ls -lh $(OUTPUT)

clean:
	rm -rf build
	$(MAKE) -C src/init clean
	$(MAKE) -C src/msh  clean
	$(MAKE) -C src/lup  clean
