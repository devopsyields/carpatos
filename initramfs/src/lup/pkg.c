/* pkg.c — incarcare / salvare fisier .lup (antet + manifest + payload) */
#define _GNU_SOURCE
#include "lup.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void pune_u32(unsigned char *p, uint32_t v) {
    p[0] = (unsigned char)(v & 0xff);
    p[1] = (unsigned char)((v >> 8) & 0xff);
    p[2] = (unsigned char)((v >> 16) & 0xff);
    p[3] = (unsigned char)((v >> 24) & 0xff);
}

static uint32_t ia_u32(const unsigned char *p) {
    return (uint32_t)p[0]
         | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16)
         | ((uint32_t)p[3] << 24);
}

int lup_incarca(const char *cale, Manifest *m,
                void **payload_out, size_t *payload_len_out) {
    size_t total;
    char *buf = citeste_fisier(cale, &total);
    if (!buf) { lup_err("nu pot citi %s", cale); return -1; }
    if (total < 16) {
        free(buf); lup_err("%s: fisier prea mic pentru .lup", cale); return -1;
    }

    const unsigned char *u = (const unsigned char *)buf;
    uint32_t magic = ia_u32(u);
    uint32_t ver   = ia_u32(u + 4);
    uint32_t mlen  = ia_u32(u + 8);
    uint32_t plen  = ia_u32(u + 12);

    if (magic != LUP_MAGIC) {
        free(buf);
        lup_err("%s: magic invalid (0x%08x)", cale, magic);
        return -1;
    }
    if (ver != LUP_FORMAT_VER) {
        free(buf);
        lup_err("%s: versiune format %u necunoscuta", cale, ver);
        return -1;
    }
    if ((size_t)16 + mlen + plen > total) {
        free(buf);
        lup_err("%s: dimensiuni incorecte in antet", cale);
        return -1;
    }

    if (manifest_parseaza(buf + 16, mlen, m) < 0) {
        free(buf);
        lup_err("%s: manifest invalid", cale);
        return -1;
    }

    void *payload = NULL;
    if (plen > 0) {
        payload = malloc(plen);
        if (!payload) { free(buf); return -1; }
        memcpy(payload, buf + 16 + mlen, plen);
    }
    free(buf);

    *payload_out = payload;
    *payload_len_out = plen;
    return 0;
}

int lup_salveaza(const char *cale, const Manifest *m,
                 const void *payload, size_t payload_len) {
    char mbuf[2048];
    int mlen = manifest_serializeaza(m, mbuf, sizeof(mbuf));
    if (mlen < 0) { lup_err("manifest prea mare pentru serializare"); return -1; }

    FILE *f = fopen(cale, "wb");
    if (!f) { lup_err("nu pot scrie %s", cale); return -1; }

    unsigned char header[16];
    pune_u32(header,      LUP_MAGIC);
    pune_u32(header + 4,  LUP_FORMAT_VER);
    pune_u32(header + 8,  (uint32_t)mlen);
    pune_u32(header + 12, (uint32_t)payload_len);

    if (fwrite(header, 1, 16, f) != 16) { fclose(f); return -1; }
    if (fwrite(mbuf, 1, (size_t)mlen, f) != (size_t)mlen) { fclose(f); return -1; }
    if (payload_len > 0 &&
        fwrite(payload, 1, payload_len, f) != payload_len) {
        fclose(f); return -1;
    }
    return fclose(f) == 0 ? 0 : -1;
}
