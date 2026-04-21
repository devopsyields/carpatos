# Makefile — initramfs CarpatOS
#
# Construieste init + msh, le instaleaza intr-un rootfs staging,
# apoi impacheteaza ca archive cpio (newc format) gzipped.

ROOTFS_STAGE := $(CURDIR)/build/rootfs
OUTPUT       := $(CURDIR)/build/initramfs.cpio.gz

SKELETON     := $(CURDIR)/rootfs

.PHONY: all clean init msh stage archive

all: $(OUTPUT)

init:
	$(MAKE) -C src/init

msh:
	$(MAKE) -C src/msh

# Staging: copiez scheletul + instalez binarele compilate
stage: init msh
	rm -rf $(ROOTFS_STAGE)
	mkdir -p $(ROOTFS_STAGE)
	cp -a $(SKELETON)/. $(ROOTFS_STAGE)/
	$(MAKE) -C src/init install DESTDIR=$(ROOTFS_STAGE)
	$(MAKE) -C src/msh install DESTDIR=$(ROOTFS_STAGE)
	# /bin/sh -> msh (pentru compatibilitate cu scripturi)
	ln -sf msh $(ROOTFS_STAGE)/bin/sh
	# permisiunile corecte pe directoarele de sistem
	chmod 1777 $(ROOTFS_STAGE)/tmp
	chmod 1777 $(ROOTFS_STAGE)/run

# Archive: construieste cpio (newc) + gzip
$(OUTPUT): stage
	mkdir -p $(dir $(OUTPUT))
	cd $(ROOTFS_STAGE) && \
	  find . -print0 | cpio --null --create --format=newc --quiet \
	  | gzip -9 > $(OUTPUT)
	@echo ""
	@echo "==> initramfs construit: $(OUTPUT)"
	@ls -lh $(OUTPUT)

clean:
	rm -rf build
	$(MAKE) -C src/init clean
	$(MAKE) -C src/msh clean
