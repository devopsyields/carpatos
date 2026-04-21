# Makefile — msh CarpatOS

CC       ?= x86_64-linux-musl-gcc
CFLAGS   := -std=c11 -Wall -Wextra -Werror -O2 \
            -fno-stack-protector -fno-pie \
            -I../common
LDFLAGS  := -static -no-pie -s

TARGET   := msh
SOURCES  := msh.c
OBJECTS  := $(SOURCES:.c=.o)

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^
	strip $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)/bin/msh

clean:
	rm -f $(TARGET) $(OBJECTS)
