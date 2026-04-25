/* cmd_install.c — rezolvare deps + instalare; cmd_local pentru fisier .cpm */
#define _GNU_SOURCE
#include "cpm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Destinatia de extractie: CPM_ROOT daca e setat, altfel "/". Permite
 * cpm sa fie folosit pentru staged build (CPM_ROOT=rootfs/ ...). */
static const char *dest_root(void) {
    const char *r = getenv("CPM_ROOT");
    if (r && *r) return r;
    return "/";
}

typedef struct {
    char **items;
    int n;
    int cap;
} Lista;

static int lista_contine(const Lista *l, const char *s) {
    for (int i = 0; i < l->n; i++)
        if (strcmp(l->items[i], s) == 0) return 1;
    return 0;
}

static int lista_adauga(Lista *l, const char *s) {
    if (l->n == l->cap) {
        int nou = l->cap ? l->cap * 2 : 8;
        char **p = realloc(l->items, (size_t)nou * sizeof(char *));
        if (!p) return -1;
        l->items = p;
        l->cap = nou;
    }
    l->items[l->n] = strdup(s);
    if (!l->items[l->n]) return -1;
    l->n++;
    return 0;
}

static void lista_scoate(Lista *l, const char *s) {
    for (int i = 0; i < l->n; i++) {
        if (strcmp(l->items[i], s) == 0) {
            free(l->items[i]);
            memmove(&l->items[i], &l->items[i + 1],
                    (size_t)(l->n - i - 1) * sizeof(char *));
            l->n--;
            return;
        }
    }
}

static void lista_elibereaza(Lista *l) {
    for (int i = 0; i < l->n; i++) free(l->items[i]);
    free(l->items);
    l->items = NULL;
    l->n = l->cap = 0;
}

/* DFS aprox. topologic — completeaza "ordine".
 * Pachetele de baza Ubuntu au cicluri legitime (libc6 <-> libgcc-s1).
 * Cand detectam un ciclu, doar logam si continuam — pachetele se vor
 * instala amandoua, ordinea exacta nu mai e strict topologica. */
static int rezolva(const char *nume, Lista *ordine, Lista *in_curs) {
    if (db_este_instalat(nume)) return 0;
    if (lista_contine(ordine, nume)) return 0;
    if (lista_contine(in_curs, nume)) {
        cpm_debug("ciclu detectat la %s, continui", nume);
        return 0;
    }
    if (lista_adauga(in_curs, nume) < 0) return -1;

    Manifest m;
    if (repo_gaseste(nume, &m) < 0) {
        cpm_err("pachetul '%s' nu este in repo", nume);
        return -1;
    }

    /* itereaza prin m.depinde fara sa-l modifici */
    const char *p = m.depinde;
    while (*p) {
        while (*p == ',' || *p == ' ') p++;
        if (!*p) break;
        const char *q = p;
        while (*q && *q != ',' && *q != ' ') q++;
        char dep_nume[MAX_NUME];
        size_t len = (size_t)(q - p);
        if (len >= sizeof(dep_nume)) len = sizeof(dep_nume) - 1;
        memcpy(dep_nume, p, len);
        dep_nume[len] = '\0';
        if (rezolva(dep_nume, ordine, in_curs) < 0) return -1;
        p = q;
    }

    if (lista_adauga(ordine, nume) < 0) return -1;
    lista_scoate(in_curs, nume);
    return 0;
}

typedef struct {
    FILE *jurnal;
} JurnalCtx;

static void jurnal_scrie(const char *cale, void *ctx) {
    JurnalCtx *j = (JurnalCtx *)ctx;
    fprintf(j->jurnal, "%s\n", cale);
}

/* Extrage payload-ul dintr-un .cpm intr-un dest_dir si scrie jurnalul fisierelor */
static int extrage_si_inregistreaza(const Manifest *m, const char *cale_cpm,
                                     const char *dest_dir) {
    Manifest m2;
    void *payload;
    size_t plen;
    if (cpm_incarca(cale_cpm, &m2, &payload, &plen) < 0) return -1;

    char *jurnal_buf = NULL;
    size_t jurnal_len = 0;
    FILE *jurnal = open_memstream(&jurnal_buf, &jurnal_len);
    if (!jurnal) {
        free(payload);
        cpm_err("open_memstream esuat");
        return -1;
    }

    JurnalCtx ctx = { .jurnal = jurnal };
    int rc = tar_extrage(payload, plen, dest_dir, jurnal_scrie, &ctx);
    fclose(jurnal);
    free(payload);

    if (rc < 0) {
        free(jurnal_buf);
        cpm_err("extractie esuata pentru %s", m->nume);
        return -1;
    }

    if (db_salveaza_pachet(&m2, jurnal_buf) < 0) {
        free(jurnal_buf);
        return -1;
    }
    free(jurnal_buf);
    return 0;
}

