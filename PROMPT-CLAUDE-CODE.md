# Prompt de onboarding — CarpatOS în Claude Code

> Copiază secțiunea de mai jos (de la `---BEGIN---` la `---END---`) ca
> **primul mesaj** într-o sesiune nouă de Claude Code, după ce ai dezarhivat
> `carpatos-mvp-v0.1.zip` și ai `cd` în director.

---BEGIN---

Salut! Continuăm un proiect început într-o sesiune de chat. Context complet mai jos. Răspunde-mi în română. Identificatorii din cod în engleză (standard POSIX), dar toate stringurile către utilizator, comentariile și documentația în română.

## Proiectul: CarpatOS

Distribuție Linux minimalistă stil Alpine, cu package manager propriu numit `lup`, și userland scris de la zero în C. Filozofie: ISO-ul bootează într-un shell minim propriu (`msh`) + `lup` preinstalat; restul (bash, coreutils, grep etc.) se instalează prin `lup install` după boot.

**Arhitecturi target: multi-arch x86_64 + aarch64.** Utilizatorul rulează pe Mac Apple Silicon + Parallels Desktop, deci **aarch64 e prioritatea principală** de testare.

## Stadiul actual

Ce e deja în repo (din `carpatos-mvp-v0.1.zip`):
- Scaffolding complet pentru MVP-ul de boot (Faza 1)
- `kernel/Makefile` — descarcă și compilează Linux 6.12.7 (doar x86_64 în acest ZIP)
- `initramfs/src/init/init.c` — PID 1 propriu (~130 LoC), montează pseudo-fs, SIGCHLD reaper, respawn shell
- `initramfs/src/msh/msh.c` — shell minim (~180 LoC) cu builtins: exit, help, cd, pwd, echo, versiune + exec binare externe
- `initramfs/src/common/mesaje.h` — stringuri românești centralizate
- `toolchain/Dockerfile` — Debian 12 + musl-cross x86_64 + Limine v9.3.2 + QEMU + xorriso (doar x86_64 în acest ZIP)
- `boot/limine.conf` — 2 entry-uri (normal + verbose), doar x86_64
- `scripts/build-iso.sh` + `scripts/run-qemu.sh` — doar x86_64
- `docs/CONSTRUIRE.md`, `docs/ARHITECTURA.md`, `docs/INSTALARE.md`
- `Makefile` top-level + `README.md`

Codul existent a fost verificat sintactic și `msh` a fost testat funcțional (echo, versiune, exit răspund corect).

## Decizii arhitecturale deja luate

- **Kernel**: Linux 6.12 LTS vanilla (nu kernel propriu)
- **libc**: musl, static linked (Alpine-style)
- **Bootloader**: Limine (BIOS+UEFI pe x86_64, UEFI-only pe aarch64)
- **Compresie pachete**: NU pentru MVP — tar USTAR necomprimat. Se va adăuga zstd/gzip ulterior.
- **Output utilizator**: română peste tot. Kernel messages rămân în engleză (nu patchuim kernelul).
- **Identificatori în cod**: engleză (POSIX compat). Stringuri + comentarii + docs: română.
- **Package manager**: `lup`, specificat detaliat mai jos.

## Specificație `lup` (complet proiectat, cod scris și testat funcțional în sesiunea anterioară — trebuie recreat)

### Format fișier `.lup`
```
[antet 16 octeți, little-endian]
  uint32_t magic;            // 0x0050554c = "LUP\0"
  uint32_t versiune_format;  // 1
  uint32_t manifest_len;
  uint32_t payload_len;
[manifest: text key=value, lungime variabilă]
[payload: arhivă tar USTAR necomprimată]
```

### Format manifest (text)
```
nume=hello
versiune=1.0.0
arhitectura=any|x86_64|aarch64
descriere=Descriere scurtă
depinde=pkg1,pkg2,pkg3
```
Comentarii: linii care încep cu `#`. Spații în jurul `=` acceptate.

### Layout filesystem
```
/var/lup/
├── db/
│   ├── installed/
│   │   └── <nume>/
│   │       ├── manifest     (textul manifestului original)
│   │       └── files        (căi absolute instalate, una pe linie)
│   └── repo.index           (text: nume|ver|arh|desc|dep1,dep2|fisier.lup)
├── cache/
└── repos/
    └── carpatos-core/       (fișiere .lup)
```

### Comenzi de implementat
- `lup install <pkg>...` — rezolvă deps recursiv, instalează în ordine topologică, DFS cu detectare cicluri
- `lup remove <pkg>... [--force|-f]` — verifică reverse-deps, refuză fără `--force` dacă alții depind
- `lup local <fisier.lup>...` — instalează direct dintr-un fișier, fără deps automate
- `lup list` — pachete instalate (din db/installed/)
- `lup list -a` — pachete disponibile (din repo.index)
- `lup search <termen>` — caută case-insensitive în nume+descriere (folosește strcasestr)
- `lup info <pkg>` — detalii, caută întâi în instalate, apoi în repo
- `lup update` — reconstruiește repo.index scanând `DIR_REPO/*.lup`
- `lup build <dir> [-o <out>]` — construiește `.lup` din director sursă cu `LUPBUILD` + `build.sh`
- `lup version`, `lup help`

