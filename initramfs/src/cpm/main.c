/* main.c — dispatch principal al lui cpm */
#define _GNU_SOURCE
#include "cpm.h"

#include <stdio.h>
#include <string.h>

static int cmd_version(int argc, char **argv) {
    (void)argc; (void)argv;
    printf("cpm %s — package manager CarpatOS\n", CPM_VERSIUNE);
    return 0;
}

static int cmd_help(int argc, char **argv);

static struct {
    const char *nume;
    int (*func)(int, char **);
    const char *desc;
} COMENZI[] = {
    {"install", cmd_install, "instaleaza pachete (cu dependente)"},
    {"remove",  cmd_remove,  "dezinstaleaza pachete [--force|-f]"},
    {"local",   cmd_local,   "instaleaza fisier .cpm direct (fara deps)"},
    {"list",    cmd_list,    "instalate (sau '-a' pentru disponibile)"},
    {"search",  cmd_search,  "cauta in repo dupa nume / descriere"},
    {"info",    cmd_info,    "detalii despre un pachet"},
    {"update",  cmd_update,  "reconstruieste indexul repo-ului local"},
    {"build",   cmd_build,   "construieste .cpm din director sursa"},
    {"version", cmd_version, "afiseaza versiunea lui cpm"},
    {"help",    cmd_help,    "acest mesaj"},
    {NULL, NULL, NULL}
};

static int cmd_help(int argc, char **argv) {
    (void)argc; (void)argv;
    printf("cpm %s — package manager CarpatOS\n\n", CPM_VERSIUNE);
    printf("Folosire: cpm <comanda> [argumente...]\n\n");
    printf("Comenzi:\n");
    for (int i = 0; COMENZI[i].nume; i++)
        printf("  %-9s %s\n", COMENZI[i].nume, COMENZI[i].desc);
    printf("\nVariabile de mediu:\n");
    printf("  CPM_DEBUG=1   activeaza mesaje de debug\n");
    printf("  CPM_ROOT=dir  prefixeaza toate path-urile cu dir (pentru build)\n");
    return 0;
}

int main(int argc, char **argv) {
    cpm_init_paths();
    if (argc < 2) { cmd_help(0, NULL); return 1; }
    for (int i = 0; COMENZI[i].nume; i++) {
        if (strcmp(argv[1], COMENZI[i].nume) == 0)
            return COMENZI[i].func(argc - 2, argv + 2);
    }
    cpm_err("comanda necunoscuta: %s", argv[1]);
    cmd_help(0, NULL);
    return 1;
}
