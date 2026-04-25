/* tar.c — USTAR read + write simplu pentru cpm
 *
 * Limitari MVP:
 *   - nume <= 100 octeti (fara GNU LongLink)
 *   - doar fisiere regulate, directoare si symlinks
 *   - fara sparse, fara extinderi pax
 */
#define _GNU_SOURCE
#include "cpm.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define TAR_BLOC 512

typedef struct {
    char name[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char chksum[8];
    char typeflag;
    char linkname[100];
    char magic[6];
    char version[2];
    char uname[32];
    char gname[32];
    char devmajor[8];
    char devminor[8];
    char prefix[155];
    char pad[12];
} Ustar;

/* ===== helpers pentru octal ===== */

static unsigned long oct_citeste(const char *s, size_t n) {
    unsigned long v = 0;
    for (size_t i = 0; i < n && s[i]; i++) {
        if (s[i] < '0' || s[i] > '7') break;
        v = v * 8 + (unsigned)(s[i] - '0');
    }
    return v;
}

static void oct_scrie(char *dest, size_t n, unsigned long v) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%0*lo", (int)(n - 1), v);
    memcpy(dest, buf, n - 1);
    dest[n - 1] = '\0';
}

static void completeaza_chksum(Ustar *h) {
    memset(h->chksum, ' ', 8);
    unsigned long s = 0;
    const unsigned char *p = (const unsigned char *)h;
    for (size_t i = 0; i < sizeof(*h); i++) s += p[i];
    char tmp[8];
    snprintf(tmp, sizeof(tmp), "%06lo", s & 07777777u);
    memcpy(h->chksum, tmp, 6);
    h->chksum[6] = '\0';
    h->chksum[7] = ' ';
}

/* ===== extract ===== */