### Structura fișierelor sursă `lup` (13 fișiere)
Organizate în `initramfs/src/lup/`:
- `lup.h` — declarații
- `util.c` — logging (lup_info/err/debug, LUP_DEBUG env var), asigura_dir (mkdir -p), sterge_recursiv, citeste_fisier (malloc), scrie_fisier, copiaza_fisier
- `manifest.c` — parse key=value, serializare, afișare
- `tar.c` — USTAR read (tar_extrage, suport fișiere + dirs + symlinks) + write (tar_construieste, walk director). Ignoră tipuri speciale. MAX nume 100 chars (fără GNU LongLink pentru MVP).
- `pkg.c` — lup_incarca / lup_salveaza (antet + manifest + payload)
- `db.c` — CRUD în /var/lup/db/installed/
- `repo.c` — parse index, repo_gaseste, repo_listeaza, repo_actualizeaza_index (scanare .lup)
- `cmd_install.c` — rezolvare cu DFS + lista "ordine" + "in_curs" pentru detectare cicluri
- `cmd_remove.c` — reverse_deps check
- `cmd_query.c` — list/search/info/update
- `cmd_build.c` — parse LUPBUILD, fork+exec build.sh cu DESTDIR=/tmp/lup-build-PID-nume, tar_construieste, scrie .lup
- `main.c` — dispatch simplu cu strcmp
- `Makefile` — cu `ARCH=x86_64|aarch64`, cross-compile static cu `*-linux-musl-gcc`, flags: `-std=c11 -Wall -Wextra -Werror -O2 -fno-stack-protector -fno-pie`, ldflags: `-static -no-pie -s`

### Atenție specială (lecții din sesiunea anterioară)
- `gcc -Wformat-truncation` va urla la snprintf pe buffere de aceeași dimensiune. Rezolvare: buffere de destinație cu `MAX_CALE + 16` sau `MAX_CALE + 64`, plus verificarea return-ului: `if ((size_t)snprintf(...) >= sizeof(...)) return -1;`
- `tar_construieste` trebuie să termine cu 2 blocuri de 512 octeți zero (end-of-archive).
- Checksum USTAR: sumă de octeți din header cu câmpul chksum tratat ca 8 spații; apoi scrie `"%06o\0 "` în chksum.
- `cmd_install` trebuie să folosească `open_memstream` (POSIX) ca să colecteze jurnalul de fișiere instalate în timpul `tar_extrage`, apoi `db_salveaza_pachet(m, jurnal_buf)`.

## Specificație multi-arch (nu există încă în ZIP, trebuie adăugat)

### Dockerfile (`toolchain/Dockerfile`)
Adaugă și `aarch64-linux-musl-cross` de la musl.cc, plus:
- `qemu-system-arm` pentru rulare ARM64 în QEMU
- `qemu-efi-aarch64` pentru firmware UEFI ARM64 (AAVMF_CODE.fd + AAVMF_VARS.fd)
- Link-uri de conveniență: `/opt/aavmf-code.fd`, `/opt/aavmf-vars.fd`, `/opt/ovmf.fd`
- PATH include ambele toolchain-uri

### Kernel Makefile (`kernel/Makefile`)
Parametrizare `ARCH=x86_64|aarch64`. Pentru aarch64:
- `K_ARCH := arm64`, `CROSS := aarch64-linux-musl-`
- `K_ARTIFACT := arch/arm64/boot/Image.gz`
- Config: în loc de SERIAL_8250 → SERIAL_AMBA_PL011 + PL011_CONSOLE; în loc de FB_VESA → FB_SIMPLE; adaugă PCI_HOST_GENERIC
- Build dir separat per arh: `build/$(ARCH)/`

### Initramfs Makefile (`initramfs/Makefile`)
Parametrizare `ARCH`. Construiește init+msh+lup pentru arhitectura respectivă. Output: `build/$(ARCH)/initramfs.cpio.gz`.

### Build ISO (`scripts/build-iso.sh`)
Acceptă `ARCH=x86_64|aarch64` ca prim argument. Produce `build/carpatos-$(ARCH).iso`.
- Pentru aarch64: doar UEFI, `/EFI/BOOT/BOOTAA64.EFI`, nu face `limine bios-install`
- Pentru x86_64: BIOS + UEFI hibrid (ca în ZIP-ul existent)

### Run QEMU (`scripts/run-qemu.sh`)
Moduri: `direct-x86`, `iso-x86`, `uefi-x86`, `direct-arm`, `iso-arm`, `uefi-arm`. Pentru aarch64:
- `qemu-system-aarch64 -machine virt -cpu cortex-a72 -m 512M -bios /opt/aavmf-code.fd`
- Pentru boot direct: `-kernel ... -initrd ... -append "..."`

