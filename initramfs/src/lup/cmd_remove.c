/* cmd_remove.c — dezinstalare cu verificare reverse-deps */
#define _GNU_SOURCE
#include "lup.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Sterge fisierele/dir-urile listate (linie cu linie). Iteratie inversa
 * ca sa stergem intai fisierele si abia apoi directoarele lor. */
static void sterge_fisiere(const char *lista_text) {
    char **lini = NULL;
    int n = 0, cap = 0;
    const char *p = lista_text;
    while (*p) {
        const char *q = p;
        while (*q && *q != '\n') q++;
        size_t len = (size_t)(q - p);
        if (len > 0) {
            if (n == cap) {
                cap = cap ? cap * 2 : 16;
                char **nou = realloc(lini, (size_t)cap * sizeof(char *));
                if (!nou) break;
                lini = nou;
            }
            lini[n] = malloc(len + 1);
            if (!lini[n]) break;
            memcpy(lini[n], p, len);
            lini[n][len] = '\0';
            n++;
        }
        p = (*q == '\n') ? q + 1 : q;
    }
    for (int i = n - 1; i >= 0; i--) {
        struct stat st;
        if (lstat(lini[i], &st) == 0) {
            if (S_ISDIR(st.st_mode)) {
                rmdir(lini[i]);  /* tolerat daca dir-ul nu e gol */
            } else {
                unlink(lini[i]);
            }
        }
    }
    for (int i = 0; i < n; i++) free(lini[i]);
    free(lini);
}

int cmd_remove(int argc, char **argv) {
    int force = 0;
    char **pachete = NULL;
    int np = 0;
    if (argc > 0) {
        pachete = malloc((size_t)argc * sizeof(char *));
        if (!pachete) return 1;
        for (int i = 0; i < argc; i++) {
            if (strcmp(argv[i], "--force") == 0 ||
                strcmp(argv[i], "-f") == 0) {
                force = 1;
            } else {
                pachete[np++] = argv[i];
            }
        }
    }
    if (np == 0) {
        lup_err("folosire: lup remove <pachet>... [--force|-f]");
        free(pachete);
        return 1;
    }

    int rc = 0;
    for (int i = 0; i < np; i++) {
        const char *nume = pachete[i];
        if (!db_este_instalat(nume)) {
            lup_err("%s nu este instalat", nume);
            rc = 1;
            continue;
        }
        if (!force) {
            char **rev = NULL;
            int nrev = 0;
            db_reverse_deps(nume, &rev, &nrev);
            if (nrev > 0) {
                fprintf(stderr, "lup: eroare: %s este cerut de:", nume);
                for (int j = 0; j < nrev; j++)
                    fprintf(stderr, " %s", rev[j]);
                fprintf(stderr, "\n");
                fprintf(stderr,
                        "Foloseste --force pentru a sterge oricum.\n");
                for (int j = 0; j < nrev; j++) free(rev[j]);
                free(rev);
                rc = 1;
                continue;
            }
            for (int j = 0; j < nrev; j++) free(rev[j]);
            free(rev);
        }
        char *fisiere = db_citeste_fisiere(nume);
        if (fisiere) { sterge_fisiere(fisiere); free(fisiere); }
        if (db_sterge_pachet(nume) < 0) {
            lup_err("nu pot sterge intrarea db pentru %s", nume);
            rc = 1;
            continue;
        }
        lup_info("Dezinstalat: %s", nume);
    }
    free(pachete);
    return rc;
}
