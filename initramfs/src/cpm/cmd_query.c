/* cmd_query.c — list, search, info, update */
#define _GNU_SOURCE
#include "cpm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

int cmd_list(int argc, char **argv) {
    int disponibile = (argc >= 1 &&
                       (strcmp(argv[0], "-a") == 0 ||
                        strcmp(argv[0], "--all") == 0));
    if (disponibile) {
        Manifest *lista;
        int n;
        if (repo_listeaza(&lista, &n) < 0) return 1;
        if (n == 0) {
            cpm_info("(niciun pachet disponibil)");
            free(lista);
            return 0;
        }
        for (int i = 0; i < n; i++) {
            printf("%-20s %-10s %-8s %s\n",
                   lista[i].nume, lista[i].versiune,
                   lista[i].arhitectura, lista[i].descriere);
        }
        free(lista);
    } else {
        char **nume;
        int n;
        if (db_listeaza(&nume, &n) < 0) return 1;
        if (n == 0) {
            cpm_info("(niciun pachet instalat)");
            free(nume);
            return 0;
        }
        for (int i = 0; i < n; i++) {
            Manifest m;
            if (db_citeste_manifest(nume[i], &m) == 0)
                printf("%-20s %s\n", m.nume, m.versiune);
            else
                printf("%-20s ?\n", nume[i]);
            free(nume[i]);
        }
        free(nume);
    }
    return 0;
}

int cmd_search(int argc, char **argv) {
    if (argc < 1) {
        cpm_err("folosire: cpm search <termen>");
        return 1;
    }
    Manifest *lista;
    int n;
    if (repo_listeaza(&lista, &n) < 0) return 1;
    int gasite = 0;
    for (int i = 0; i < n; i++) {
        if (strcasestr(lista[i].nume, argv[0]) ||
            strcasestr(lista[i].descriere, argv[0])) {
            printf("%-20s %-10s %s\n",
                   lista[i].nume, lista[i].versiune, lista[i].descriere);
            gasite++;
        }
    }
    free(lista);
    if (gasite == 0) cpm_info("(nicio potrivire)");
    return 0;
}

int cmd_info(int argc, char **argv) {
    if (argc < 1) {
        cpm_err("folosire: cpm info <pachet>");
        return 1;
    }
    Manifest m;
    if (db_citeste_manifest(argv[0], &m) == 0) {
        printf("=== Instalat ===\n");
        manifest_afiseaza(&m);
        return 0;
    }
    if (repo_gaseste(argv[0], &m) == 0) {
        printf("=== Disponibil in repo ===\n");
        manifest_afiseaza(&m);
        return 0;
    }
    cpm_err("pachetul '%s' nu a fost gasit", argv[0]);
    return 1;
}

int cmd_update(int argc, char **argv) {
    (void)argc;
    (void)argv;
    char base_url[MAX_CALE];
    if (cpm_repo_url(base_url, sizeof(base_url)) == 0) {
        char url[MAX_CALE + 64];
        if ((size_t)snprintf(url, sizeof(url), "%s/repo.index",
                              base_url) >= sizeof(url)) {
            cpm_err("URL prea lung");
            return 1;
        }
        if (asigura_dir(DIR_DB) < 0) {
            cpm_err("nu pot crea %s", DIR_DB);
            return 1;
        }
        cpm_info("Descarc %s", url);
        if (http_descarca(url, FILE_REPO_INDEX) < 0) return 1;
        Manifest *lista = NULL;
        int n = 0;
        if (repo_listeaza(&lista, &n) == 0) {
            cpm_info("Index repo descarcat: %d pachete", n);
            free(lista);
        }
        return 0;
    }
    /* fallback: scanare locala */
    return repo_actualizeaza_index() < 0 ? 1 : 0;
}
