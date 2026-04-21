/* main.c — dispatch principal al lui lup */
#define _GNU_SOURCE
#include "lup.h"

#include <stdio.h>
#include <string.h>

static int cmd_version(int argc, char **argv) {
    (void)argc; (void)argv;
    printf("lup %s — package manager CarpatOS\n", LUP_VERSIUNE);
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
    {"local",   cmd_local,   "instaleaza fisier .lup direct (fara deps)"},
    {"list",    cmd_list,    "instalate (sau '-a' pentru disponibile)"},
    {"search",  cmd_search,  "cauta in repo dupa nume / descriere"},
    {"info",    cmd_info,    "detalii despre un pachet"},
    {"update",  cmd_update,  "reconstruieste indexul repo-ului local"},
    {"build",   cmd_build,   "construieste .lup din director sursa"},
    {"version", cmd_version, "afiseaza versiunea lui lup"},
    {"help",    cmd_help,    "acest mesaj"},
    {NULL, NULL, NULL}
};

static int cmd_help(int argc, char **argv) {
    (void)argc; (void)argv;
    printf("lup %s — package manager CarpatOS\n\n", LUP_VERSIUNE);
    printf("Folosire: lup <comanda> [argumente...]\n\n");
    printf("Comenzi:\n");
    for (int i = 0; COMENZI[i].nume; i++)
        printf("  %-9s %s\n", COMENZI[i].nume, COMENZI[i].desc);
    printf("\nVariabile de mediu:\n");
    printf("  LUP_DEBUG=1   activeaza mesaje de debug\n");
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) { cmd_help(0, NULL); return 1; }
    for (int i = 0; COMENZI[i].nume; i++) {
        if (strcmp(argv[1], COMENZI[i].nume) == 0)
            return COMENZI[i].func(argc - 2, argv + 2);
    }
    lup_err("comanda necunoscuta: %s", argv[1]);
    cmd_help(0, NULL);
    return 1;
}
