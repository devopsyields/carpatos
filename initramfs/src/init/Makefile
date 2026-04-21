# Makefile — init CarpatOS
# Compileaza /init static cu musl (fara dependente runtime)

ARCH     ?= x86_64
CC       ?= $(ARCH)-linux-musl-gcc
CFLAGS   := -std=c11 -Wall -Wextra -Werror -O2 \
            -fno-stack-protector -fno-pie \
            -I../common
LDFLAGS  := -static -no-pie -s

TARGET   := init
SOURCES  := init.c
OBJECTS  := $(SOURCES:.c=.o)

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^
	strip $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)/init

clean:
	rm -f $(TARGET) $(OBJECTS)
