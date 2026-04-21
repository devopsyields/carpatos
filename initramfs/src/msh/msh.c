/* msh.c — Shell minim pentru CarpatOS
 *
 * Caracteristici MVP:
 *   - citire linie cu editare minima (backspace)
 *   - parsare in argv simplu (whitespace-separated)
 *   - builtins: exit, help, cd, pwd, echo, versiune
 *   - executie binare externe din PATH
 *
 * Dupa MVP vom adauga: pipes, redirecturi, history, glob.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../common/mesaje.h"

#define MAX_LINIE 1024
#define MAX_ARG   64

/* Scriere directa, fara buffering */
static void scrie(int fd, const char *s) {
    size_t len = strlen(s);
    while (len > 0) {
        ssize_t n = write(fd, s, len);
        if (n <= 0) return;
        s += n;
        len -= (size_t)n;
    }
}

static void out(const char *s) { scrie(1, s); }
static void err(const char *s) { scrie(2, s); }

/* Citeste o linie de la stdin, max-1 octeti, terminata cu \n.
 * Intoarce lungimea (>=0) sau -1 la EOF / eroare. */
static int citeste_linie(char *buf, size_t max) {
    size_t n = 0;
    char c;
    for (;;) {
        ssize_t r = read(0, &c, 1);
        if (r <= 0) return -1;
        if (c == '\n') break;
        if (c == '\b' || c == 0x7f) {
            if (n > 0) n--;
            continue;
        }
        if (n < max - 1) buf[n++] = c;
    }
    buf[n] = '\0';
    return (int)n;
}

/* Parseaza linia in argv, modificand buf-ul (tokenizer in-place) */
static int parseaza(char *linie, char **argv, int max) {
    int n = 0;
    char *p = linie;
    while (*p && n < max - 1) {
        while (*p == ' ' || *p == '\t') *p++ = '\0';
        if (!*p) break;
        argv[n++] = p;
        while (*p && *p != ' ' && *p != '\t') p++;
    }
    argv[n] = NULL;
    return n;
}

/* ===== Builtins ===== */

static int bi_exit(char **argv) {
    (void)argv;
    out(MSH_BYE);
    exit(0);
}

static int bi_help(char **argv) {
    (void)argv;
    out("Builtins disponibile:\n");
    out("  exit       — iesire din shell\n");
    out("  help       — acest mesaj\n");
    out("  cd [dir]   — schimba directorul curent\n");
    out("  pwd        — afiseaza directorul curent\n");
    out("  echo ...   — afiseaza argumentele\n");
    out("  versiune   — versiunea CarpatOS\n");
    out("\nOrice alta comanda e cautata ca binar extern in PATH.\n");
    return 0;
}

static int bi_cd(char **argv) {
    const char *tinta = argv[1] ? argv[1] : "/";
    if (chdir(tinta) < 0) {
        err("cd: nu pot schimba in ");
        err(tinta);
        err(": ");
        err(strerror(errno));
        err("\n");
        return 1;
    }
    return 0;
}

static int bi_pwd(char **argv) {
    (void)argv;
    char buf[4096];
    if (getcwd(buf, sizeof(buf))) {
        out(buf);
        out("\n");
        return 0;
    }
    err("pwd: eroare\n");
    return 1;
}

static int bi_echo(char **argv) {
    for (int i = 1; argv[i]; i++) {
        out(argv[i]);
        if (argv[i + 1]) out(" ");
    }
    out("\n");
    return 0;
}

static int bi_versiune(char **argv) {
    (void)argv;
    out(CARPATOS_NUME " " CARPATOS_VERSIUNE "\n");
    return 0;
}

/* Tabel de builtins */
struct builtin {
    const char *nume;
    int (*func)(char **);
};

static struct builtin BUILTINS[] = {
    {"exit",     bi_exit},
    {"help",     bi_help},
    {"cd",       bi_cd},
    {"pwd",      bi_pwd},
    {"echo",     bi_echo},
    {"versiune", bi_versiune},
    {NULL, NULL}
};

static int gaseste_si_ruleaza_builtin(char **argv) {
    for (int i = 0; BUILTINS[i].nume; i++) {
        if (strcmp(argv[0], BUILTINS[i].nume) == 0) {
            return BUILTINS[i].func(argv);
        }
    }
    return -1;  /* nu e builtin */
}

/* Executa un binar extern prin fork+exec */
static int executa_extern(char **argv) {
    pid_t pid = fork();
    if (pid < 0) {
        err("msh: fork() a esuat\n");
        return 1;
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        /* daca ajungem aici, exec a esuat */
        err("msh: comanda necunoscuta: ");
        err(argv[0]);
        err("\n");
        _exit(127);
    }
    int status;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return 1;
}

int main(void) {
    char linie[MAX_LINIE];
    char *argv[MAX_ARG];

    out(MSH_BANNER);
    out("Tasteaza 'help' pentru lista de comenzi.\n\n");

    for (;;) {
        out(MSH_PROMPT);
        int n = citeste_linie(linie, sizeof(linie));
        if (n < 0) {
            /* EOF — iesim curat */
            out("\n");
            break;
        }
        if (n == 0) continue;

        int argc = parseaza(linie, argv, MAX_ARG);
        if (argc == 0) continue;

        int rc = gaseste_si_ruleaza_builtin(argv);
        if (rc < 0) rc = executa_extern(argv);
        (void)rc;  /* $? vine in faza urmatoare */
    }

    return 0;
}