int tar_extrage(const void *buf, size_t len, const char *dest_dir,
                void (*jurnal)(const char *cale, void *ctx), void *ctx) {
    const char *p = (const char *)buf;
    size_t off = 0;

    /* normalizam dest_dir: strip trailing '/'.
     * Cazul special "/" -> dd_len = 0, calea finala va fi '/' + nume
     * (fara dubla bara). */
    size_t dd_len = strlen(dest_dir);
    while (dd_len > 1 && dest_dir[dd_len - 1] == '/') dd_len--;
    if (dd_len == 1 && dest_dir[0] == '/') dd_len = 0;

    while (off + TAR_BLOC <= len) {
        const Ustar *h = (const Ustar *)(p + off);

        /* bloc complet de zero = end-of-archive */
        int toate_zero = 1;
        for (size_t i = 0; i < TAR_BLOC; i++) {
            if (((const unsigned char *)h)[i] != 0) { toate_zero = 0; break; }
        }
        if (toate_zero) break;

        off += TAR_BLOC;
        unsigned long sz = oct_citeste(h->size, sizeof(h->size));
        size_t data_off = off;
        size_t data_blocuri = (sz + TAR_BLOC - 1) / TAR_BLOC;
        off += data_blocuri * TAR_BLOC;
        if (off > len) { cpm_err("tar: arhiva trunchiata"); return -1; }

        char nume[300];
        if (h->prefix[0]) {
            snprintf(nume, sizeof(nume), "%.155s/%.100s", h->prefix, h->name);
        } else {
            snprintf(nume, sizeof(nume), "%.100s", h->name);
        }
        if (nume[0] == '\0') continue;

        /* normalizeaza numele intrarii:
         *   - strip "./" si "/" duplicate la inceput (comun in .deb: "./usr/...")
         *   - strip "/" final */
        size_t nl = strlen(nume);
        size_t idx = 0;
        while (idx < nl) {
            if (nume[idx] == '/') { idx++; continue; }
            if (nume[idx] == '.' && idx + 1 < nl && nume[idx + 1] == '/') {
                idx += 2; continue;
            }
            break;
        }
        if (idx > 0) {
            memmove(nume, nume + idx, nl - idx + 1);
            nl -= idx;
        }
        while (nl > 0 && nume[nl - 1] == '/') nume[--nl] = '\0';
        if (nl == 0) continue;

        char cale[MAX_CALE + 64];
        if (dd_len == 0) {
            if ((size_t)snprintf(cale, sizeof(cale), "/%s", nume) >= sizeof(cale)) {
                cpm_err("tar: cale prea lunga: %s", nume);
                return -1;
            }
        } else {
            if ((size_t)snprintf(cale, sizeof(cale), "%.*s/%s",
                                  (int)dd_len, dest_dir, nume) >= sizeof(cale)) {
                cpm_err("tar: cale prea lunga: %s", nume);
                return -1;
            }
        }

        unsigned long mode = oct_citeste(h->mode, sizeof(h->mode));
        if (mode == 0) mode = 0644;

        char typeflag = h->typeflag;
        if (typeflag == '\0') typeflag = '0';

        /* asigura directorul parinte */
        char parinte[MAX_CALE + 64];
        snprintf(parinte, sizeof(parinte), "%s", cale);
        char *slash = strrchr(parinte, '/');
        if (slash && slash != parinte) {
            *slash = '\0';
            asigura_dir(parinte);
        }

        if (typeflag == '5') {
            asigura_dir(cale);
            if (jurnal) jurnal(cale, ctx);
        } else if (typeflag == '2') {
            /* Daca exista un director gol pe calea destinatie (creat de un
             * pachet anterior), il stergem ca sa putem face symlink. Cazul
             * tipic Debian: /usr/share/doc/<x> facut dir de un pachet si
             * symlink de altul. */
            struct stat st;
            if (lstat(cale, &st) == 0) {
                if (S_ISDIR(st.st_mode)) {
                    if (rmdir(cale) < 0) {
                        cpm_err("tar: %s e director nevid, nu pot face symlink",
                                cale);
                        return -1;
                    }
                } else {
                    unlink(cale);
                }
            }
            if (symlink(h->linkname, cale) < 0) {
                cpm_err("tar: symlink %s -> %s: %s",
                        cale, h->linkname, strerror(errno));
                return -1;
            }
            if (jurnal) jurnal(cale, ctx);
        } else if (typeflag == '0' || typeflag == '\0') {
            int fd = open(cale, O_WRONLY | O_CREAT | O_TRUNC,
                          (mode_t)(mode & 07777));
            if (fd < 0) {
                cpm_err("tar: nu pot crea %s: %s", cale, strerror(errno));
                return -1;
            }
            size_t ramane = sz;
            size_t cursor = data_off;
            while (ramane > 0) {
                ssize_t w = write(fd, p + cursor, ramane);
                if (w <= 0) { close(fd); return -1; }
                cursor += (size_t)w;
                ramane -= (size_t)w;
            }
            close(fd);
            chmod(cale, (mode_t)(mode & 07777));
            if (jurnal) jurnal(cale, ctx);
        } else {
            cpm_debug("tar: ignorat tip %c pentru %s", typeflag, nume);
        }
    }
    return 0;
}

/* ===== build ===== */

typedef struct {
    char *buf;
    size_t len;
    size_t cap;
} Buffer;

static int buf_adauga(Buffer *b, const void *data, size_t n) {
    if (b->len + n > b->cap) {
        size_t nou = b->cap ? b->cap * 2 : 4096;
        while (nou < b->len + n) nou *= 2;
        char *p = realloc(b->buf, nou);
        if (!p) return -1;
        b->buf = p;
        b->cap = nou;
    }
    memcpy(b->buf + b->len, data, n);
    b->len += n;
    return 0;
}

static int buf_zero(Buffer *b, size_t n) {
    static const char zero[TAR_BLOC] = {0};
    while (n > 0) {
        size_t chunk = n > TAR_BLOC ? TAR_BLOC : n;
        if (buf_adauga(b, zero, chunk) < 0) return -1;
        n -= chunk;
    }
    return 0;
}

