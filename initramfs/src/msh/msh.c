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

/* Citeste o linie de la fd, max-1 octeti, terminata cu \n.
 * Intoarce lungimea (>=0) sau -1 la EOF / eroare.
 * interactiv=1 → tratam backspace/DEL; interactiv=0 → citire cruda (script). */
static int citeste_linie(int fd, char *buf, size_t max, int interactiv) {
    size_t n = 0;
    char c;
    for (;;) {
        ssize_t r = read(fd, &c, 1);
        if (r <= 0) {
            if (n == 0) return -1;
            break;
        }
        if (c == '\n') break;
        if (interactiv && (c == '\b' || c == 0x7f)) {
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
    int cod = 0;
    if (argv[1]) cod = atoi(argv[1]);
    /* Banner de iesire doar in mod interactiv (stdin tty) */
    if (isatty(0)) out(MSH_BYE);
    exit(cod);
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

/* Executa linii citite din fd (fie stdin interactiv, fie script). */
static int ruleaza_din(int fd, int interactiv) {
    char linie[MAX_LINIE];
    char *argv[MAX_ARG];
    int ultim_rc = 0;

    if (interactiv) {
        out(MSH_BANNER);
        out("Tasteaza 'help' pentru lista de comenzi.\n\n");
    }

    for (;;) {
        if (interactiv) out(MSH_PROMPT);
        int n = citeste_linie(fd, linie, sizeof(linie), interactiv);
        if (n < 0) {
            if (interactiv) out("\n");
            break;
        }
        if (n == 0) continue;

        /* Trim leading whitespace pentru detectie shebang/comentariu */
        char *l = linie;
        while (*l == ' ' || *l == '\t') l++;
        if (*l == '\0' || *l == '#') continue;

        int argc = parseaza(l, argv, MAX_ARG);
        if (argc == 0) continue;

        int rc = gaseste_si_ruleaza_builtin(argv);
        if (rc < 0) rc = executa_extern(argv);
        ultim_rc = rc;
    }

    return ultim_rc;
}

int main(int argc, char **argv) {
    if (argc >= 2) {
        /* Mod script: msh <fisier> */
        int fd = open(argv[1], O_RDONLY);
        if (fd < 0) {
            err("msh: nu pot deschide ");
            err(argv[1]);
            err(": ");
            err(strerror(errno));
            err("\n");
            return 127;
        }
        int rc = ruleaza_din(fd, 0);
        close(fd);
        return rc;
    }
    return ruleaza_din(0, isatty(0));
}
