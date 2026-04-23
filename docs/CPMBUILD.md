# Formatul `cpm` si scrierea de pachete

`cpm` e package managerul CarpatOS. Un pachet `.cpm` e un singur fisier
binar care contine metadatele + arhiva tar cu fisierele de instalat.
Acest document descrie formatul binar si cum se scrie un pachet nou.

## Formatul binar `.cpm`

```
+---------------------------+
| Header (16 octeti LE)     |
|  uint32 magic             |   0x004d5043  (ASCII "CPM\0")
|  uint32 versiune_format   |   1
|  uint32 manifest_len      |   nr octeti manifest text
|  uint32 payload_len       |   nr octeti payload tar
+---------------------------+
| Manifest (text, UTF-8)    |   key=value, un camp pe linie
+---------------------------+
| Payload (USTAR tar)       |   arhiva cu fisierele pachetului
+---------------------------+
```

Toti intregii sunt **little-endian**. Magic-ul permite identificare rapida:
`file` ar vedea primii 4 octeti ca `LUP\0`.

## Manifestul

Format text, cu comentarii `#` si linii goale permise. Chei recunoscute:

| Cheie | Tip | Obligatoriu | Descriere |
|---|---|---|---|
| `nume` | sir | da | Numele pachetului (a-z, 0-9, `-`) |
| `versiune` | sir | implicit `0` | Versiunea (liber) |
| `arhitectura` | sir | implicit `any` | `x86_64`, `aarch64` sau `any` |
| `descriere` | sir | nu | Descriere scurta |
| `depinde` | lista | nu | Alte pachete, separate prin spatiu |

Exemplu:

```
nume=hello
versiune=1.0
arhitectura=any
descriere=Salutari din CarpatOS
depinde=
```

## Fisierul `CPMBUILD`

Fiecare pachet traieste intr-un director ce contine:

- `CPMBUILD` — manifestul (acelasi format ca mai sus)
- `build.sh` — script shell ce produce fisierele in `$DESTDIR`

## Scriptul `build.sh`

`cpm build` face `chdir` in directorul pachetului si apoi executa
`sh ./build.sh` cu urmatoarele variabile de mediu setate:

| Variabila | Continut |
|---|---|
| `DESTDIR` | Director temporar unde trebuie instalate fisierele |
| `PKG_NUME` | `nume` din CPMBUILD |
| `PKG_VERSIUNE` | `versiune` din CPMBUILD |
| `PKG_ARH` | `arhitectura` efectiva (inclusiv override `--arch`) |

Toate fisierele scrise in `$DESTDIR` vor fi arhivate si intra in pachet
cu calea relativa la `$DESTDIR` (ex: `$DESTDIR/bin/hello` → `/bin/hello`).

### Exemplu — script shell (`hello`)

```sh
#!/bin/sh
set -eu
install -d "$DESTDIR/bin"
cat > "$DESTDIR/bin/hello" <<'EOF'
#!/bin/msh
echo Salut din CarpatOS!
EOF
chmod 0755 "$DESTDIR/bin/hello"
```

### Exemplu — binar C nativ (`ecou`)

```sh
#!/bin/sh
set -eu
: "${PKG_ARH:?}"
CC="${CC:-${PKG_ARH}-linux-musl-gcc}"
install -d "$DESTDIR/bin"
$CC -O2 -Wall -static -s -o "$DESTDIR/bin/ecou" ecou.c
```

## Comenzi `cpm build`

```
cpm build <dir-pachet> [-o iesire.cpm] [--arch <arh>]
```

- `-o` — nume fisier de iesire (implicit `<nume>-<ver>-<arh>.cpm`)
- `--arch` — suprascrie `arhitectura` din CPMBUILD (util pentru pachetele
  native ce vor sa suporte mai multe arhitecturi dintr-o singura sursa)

## Operatii cu pachete

```
cpm install <nume>           # din repo (cauta in /var/cpm/repos/*/index)
cpm local   <fisier.cpm>     # dintr-un fisier local
cpm remove  <nume> [--force] # sterge (blocheaza daca alte pachete depind)
cpm list    [-a]             # listeaza instalate (-a include repo)
cpm search  <cuvant>         # cauta in nume + descriere
cpm info    <nume>           # arata manifestul
cpm update                   # reconstruieste indexul din *.cpm din repo
```

Dependentele sunt rezolvate recursiv (DFS) cu detectare de cicluri.

## Baza de date de pachete instalate

`cpm` stocheaza in `/var/cpm/db/installed/<nume>/`:

- `manifest` — copia manifestului pachetului
- `files` — lista fisierelor instalate, relativa la `/` (pentru remove)

## Indexul de repo

Un repo este un director in `/var/cpm/repos/<nume-repo>/` care contine:

- Fisierele `.cpm` in sine
- Un fisier `index` — text, un pachet per linie, cu formatul:
  ```
  nume|versiune|arhitectura|descriere|depinde|fisier.cpm
  ```
  Reconstruit prin `cpm update`.

## Limitari curente (MVP)

- Fara semnaturi criptografice. Pachetele sunt inchizand `trust-on-first-use`.
- Fara rezolutie de conflicte la fisiere — ultimul castiga.
- Fara hook-uri `post-install` / `pre-remove`.
- Fara versionare semver — `depinde=foo` = orice versiune de `foo`.

Toate acestea sunt candidate pentru Faza 3+ (repo-uri HTTP, semnaturi).