static int adauga_intrare(Buffer *b, const char *nume_arh,
                           const struct stat *st,
                           const char *continut, size_t cont_len,
                           const char *linkname) {
    if (strlen(nume_arh) >= 100) {
        cpm_err("tar: nume prea lung (>=100): %s", nume_arh);
        return -1;
    }
    Ustar h;
    memset(&h, 0, sizeof(h));

    snprintf(h.name, sizeof(h.name), "%s", nume_arh);
    oct_scrie(h.mode, sizeof(h.mode), st->st_mode & 07777);
    oct_scrie(h.uid, sizeof(h.uid), 0);
    oct_scrie(h.gid, sizeof(h.gid), 0);
    oct_scrie(h.size, sizeof(h.size), cont_len);
    oct_scrie(h.mtime, sizeof(h.mtime), (unsigned long)st->st_mtime);

    if (S_ISDIR(st->st_mode)) {
        h.typeflag = '5';
    } else if (S_ISLNK(st->st_mode)) {
        h.typeflag = '2';
        if (linkname)
            snprintf(h.linkname, sizeof(h.linkname), "%s", linkname);
    } else {
        h.typeflag = '0';
    }

    memcpy(h.magic, "ustar", 6);
    memcpy(h.version, "00", 2);
    snprintf(h.uname, sizeof(h.uname), "%s", "root");
    snprintf(h.gname, sizeof(h.gname), "%s", "root");
    completeaza_chksum(&h);

    if (buf_adauga(b, &h, sizeof(h)) < 0) return -1;
    if (cont_len > 0) {
        if (buf_adauga(b, continut, cont_len) < 0) return -1;
        size_t rem = cont_len % TAR_BLOC;
        if (rem) {
            if (buf_zero(b, TAR_BLOC - rem) < 0) return -1;
        }
    }
    return 0;
}

static int walk(const char *root, const char *rel, Buffer *b) {
    char cale_disk[MAX_CALE + 64];
    if (rel[0] == '\0') {
        if ((size_t)snprintf(cale_disk, sizeof(cale_disk), "%s",
                              root) >= sizeof(cale_disk)) return -1;
    } else {
        if ((size_t)snprintf(cale_disk, sizeof(cale_disk), "%s/%s",
                              root, rel) >= sizeof(cale_disk)) return -1;
    }

    struct stat st;
    if (lstat(cale_disk, &st) < 0) return -1;

    if (S_ISLNK(st.st_mode)) {
        char lnk[256];
        ssize_t n = readlink(cale_disk, lnk, sizeof(lnk) - 1);
        if (n < 0) return -1;
        lnk[n] = '\0';
        return adauga_intrare(b, rel, &st, NULL, 0, lnk);
    }
    if (S_ISDIR(st.st_mode)) {
        if (rel[0] != '\0') {
            char nume_d[128];
            if ((size_t)snprintf(nume_d, sizeof(nume_d), "%s/",
                                  rel) >= sizeof(nume_d)) return -1;
            if (adauga_intrare(b, nume_d, &st, NULL, 0, NULL) < 0) return -1;
        }
        DIR *d = opendir(cale_disk);
        if (!d) return -1;
        struct dirent *ent;
        int rc = 0;
        while ((ent = readdir(d))) {
            if (strcmp(ent->d_name, ".") == 0 ||
                strcmp(ent->d_name, "..") == 0) continue;
            char sub_rel[MAX_CALE + 64];
            if (rel[0] == '\0') {
                if ((size_t)snprintf(sub_rel, sizeof(sub_rel), "%s",
                                      ent->d_name) >= sizeof(sub_rel)) {
                    rc = -1; break;
                }
            } else {
                if ((size_t)snprintf(sub_rel, sizeof(sub_rel), "%s/%s",
                                      rel, ent->d_name) >= sizeof(sub_rel)) {
                    rc = -1; break;
                }
            }
            if (walk(root, sub_rel, b) < 0) { rc = -1; break; }
        }
        closedir(d);
        return rc;
    }
    if (S_ISREG(st.st_mode)) {
        size_t sz;
        char *continut = citeste_fisier(cale_disk, &sz);
        if (!continut) return -1;
        int rc = adauga_intrare(b, rel, &st, continut, sz, NULL);
        free(continut);
        return rc;
    }
    cpm_debug("tar: ignorat fisier special: %s", cale_disk);
    return 0;
}

int tar_construieste(const char *src_dir, void **buf_out, size_t *len_out) {
    Buffer b = {0};
    if (walk(src_dir, "", &b) < 0) { free(b.buf); return -1; }
    /* terminator: 2 blocuri de 512 octeti zero */
    if (buf_zero(&b, TAR_BLOC * 2) < 0) { free(b.buf); return -1; }
    *buf_out = b.buf;
    *len_out = b.len;
    return 0;
}
