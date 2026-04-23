## Makefile — cpm CarpatOS
##
## Suporta cross-build pentru x86_64 si aarch64 cu musl-cross.
##   make ARCH=x86_64
##   make ARCH=aarch64
##
## Pentru sanity check pe host (nu produce binar de boot):
##   make CC=gcc LDFLAGS= STRIP=true CFLAGS_EXTRA="-fPIE"

ARCH     ?= x86_64
CC       ?= $(ARCH)-linux-musl-gcc
STRIP    ?= strip

CFLAGS   := -std=c11 -Wall -Wextra -Werror -O2 \
            -fno-stack-protector -fno-pie \
            -I../common $(CFLAGS_EXTRA)
LDFLAGS  ?= -static -no-pie -s

TARGET   := cpm
SOURCES  := util.c manifest.c tar.c pkg.c db.c repo.c \
            cmd_install.c cmd_remove.c cmd_query.c cmd_build.c main.c
OBJECTS  := $(SOURCES:.c=.o)

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^
	-$(STRIP) $@

%.o: %.c cpm.h
	$(CC) $(CFLAGS) -c $< -o $@

install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)/bin/cpm

clean:
	rm -f $(TARGET) cpm_host $(OBJECTS)
