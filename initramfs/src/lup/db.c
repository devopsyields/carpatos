/* db.c — CRUD in /var/lup/db/installed/<nume>/{manifest,files} */
#define _GNU_SOURCE
#include "lup.h"

#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static int cale_pkg(char *dest, size_t cap, const char *nume) {
    if ((size_t)snprintf(dest, cap, "%s/%s",
                          DIR_INSTALLED, nume) >= cap) return -1;
    return 0;
}

int db_este_instalat(const char *nume) {
    char cale[MAX_CALE + 64];
    if (cale_pkg(cale, sizeof(cale), nume) < 0) return 0;
    struct stat st;
    return (stat(cale, &st) == 0 && S_ISDIR(st.st_mode)) ? 1 : 0;
}

int db_salveaza_pachet(const Manifest *m, const char *jurnal_fisiere) {
    if (asigura_dir(DIR_INSTALLED) < 0) {
        lup_err("nu pot crea %s: %s", DIR_INSTALLED, strerror(errno));
        return -1;
    }
    char cale[MAX_CALE + 64];
    if (cale_pkg(cale, sizeof(cale), m->nume) < 0) return -1;
    if (asigura_dir(cale) < 0) return -1;

    char mbuf[2048];
    int mlen = manifest_serializeaza(m, mbuf, sizeof(mbuf));
    if (mlen < 0) return -1;

    char fman[MAX_CALE + 96];
    if ((size_t)snprintf(fman, sizeof(fman), "%s/manifest",
                          cale) >= sizeof(fman)) return -1;
    if (scrie_fisier(fman, mbuf, (size_t)mlen) < 0) return -1;

    char ffil[MAX_CALE + 96];
    if ((size_t)snprintf(ffil, sizeof(ffil), "%s/files",
                          cale) >= sizeof(ffil)) return -1;
    size_t jl = jurnal_fisiere ? strlen(jurnal_fisiere) : 0;
    if (scrie_fisier(ffil, jurnal_fisiere ? jurnal_fisiere : "", jl) < 0) return -1;
    return 0;
}

int db_citeste_manifest(const char *nume, Manifest *m_out) {
    char cale[MAX_CALE + 96];
    if ((size_t)snprintf(cale, sizeof(cale), "%s/%s/manifest",
                          DIR_INSTALLED, nume) >= sizeof(cale)) return -1;
    size_t len;
    char *buf = citeste_fisier(cale, &len);
    if (!buf) return -1;
    int rc = manifest_parseaza(buf, len, m_out);
    free(buf);
    return rc;
}

char *db_citeste_fisiere(const char *nume) {
    char cale[MAX_CALE + 96];
    if ((size_t)snprintf(cale, sizeof(cale), "%s/%s/files",
                          DIR_INSTALLED, nume) >= sizeof(cale)) return NULL;
    size_t len;
    return citeste_fisier(cale, &len);
}

int db_sterge_pachet(const char *nume) {
    char cale[MAX_CALE + 64];
    if (cale_pkg(cale, sizeof(cale), nume) < 0) return -1;
    return sterge_recursiv(cale);
}

int db_listeaza(char ***nume_out, int *nr_out) {
    *nume_out = NULL;
    *nr_out = 0;
    DIR *d = opendir(DIR_INSTALLED);
    if (!d) return 0;  /* directorul inca nu exista = nimic instalat */

    char **lista = NULL;
    int n = 0, cap = 0;
    struct dirent *ent;
    while ((ent = readdir(d))) {
        if (ent->d_name[0] == '.') continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 8;
            char **nou = realloc(lista, (size_t)cap * sizeof(char *));
            if (!nou) { closedir(d); return -1; }
            lista = nou;
        }
        lista[n] = strdup(ent->d_name);
        if (!lista[n]) { closedir(d); return -1; }
        n++;
    }
    closedir(d);
    *nume_out = lista;
    *nr_out = n;
    return 0;
}

static int depinde_de(const char *candidat, const char *tinta) {
    Manifest m;
    if (db_citeste_manifest(candidat, &m) < 0) return 0;
    const char *p = m.depinde;
    size_t tl = strlen(tinta);
    while (*p) {
        while (*p == ',' || *p == ' ') p++;
        if (!*p) break;
        const char *q = p;
        while (*q && *q != ',' && *q != ' ') q++;
        size_t len = (size_t)(q - p);
        if (len == tl && memcmp(p, tinta, tl) == 0) return 1;
        p = q;
    }
    return 0;
}

int db_reverse_deps(const char *nume, char ***deps_out, int *nr_out) {
    char **toate;
    int ntoate;
    if (db_listeaza(&toate, &ntoate) < 0) return -1;

    char **rev = NULL;
    int nrev = 0, cap = 0;
    for (int i = 0; i < ntoate; i++) {
        if (strcmp(toate[i], nume) == 0) continue;
        if (depinde_de(toate[i], nume)) {
            if (nrev == cap) {
                cap = cap ? cap * 2 : 4;
                char **nou = realloc(rev, (size_t)cap * sizeof(char *));
                if (!nou) break;
                rev = nou;
            }
            rev[nrev++] = strdup(toate[i]);
        }
    }
    for (int i = 0; i < ntoate; i++) free(toate[i]);
    free(toate);

    *deps_out = rev;
    *nr_out = nrev;
    return 0;
}
