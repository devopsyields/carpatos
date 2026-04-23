/* cmd_build.c — construieste un .cpm dintr-un director sursa cu CPMBUILD + build.sh */
#define _GNU_SOURCE
#include "cpm.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static int citeste_cpmbuild(const char *cale, Manifest *m) {
    size_t len;
    char *buf = citeste_fisier(cale, &len);
    if (!buf) {
        cpm_err("nu pot citi %s", cale);
        return -1;
    }
    int rc = manifest_parseaza(buf, len, m);
    free(buf);
    return rc;
}

int cmd_build(int argc, char **argv) {
    if (argc < 1) {
        cpm_err("folosire: cpm build <dir> [-o <iesire.cpm>]");
        return 1;
    }
    const char *src = argv[0];
    const char *out = NULL;
    const char *arh_override = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
            out = argv[++i];
        } else if (strcmp(argv[i], "--arch") == 0 && i + 1 < argc) {
            arh_override = argv[++i];
        }
    }

    char cale_cpmbuild[MAX_CALE + 64];
    if ((size_t)snprintf(cale_cpmbuild, sizeof(cale_cpmbuild),
                          "%s/CPMBUILD", src) >= sizeof(cale_cpmbuild)) {
        cpm_err("cale prea lunga"); return 1;
    }
    Manifest m;
    if (citeste_cpmbuild(cale_cpmbuild, &m) < 0) return 1;
    if (arh_override) snprintf(m.arhitectura, sizeof(m.arhitectura), "%s", arh_override);

    char cale_build[MAX_CALE + 64];
    if ((size_t)snprintf(cale_build, sizeof(cale_build),
                          "%s/build.sh", src) >= sizeof(cale_build)) return 1;
    struct stat stb;
    if (stat(cale_build, &stb) < 0) {
        cpm_err("lipseste build.sh in %s", src);
        return 1;
    }

    /* DESTDIR temporar */
    char destdir[MAX_CALE];
    if ((size_t)snprintf(destdir, sizeof(destdir),
                          "/tmp/cpm-build-%d-%s",
                          (int)getpid(), m.nume) >= sizeof(destdir)) return 1;
    sterge_recursiv(destdir);
    if (asigura_dir(destdir) < 0) {
        cpm_err("nu pot crea %s: %s", destdir, strerror(errno));
        return 1;
    }

    cpm_info("Construiesc %s-%s (DESTDIR=%s)",
             m.nume, m.versiune, destdir);

    /* Cale absoluta pentru src — vom face chdir(src), DESTDIR e absolut deja */
    char src_abs[MAX_CALE];
    if (src[0] == '/') {
        snprintf(src_abs, sizeof(src_abs), "%s", src);
    } else {
        char cwd[MAX_CALE];
        if (!getcwd(cwd, sizeof(cwd))) {
            cpm_err("getcwd esuat"); sterge_recursiv(destdir); return 1;
        }
        if ((size_t)snprintf(src_abs, sizeof(src_abs),
                              "%s/%s", cwd, src) >= sizeof(src_abs)) {
            cpm_err("cale src prea lunga"); sterge_recursiv(destdir); return 1;
        }
    }

    pid_t pid = fork();
    if (pid < 0) {
        cpm_err("fork esuat: %s", strerror(errno));
        sterge_recursiv(destdir);
        return 1;
    }
    if (pid == 0) {
        if (chdir(src_abs) < 0) {
            fprintf(stderr, "chdir %s: %s\n", src_abs, strerror(errno));
            _exit(127);
        }
        setenv("DESTDIR", destdir, 1);
        setenv("PKG_NUME", m.nume, 1);
        setenv("PKG_VERSIUNE", m.versiune, 1);
        setenv("PKG_ARH", m.arhitectura, 1);
        execlp("sh", "sh", "./build.sh", (char *)NULL);
        fprintf(stderr, "execlp sh: %s\n", strerror(errno));
        _exit(127);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        cpm_err("build.sh a esuat (status raw=%d)", status);
        sterge_recursiv(destdir);
        return 1;
    }

    void *payload;
    size_t plen;
    if (tar_construieste(destdir, &payload, &plen) < 0) {
        cpm_err("constructia tar-ului a esuat");
        sterge_recursiv(destdir);
        return 1;
    }

    char nume_out[MAX_CALE];
    if (out) {
        snprintf(nume_out, sizeof(nume_out), "%s", out);
    } else {
        if ((size_t)snprintf(nume_out, sizeof(nume_out),
                              "%s-%s-%s.cpm",
                              m.nume, m.versiune,
                              m.arhitectura) >= sizeof(nume_out)) {
            free(payload); sterge_recursiv(destdir); return 1;
        }
    }

    if (cpm_salveaza(nume_out, &m, payload, plen) < 0) {
        free(payload); sterge_recursiv(destdir); return 1;
    }
    free(payload);
    sterge_recursiv(destdir);
    cpm_info("Pachet construit: %s (%zu octeti payload)", nume_out, plen);
    return 0;
}
