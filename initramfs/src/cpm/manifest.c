/* manifest.c — parsare si serializare manifest text key=value */
#define _GNU_SOURCE
#include "cpm.h"

#include <stdio.h>
#include <string.h>

static void trim(char *s) {
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == ' ' || s[n - 1] == '\t' ||
                      s[n - 1] == '\r' || s[n - 1] == '\n')) {
        s[--n] = '\0';
    }
    size_t i = 0;
    while (s[i] == ' ' || s[i] == '\t') i++;
    if (i) memmove(s, s + i, n - i + 1);
}

static void seteaza(Manifest *m, const char *cheie, const char *valoare) {
    if      (strcmp(cheie, "nume") == 0)
        snprintf(m->nume, sizeof(m->nume), "%s", valoare);
    else if (strcmp(cheie, "versiune") == 0)
        snprintf(m->versiune, sizeof(m->versiune), "%s", valoare);
    else if (strcmp(cheie, "arhitectura") == 0)
        snprintf(m->arhitectura, sizeof(m->arhitectura), "%s", valoare);
    else if (strcmp(cheie, "descriere") == 0)
        snprintf(m->descriere, sizeof(m->descriere), "%s", valoare);
    else if (strcmp(cheie, "depinde") == 0)
        snprintf(m->depinde, sizeof(m->depinde), "%s", valoare);
}

int manifest_parseaza(const char *text, size_t len, Manifest *m) {
    memset(m, 0, sizeof(*m));
    char linie[1024];
    size_t i = 0;
    while (i < len) {
        size_t j = 0;
        while (i < len && text[i] != '\n' && j < sizeof(linie) - 1) {
            linie[j++] = text[i++];
        }
        /* daca linia e mai lunga decat buffer-ul, saream pana la newline */
        while (i < len && text[i] != '\n') i++;
        if (i < len && text[i] == '\n') i++;
        linie[j] = '\0';

        trim(linie);
        if (linie[0] == '\0' || linie[0] == '#') continue;

        char *eq = strchr(linie, '=');
        if (!eq) continue;
        *eq = '\0';
        char *cheie = linie;
        char *val = eq + 1;
        trim(cheie);
        trim(val);
        seteaza(m, cheie, val);
    }
    if (m->nume[0] == '\0') return -1;
    if (m->versiune[0] == '\0')
        snprintf(m->versiune, sizeof(m->versiune), "%s", "0");
    if (m->arhitectura[0] == '\0')
        snprintf(m->arhitectura, sizeof(m->arhitectura), "%s", "any");
    return 0;
}

int manifest_serializeaza(const Manifest *m, char *buf, size_t cap) {
    int n = snprintf(buf, cap,
        "nume=%s\n"
        "versiune=%s\n"
        "arhitectura=%s\n"
        "descriere=%s\n"
        "depinde=%s\n",
        m->nume, m->versiune, m->arhitectura, m->descriere, m->depinde);
    if (n < 0 || (size_t)n >= cap) return -1;
    return n;
}

void manifest_afiseaza(const Manifest *m) {
    printf("Nume:        %s\n", m->nume);
    printf("Versiune:    %s\n", m->versiune);
    printf("Arhitectura: %s\n", m->arhitectura);
    printf("Descriere:   %s\n", m->descriere);
    printf("Depinde:     %s\n", m->depinde[0] ? m->depinde : "(nimic)");
    if (m->sha256[0])
        printf("SHA-256:     %s\n", m->sha256);
}
