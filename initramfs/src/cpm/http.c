/* http.c — wrapper peste binarul `curl` pentru descarcari HTTP/HTTPS.
 *
 * Cpm ramane static-linked: nu folosim libcurl ci fork()+exec() pe binarul
 * curl deja prezent in sistem (parte din essentials Ubuntu Desktop).
 * Argumentele se transmit explicit ca argv — nu trecem prin shell, deci
 * fara risc de injection in URL.
 */
#define _GNU_SOURCE
#include "cpm.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

int http_descarca(const char *url, const char *cale_dest) {
    pid_t pid = fork();
    if (pid < 0) {
        cpm_err("fork esuat: %s", strerror(errno));
        return -1;
    }
    if (pid == 0) {
        /* copilul: exec curl
         *   -f : exit non-zero la HTTP errors (404, 500, ...)
         *   -s : silent (no progress bar)
         *   -S : afiseaza erori
         *   -L : urmareste redirect-uri (necesar pt GitHub Releases)
         *   --connect-timeout 30 : nu bloca la nesfarsit pe server mort */
        char *argv[] = {
            "curl",
            "-fsSL",
            "--connect-timeout", "30",
            "-o", (char *)cale_dest,
            (char *)url,
            NULL,
        };
        execvp("curl", argv);
        fprintf(stderr, "cpm: nu pot lansa 'curl' (e instalat?): %s\n",
                strerror(errno));
        _exit(127);
    }

    int status;
    if (waitpid(pid, &status, 0) < 0) {
        cpm_err("waitpid: %s", strerror(errno));
        return -1;
    }
    if (!WIFEXITED(status)) {
        cpm_err("curl s-a terminat anormal");
        return -1;
    }
    int ec = WEXITSTATUS(status);
    if (ec != 0) {
        cpm_err("curl a esuat (cod %d) pentru %s", ec, url);
        return -1;
    }
    return 0;
}

/* Citeste URL de baza pentru repo:
 *   1. variabila env CPM_REPO_URL (override pentru dev/teste)
 *   2. fisierul FILE_REPO_URL (/etc/cpm/repo.url)
 * Trimuieste \n / \r / spatii la final. Returneaza 0 daca a gasit ceva. */
int cpm_repo_url(char *out, size_t cap) {
    const char *env = getenv("CPM_REPO_URL");
    if (env && *env) {
        snprintf(out, cap, "%s", env);
        return 0;
    }
    size_t len;
    char *buf = citeste_fisier(FILE_REPO_URL, &len);
    if (!buf) return -1;
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r'
                        || buf[len - 1] == ' ' || buf[len - 1] == '\t')) {
        buf[--len] = '\0';
    }
    if (len == 0) { free(buf); return -1; }
    snprintf(out, cap, "%s", buf);
    free(buf);
    return 0;
}
