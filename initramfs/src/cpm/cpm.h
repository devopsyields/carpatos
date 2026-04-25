/* cpm.h — declaratii comune pentru package manager-ul CarpatOS
 *
 * Format pachet .cpm:
 *   [antet 16 octeti, little-endian]
 *     uint32_t magic;            // 0x004d5043 = "CPM\0"
 *     uint32_t versiune_format;  // 1
 *     uint32_t manifest_len;
 *     uint32_t payload_len;
 *   [manifest: text key=value]
 *   [payload: arhiva tar USTAR necomprimata]
 */
#ifndef CPM_H
#define CPM_H

#include <stddef.h>
#include <stdint.h>

#define CPM_VERSIUNE        "0.1.0"
#define CPM_MAGIC           0x004d5043u  /* "CPM\0" */
#define CPM_FORMAT_VER      1u

#define MAX_CALE            512
#define MAX_NUME            64
#define MAX_VERSIUNE        32
#define MAX_ARH             16
#define MAX_DESCRIERE       256
#define MAX_SHA256          65       /* 64 hex + null */

/* Path-urile sunt construite la startup din CPM_ROOT (env, optional) +
 * subcai fixe. Permite rularea cpm_host la build cu CPM_ROOT=rootfs/.
 * Cand CPM_ROOT e nesetat, path-urile incep cu /var/cpm. */
extern char DIR_VAR[MAX_CALE];
extern char DIR_DB[MAX_CALE];
extern char DIR_INSTALLED[MAX_CALE];
extern char DIR_CACHE[MAX_CALE];
extern char DIR_REPO[MAX_CALE];
extern char FILE_REPO_INDEX[MAX_CALE];

void cpm_init_paths(void);

/* ===== logging ===== */
void cpm_info(const char *fmt, ...);
void cpm_err(const char *fmt, ...);
void cpm_debug(const char *fmt, ...);

/* ===== util ===== */
int  asigura_dir(const char *cale);            /* mkdir -p */
int  sterge_recursiv(const char *cale);
char *citeste_fisier(const char *cale, size_t *len_out);  /* malloc */
int  scrie_fisier(const char *cale, const void *buf, size_t len);
int  copiaza_fisier(const char *sursa, const char *dest);

/* ===== manifest ===== */
typedef struct {
    char nume[MAX_NUME];
    char versiune[MAX_VERSIUNE];
    char arhitectura[MAX_ARH];
    char descriere[MAX_DESCRIERE];
    char depinde[MAX_CALE];      /* "pkg1,pkg2,..." */
    char fisier[MAX_CALE];       /* folosit doar in repo.index */
    char sha256[MAX_SHA256];     /* hex; in repo.index, hash al .cpm */
} Manifest;

int  manifest_parseaza(const char *text, size_t len, Manifest *m);
int  manifest_serializeaza(const Manifest *m, char *buf, size_t cap);
void manifest_afiseaza(const Manifest *m);

/* ===== sha256 ===== */
void sha256_buf(const void *data, size_t len, char out_hex[65]);
int  sha256_file(const char *cale, char out_hex[65]);

/* ===== tar USTAR ===== */
int  tar_extrage(const void *buf, size_t len, const char *dest_dir,
                 void (*jurnal)(const char *cale, void *ctx), void *ctx);
int  tar_construieste(const char *src_dir, void **buf_out, size_t *len_out);

/* ===== pkg ===== */
int  cpm_incarca(const char *cale, Manifest *m,
                 void **payload_out, size_t *payload_len_out);
int  cpm_salveaza(const char *cale, const Manifest *m,
                  const void *payload, size_t payload_len);

/* ===== db ===== */
int  db_este_instalat(const char *nume);
int  db_salveaza_pachet(const Manifest *m, const char *jurnal_fisiere);
int  db_citeste_manifest(const char *nume, Manifest *m_out);
char *db_citeste_fisiere(const char *nume);    /* malloc */
int  db_sterge_pachet(const char *nume);
int  db_listeaza(char ***nume_out, int *nr_out);
int  db_reverse_deps(const char *nume, char ***deps_out, int *nr_out);

/* ===== repo ===== */
int  repo_gaseste(const char *nume, Manifest *m_out);
int  repo_listeaza(Manifest **lista_out, int *nr_out);
int  repo_actualizeaza_index(void);

/* ===== comenzi ===== */
int  cmd_install(int argc, char **argv);
int  cmd_remove(int argc, char **argv);
int  cmd_local(int argc, char **argv);
int  cmd_list(int argc, char **argv);
int  cmd_search(int argc, char **argv);
int  cmd_info(int argc, char **argv);
int  cmd_update(int argc, char **argv);
int  cmd_build(int argc, char **argv);

#endif /* CPM_H */
