/* sha256.c — implementare SHA-256 standalone (RFC 6234 / FIPS 180-4)
 *
 * Fara dependente externe. Folosita in cpm pentru verificarea integritatii
 * pachetelor .cpm la download si pentru calcularea hash-urilor in
 * repo.index.
 */
#define _GNU_SOURCE
#include "cpm.h"

#include <fcntl.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

static const uint32_t K[64] = {
    0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,
    0x3956c25bu,0x59f111f1u,0x923f82a4u,0xab1c5ed5u,
    0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,
    0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u,
    0xe49b69c1u,0xefbe4786u,0x0fc19dc6u,0x240ca1ccu,
    0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau,
    0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,
    0xc6e00bf3u,0xd5a79147u,0x06ca6351u,0x14292967u,
    0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,
    0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u,
    0xa2bfe8a1u,0xa81a664bu,0xc24b8b70u,0xc76c51a3u,
    0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u,
    0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,
    0x391c0cb3u,0x4ed8aa4au,0x5b9cca4fu,0x682e6ff3u,
    0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,
    0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u,
};

typedef struct {
    uint32_t h[8];
    uint64_t total_octeti;
    uint8_t buf[64];
    size_t buf_len;
} Sha256Ctx;

static void rot_proceseaza_bloc(Sha256Ctx *c, const uint8_t bloc[64]) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++) {
        w[i] = ((uint32_t)bloc[i * 4]     << 24)
             | ((uint32_t)bloc[i * 4 + 1] << 16)
             | ((uint32_t)bloc[i * 4 + 2] <<  8)
             | ((uint32_t)bloc[i * 4 + 3]);
    }
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ((w[i-15] >> 7) | (w[i-15] << 25))
                    ^ ((w[i-15] >> 18) | (w[i-15] << 14))
                    ^ (w[i-15] >> 3);
        uint32_t s1 = ((w[i-2] >> 17) | (w[i-2] << 15))
                    ^ ((w[i-2] >> 19) | (w[i-2] << 13))
                    ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }

    uint32_t a = c->h[0], b = c->h[1], cc = c->h[2], d = c->h[3];
    uint32_t e = c->h[4], f = c->h[5], g = c->h[6], hh = c->h[7];

    for (int i = 0; i < 64; i++) {
        uint32_t S1 = ((e >> 6) | (e << 26))
                    ^ ((e >> 11) | (e << 21))
                    ^ ((e >> 25) | (e << 7));
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = hh + S1 + ch + K[i] + w[i];
        uint32_t S0 = ((a >> 2) | (a << 30))
                    ^ ((a >> 13) | (a << 19))
                    ^ ((a >> 22) | (a << 10));
        uint32_t mj = (a & b) ^ (a & cc) ^ (b & cc);
        uint32_t t2 = S0 + mj;
        hh = g; g = f; f = e; e = d + t1;
        d = cc; cc = b; b = a; a = t1 + t2;
    }
    c->h[0] += a; c->h[1] += b; c->h[2] += cc; c->h[3] += d;
    c->h[4] += e; c->h[5] += f; c->h[6] += g; c->h[7] += hh;
}

static void sha256_init(Sha256Ctx *c) {
    c->h[0] = 0x6a09e667u; c->h[1] = 0xbb67ae85u;
    c->h[2] = 0x3c6ef372u; c->h[3] = 0xa54ff53au;
    c->h[4] = 0x510e527fu; c->h[5] = 0x9b05688cu;
    c->h[6] = 0x1f83d9abu; c->h[7] = 0x5be0cd19u;
    c->total_octeti = 0;
    c->buf_len = 0;
}

static void sha256_update(Sha256Ctx *c, const void *data, size_t len) {
    const uint8_t *p = (const uint8_t *)data;
    c->total_octeti += len;
    while (len > 0) {
        size_t loc = 64 - c->buf_len;
        if (loc > len) loc = len;
        memcpy(c->buf + c->buf_len, p, loc);
        c->buf_len += loc;
        p += loc;
        len -= loc;
        if (c->buf_len == 64) {
            rot_proceseaza_bloc(c, c->buf);
            c->buf_len = 0;
        }
    }
}

static void sha256_final(Sha256Ctx *c, uint8_t out[32]) {
    uint64_t biti = c->total_octeti * 8;
    uint8_t pad = 0x80;
    sha256_update(c, &pad, 1);
    static const uint8_t zero[64] = {0};
    while (c->buf_len != 56) {
        size_t need = (c->buf_len < 56) ? (56 - c->buf_len) : (64 - c->buf_len + 56);
        if (need > 64) need = 64;
        sha256_update(c, zero, need);
    }
    uint8_t lung[8];
    for (int i = 0; i < 8; i++) lung[i] = (uint8_t)(biti >> (56 - i * 8));
    sha256_update(c, lung, 8);
    for (int i = 0; i < 8; i++) {
        out[i * 4]     = (uint8_t)(c->h[i] >> 24);
        out[i * 4 + 1] = (uint8_t)(c->h[i] >> 16);
        out[i * 4 + 2] = (uint8_t)(c->h[i] >>  8);
        out[i * 4 + 3] = (uint8_t)(c->h[i]);
    }
}

static void hex_din_octeti(const uint8_t in[32], char out[65]) {
    static const char cifre[] = "0123456789abcdef";
    for (int i = 0; i < 32; i++) {
        out[i * 2]     = cifre[(in[i] >> 4) & 0xf];
        out[i * 2 + 1] = cifre[in[i] & 0xf];
    }
    out[64] = '\0';
}

void sha256_buf(const void *data, size_t len, char out_hex[65]) {
    Sha256Ctx c;
    sha256_init(&c);
    sha256_update(&c, data, len);
    uint8_t raw[32];
    sha256_final(&c, raw);
    hex_din_octeti(raw, out_hex);
}

int sha256_file(const char *cale, char out_hex[65]) {
    int fd = open(cale, O_RDONLY);
    if (fd < 0) return -1;
    Sha256Ctx c;
    sha256_init(&c);
    uint8_t buf[8192];
    for (;;) {
        ssize_t n = read(fd, buf, sizeof(buf));
        if (n < 0) { close(fd); return -1; }
        if (n == 0) break;
        sha256_update(&c, buf, (size_t)n);
    }
    close(fd);
    uint8_t raw[32];
    sha256_final(&c, raw);
    hex_din_octeti(raw, out_hex);
    return 0;
}