### Limine config (`boot/limine.conf`)
Aceeași configurație text merge pentru ambele arhitecturi (Limine alege automat artefactele corespunzătoare).

## Pachete demo (de creat în `packages/`)
4 pachete minimale pentru validare end-to-end `lup`:
- `hello` — shell script care afișează "Salut din CarpatOS!"
- `adevarat` — exit 0 (echivalent `true`)
- `fals` — exit 1 (echivalent `false`)
- `ecou` — minimal `echo` în C compilat static cu musl

Fiecare are `LUPBUILD` + `build.sh`. Există deja un script conceptual `scripts/build-packages.sh` care iterează prin ele și le pune în `initramfs/rootfs/var/lup/repos/carpatos-core/`.

## Sarcina ta (în ordine, fiecare completă înainte de următoarea)

**Faza A — Recreare `lup` (validat funcțional în sesiunea anterioară):**
1. Creează toate cele 13 fișiere în `initramfs/src/lup/` conform specificației de mai sus
2. Compilează cu gcc de sistem (sanity check): `gcc -Wall -Wextra -Werror -O2 -o lup_test *.c`
3. Fă un smoke test: `lup version`, `lup help`, `lup build` pe un director minimal, `lup list` cu /var/lup gol

**Faza B — Multi-arch:**
4. Refactorizează `toolchain/Dockerfile`, `kernel/Makefile`, `initramfs/Makefile`, `scripts/build-iso.sh`, `scripts/run-qemu.sh`, top-level `Makefile` pentru parametrizare `ARCH`
5. Verifică că `docker build -t carpatos-toolchain toolchain/` trece

**Faza C — Pachete demo:**
6. Creează cele 4 pachete în `packages/`
7. Creează `scripts/build-packages.sh` care le construiește pentru ambele arhitecturi
8. Integrează: `initramfs/Makefile` trebuie să copieze pachetele în `rootfs/var/lup/repos/carpatos-core/` înainte de cpio

**Faza D — Boot efectiv pe aarch64 în QEMU:**
9. `make ARCH=aarch64` — trebuie să producă ISO
10. `make ARCH=aarch64 run-uefi` — trebuie să booteze în QEMU și să ajungă la promptul `carpatos#`
11. Rulează `lup list -a` (trebuie să arate cele 4 pachete), `lup install hello`, `hello` (trebuie să printeze "Salut din CarpatOS!")
12. Fix orice apare pe parcurs (drivere lipsă în kernel config, permisiuni, etc.)

**Faza E — Parallels:**
13. Generează ISO aarch64 final și testează-l în Parallels Desktop pe Apple Silicon. Vezi `docs/PARALLELS.md` (de creat) pentru pași: creare VM "Other Linux (ARM)", atașare ISO, 1GB RAM, 2 vCPU, disk opțional.
14. Documentează orice particularitate Parallels în `docs/PARALLELS.md`

**Faza F — Documentație finală:**
15. Update `README.md` cu quick start pentru ambele arhitecturi și referință către PARALLELS.md
16. Update `docs/CONSTRUIRE.md` cu secțiunea multi-arch
17. Adaugă `docs/LUPBUILD.md` — specificația formatului pentru autori de pachete

## Convenții cod

- Stringuri în cod: `"Instalez %s-%s", nume, ver` (română, fără diacritice în mesajele de boot pentru siguranță — consolefont n-o să fie încărcat; după MVP trecem pe UTF-8 complet)
- Identificatori: engleză (`install`, `remove`, `parse_manifest`)
- Nume funcții Claude-side (ale lui `lup`, vizibile utilizatorului final prin help): un mix natural, de ex. `manifest_parseaza`, `cmd_install`, `repo_gaseste` — acceptabil, așa e scris deja
- Erori pe stderr, output normal pe stdout
- `-Werror` activ; orice warning trebuie reparat, nu suprimat

## Ce să NU faci

- Nu adăuga dependențe C externe (nu pulling zlib, nu json-c, etc.) — vrem binarele static-linked curate
- Nu rescrie `init.c` sau `msh.c` decât dacă găsești un bug real
- Nu schimba formatul `.lup` fără să discutăm; e stabilit
- Nu folosi GNU extensions la tar (LongLink) — menținem nume ≤ 100 chars pentru MVP
- Nu adăuga compresie la `.lup` în MVP — tar necomprimat e suficient

## Întrebări de clarificare

Dacă ceva e neclar, întreabă înainte să scrii cod. Mai ales:
- Dacă kernelul aarch64 nu bootează (probabil lipsește un driver în config — vezi-l în output-ul QEMU cu `earlyprintk=pl011,0x9000000`)
- Dacă Parallels refuză ISO-ul (poate trebuie rebuild cu `-V CARPATOS` mai specific sau partition table diferit)

Când ești gata, începe cu Faza A. După fiecare fază, fă un commit git cu mesaj descriptiv.

---END---
