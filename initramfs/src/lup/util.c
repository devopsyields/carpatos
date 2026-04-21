/* util.c — logging + operatii de fisier pentru lup */
#define _GNU_SOURCE
#include "lup.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int debug_activ(void) {
    const char *s = getenv("LUP_DEBUG");
    return s && *s && strcmp(s, "0") != 0;
}

void lup_info(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stdout, fmt, ap);
    va_end(ap);
    fputc('\n', stdout);
}

void lup_err(const char *fmt, ...) {
    fputs("lup: eroare: ", stderr);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

void lup_debug(const char *fmt, ...) {
    if (!debug_activ()) return;
    fputs("[lup-debug] ", stderr);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

int asigura_dir(const char *cale) {
    if (cale == NULL || cale[0] == '\0') {
        errno = EINVAL;
        return -1;
    }
    char tmp[MAX_CALE];
    size_t n = strlen(cale);
    if (n >= sizeof(tmp)) { errno = ENAMETOOLONG; return -1; }
    memcpy(tmp, cale, n + 1);
    for (size_t i = 1; i < n; i++) {
        if (tmp[i] == '/') {
            tmp[i] = '\0';
            if (mkdir(tmp, 0755) < 0 && errno != EEXIST) return -1;
            tmp[i] = '/';
        }
    }
    if (mkdir(tmp, 0755) < 0 && errno != EEXIST) return -1;
    return 0;
}

int sterge_recursiv(const char *cale) {
    struct stat st;
    if (lstat(cale, &st) < 0) return (errno == ENOENT) ? 0 : -1;
    if (S_ISDIR(st.st_mode)) {
        DIR *d = opendir(cale);
        if (!d) return -1;
        struct dirent *ent;
        while ((ent = readdir(d))) {
            if (strcmp(ent->d_name, ".") == 0 ||
                strcmp(ent->d_name, "..") == 0) continue;
            char sub[MAX_CALE + 64];
            if ((size_t)snprintf(sub, sizeof(sub), "%s/%s",
                                  cale, ent->d_name) >= sizeof(sub)) {
                closedir(d);
                return -1;
            }
            if (sterge_recursiv(sub) < 0) { closedir(d); return -1; }
        }
        closedir(d);
        return rmdir(cale);
    }
    return unlink(cale);
}

char *citeste_fisier(const char *cale, size_t *len_out) {
    FILE *f = fopen(cale, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) < 0) { fclose(f); return NULL; }
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; }
    rewind(f);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; }
    if (sz > 0 && fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        free(buf); fclose(f); return NULL;
    }
    buf[sz] = '\0';
    fclose(f);
    if (len_out) *len_out = (size_t)sz;
    return buf;
}

int scrie_fisier(const char *cale, const void *buf, size_t len) {
    FILE *f = fopen(cale, "wb");
    if (!f) return -1;
    if (len && fwrite(buf, 1, len, f) != len) { fclose(f); return -1; }
    return fclose(f) == 0 ? 0 : -1;
}

int copiaza_fisier(const char *sursa, const char *dest) {
    int fs = open(sursa, O_RDONLY);
    if (fs < 0) return -1;
    struct stat st;
    if (fstat(fs, &st) < 0) { close(fs); return -1; }
    int fd = open(dest, O_WRONLY | O_CREAT | O_TRUNC, st.st_mode & 0777);
    if (fd < 0) { close(fs); return -1; }
    char buf[8192];
    ssize_t n;
    while ((n = read(fs, buf, sizeof(buf))) > 0) {
        ssize_t off = 0;
        while (off < n) {
            ssize_t w = write(fd, buf + off, (size_t)(n - off));
            if (w <= 0) { close(fs); close(fd); return -1; }
            off += w;
        }
    }
    close(fs);
    close(fd);
    return n < 0 ? -1 : 0;
}