/* Cauta .cpm-ul: intai in DIR_REPO (local), apoi in DIR_CACHE (descarcat
 * deja), in final descarca de la repo URL. Verifica sha256 daca avem
 * referinta in repo.index. */
static int gaseste_sau_descarca(const Manifest *m, char *cale_cpm,
                                 size_t cap) {
    if ((size_t)snprintf(cale_cpm, cap, "%s/%s",
                          DIR_REPO, m->fisier) >= cap) return -1;
    if (access(cale_cpm, R_OK) == 0) return 0;

    if ((size_t)snprintf(cale_cpm, cap, "%s/%s",
                          DIR_CACHE, m->fisier) >= cap) return -1;
    if (access(cale_cpm, R_OK) == 0) return 0;

    /* trebuie descarcat */
    char base_url[MAX_CALE];
    if (cpm_repo_url(base_url, sizeof(base_url)) < 0) {
        cpm_err("pachet '%s' lipsa local si URL repo nesetat "
                "(setati CPM_REPO_URL sau /etc/cpm/repo.url)", m->nume);
        return -1;
    }
    if (asigura_dir(DIR_CACHE) < 0) return -1;

    char url[MAX_CALE + 128];
    if ((size_t)snprintf(url, sizeof(url), "%s/pool/%s",
                          base_url, m->fisier) >= sizeof(url)) {
        cpm_err("URL prea lung pentru %s", m->fisier);
        return -1;
    }
    cpm_info("Descarc %s", url);
    if (http_descarca(url, cale_cpm) < 0) return -1;
    return 0;
}

static int verifica_sha256(const Manifest *m, const char *cale_cpm) {
    if (m->sha256[0] == '\0') return 0;  /* fara hash, nu verificam */
    char obtinut[MAX_SHA256];
    if (sha256_file(cale_cpm, obtinut) < 0) {
        cpm_err("sha256: nu pot citi %s", cale_cpm);
        return -1;
    }
    if (strcmp(obtinut, m->sha256) != 0) {
        cpm_err("sha256 nu corespunde pentru %s:", m->fisier);
        cpm_err("  asteptat: %s", m->sha256);
        cpm_err("  obtinut:  %s", obtinut);
        return -1;
    }
    return 0;
}

static int instaleaza_din_repo(const Manifest *m) {
    char cale_cpm[MAX_CALE + 64];
    if (gaseste_sau_descarca(m, cale_cpm, sizeof(cale_cpm)) < 0) return -1;
    if (verifica_sha256(m, cale_cpm) < 0) return -1;
    cpm_info("Instalez %s-%s", m->nume, m->versiune);
    return extrage_si_inregistreaza(m, cale_cpm, dest_root());
}

int cmd_install(int argc, char **argv) {
    if (argc < 1) {
        cpm_err("folosire: cpm install <pachet>...");
        return 1;
    }
    Lista ordine = {0}, in_curs = {0};
    int rc = 0;
    for (int i = 0; i < argc; i++) {
        if (rezolva(argv[i], &ordine, &in_curs) < 0) { rc = 1; goto sfarsit; }
    }
    for (int i = 0; i < ordine.n; i++) {
        Manifest m;
        if (repo_gaseste(ordine.items[i], &m) < 0) { rc = 1; goto sfarsit; }
        if (instaleaza_din_repo(&m) < 0) { rc = 1; goto sfarsit; }
    }
sfarsit:
    lista_elibereaza(&ordine);
    lista_elibereaza(&in_curs);
    return rc;
}

int cmd_local(int argc, char **argv) {
    if (argc < 1) {
        cpm_err("folosire: cpm local <fisier.cpm>...");
        return 1;
    }
    for (int i = 0; i < argc; i++) {
        Manifest m;
        void *payload;
        size_t plen;
        if (cpm_incarca(argv[i], &m, &payload, &plen) < 0) return 1;
        free(payload);  /* eliberam — vom reciti in extrage_si_inregistreaza */
        cpm_info("Instalez %s-%s (din %s)", m.nume, m.versiune, argv[i]);
        if (extrage_si_inregistreaza(&m, argv[i], dest_root()) < 0) return 1;
    }
    return 0;
}
