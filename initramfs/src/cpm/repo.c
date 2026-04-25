/* repo.c — index de repo simplu
 *
 * Format repo.index (o linie / pachet):
 *   nume|versiune|arh|descriere|dep1,dep2|fisier.cpm|sha256
 *
 * Campul sha256 e optional pentru compatibilitate cu repo-uri vechi —
 * absenta lui inseamna "no integrity check" (acceptabil pentru repo-uri
 * locale, refuzat pe download remote).
 */
#define _GNU_SOURCE
#include "cpm.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int parseaza_linie(char *linie, Manifest *m) {
    memset(m, 0, sizeof(*m));
    char *campuri[7] = {0};
    int n = 0;
    campuri[n++] = linie;
    for (char *p = linie; *p; p++) {
        if (*p == '|') {
            *p = '\0';
            if (n < 7) campuri[n++] = p + 1;
        }
    }
    if (n < 6) return -1;  /* min 6 campuri (sha256 optional) */
    snprintf(m->nume,        sizeof(m->nume),        "%s", campuri[0]);
    snprintf(m->versiune,    sizeof(m->versiune),    "%s", campuri[1]);
    snprintf(m->arhitectura, sizeof(m->arhitectura), "%s", campuri[2]);
    snprintf(m->descriere,   sizeof(m->descriere),   "%s", campuri[3]);
    snprintf(m->depinde,     sizeof(m->depinde),     "%s", campuri[4]);
    snprintf(m->fisier,      sizeof(m->fisier),      "%s", campuri[5]);
    if (n >= 7 && campuri[6])
        snprintf(m->sha256,  sizeof(m->sha256),      "%s", campuri[6]);
    return 0;
}

int repo_listeaza(Manifest **lista_out, int *nr_out) {
    *lista_out = NULL;
    *nr_out = 0;
    size_t len;
    char *buf = citeste_fisier(FILE_REPO_INDEX, &len);
    if (!buf) return 0;  /* index absent = repo gol */

    Manifest *lista = NULL;
    int n = 0, cap = 0;
    char *p = buf;
    char *fin = buf + len;
    while (p < fin) {
        char *linie = p;
        while (p < fin && *p != '\n') p++;
        if (p < fin) { *p = '\0'; p++; }
        if (*linie == '\0' || *linie == '#') continue;
        Manifest m;
        if (parseaza_linie(linie, &m) < 0) continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 8;
            Manifest *nou = realloc(lista, (size_t)cap * sizeof(Manifest));
            if (!nou) { free(buf); free(lista); return -1; }
            lista = nou;
        }
        lista[n++] = m;
    }
    free(buf);
    *lista_out = lista;
    *nr_out = n;
    return 0;
}

int repo_gaseste(const char *nume, Manifest *m_out) {
    Manifest *lista;
    int n;
    if (repo_listeaza(&lista, &n) < 0) return -1;
    int gasit = 0;
    for (int i = 0; i < n; i++) {
        if (strcmp(lista[i].nume, nume) == 0) {
            *m_out = lista[i];
            gasit = 1;
            break;
        }
    }
    free(lista);
    return gasit ? 0 : -1;
}

int repo_actualizeaza_index(void) {
    if (asigura_dir(DIR_DB) < 0) {
        cpm_err("nu pot crea %s", DIR_DB);
        return -1;
    }
    DIR *d = opendir(DIR_REPO);
    if (!d) {
        cpm_err("nu pot deschide %s", DIR_REPO);
        return -1;
    }

    FILE *idx = fopen(FILE_REPO_INDEX, "w");
    if (!idx) {
        closedir(d);
        cpm_err("nu pot scrie %s", FILE_REPO_INDEX);
        return -1;
    }

    struct dirent *ent;
    int nr = 0;
    while ((ent = readdir(d))) {
        const char *nume = ent->d_name;
        size_t ln = strlen(nume);
        if (ln < 5 || strcmp(nume + ln - 4, ".cpm") != 0) continue;

        char cale[MAX_CALE + 64];
        if ((size_t)snprintf(cale, sizeof(cale), "%s/%s",
                              DIR_REPO, nume) >= sizeof(cale)) continue;

        Manifest m;
        void *payload;
        size_t plen;
        if (cpm_incarca(cale, &m, &payload, &plen) < 0) {
            cpm_err("ignorat (invalid): %s", nume);
            continue;
        }
        free(payload);

        char hash[MAX_SHA256] = "";
        if (sha256_file(cale, hash) < 0) {
            cpm_err("ignorat (sha256 esuat): %s", nume);
            continue;
        }

        fprintf(idx, "%s|%s|%s|%s|%s|%s|%s\n",
                m.nume, m.versiune, m.arhitectura,
                m.descriere, m.depinde, nume, hash);
        nr++;
    }
    closedir(d);
    fclose(idx);
    cpm_info("Index repo actualizat: %d pachete in %s", nr, DIR_REPO);
    return 0;
}
