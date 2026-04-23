# Arhitectura CarpatOS

## Principii de design

1. **Minimalism** — totul start in starea cea mai mica utila; pachetele se
   instaleaza dupa boot, nu se includ implicit.
2. **Totul scris in C** (plus assembly unde-l cere kernelul Linux).
3. **musl libc, static linked** — binarele au zero dependente runtime.
4. **Propriul package manager** (`cpm`) — nu reutilizam apk/rpm/deb.
5. **Output in limba romana** — stringuri, mesaje de eroare, documentatie.
   Identificatorii in cod raman in engleza pentru compatibilitate POSIX.

## Lantul de boot

```
BIOS/UEFI
   │
   ▼
Limine (bootloader)
   │  incarca kernelul + initramfs din ISO
   ▼
Linux kernel (vmlinuz)
   │  extrage initramfs in rootfs (tmpfs)
   │  executa /init cu PID=1
   ▼
/init (binar nostru)
   │  monteaza /proc, /sys, /dev, /tmp, /run
   │  instaleaza handler SIGCHLD (reaper)
   │  atasaza consola
   ▼
fork + exec /bin/msh
   │
   ▼
msh (shell interactiv)
   │  prompt: carpatos#
   │  executa builtins sau binare externe
   ▼
(utilizator)
```

## Layoutul filesystem-ului

In MVP, tot filesystem-ul e un tmpfs populat din initramfs:

```
/                           tmpfs (din initramfs)
├── init                    -> /bin/msh? nu, PID 1 real
├── bin/
│   ├── msh                 shell
│   └── sh -> msh           compat symlink
├── dev/                    devtmpfs (populat de kernel)
├── proc/                   procfs
├── sys/                    sysfs
├── tmp/                    tmpfs (1777)
├── run/                    tmpfs (1777)
├── var/                    pentru /var/cpm/db (ulterior)
└── etc/                    pentru /etc/inittab, /etc/fstab (ulterior)
```

In fazele urmatoare adaugam /usr (pentru pachete), /home, si persistent
storage pe disk (ext4).

## Ratiunea pentru deciziile cheie

### De ce Linux kernel si nu unul propriu?

Un kernel propriu inseamna ~2 ani de munca pentru a ajunge la paritate
cu ce ofera Linux: drivere pentru storage, retea, USB, grafica, filesystem-uri,
securitate, scheduler. Pentru o distributie utilizabila, Linux e o economie
masiva de timp, fara sa compromita obiectivul de "OS scris in C si assembly"
(kernelul Linux chiar este in C + asm).

### De ce musl si nu glibc?

- Binare statice mici (~10 KB vs ~500 KB pentru hello world)
- Licenta MIT (vs LGPL)
- Cod curat, lizibil (~80k LoC vs ~1M pentru glibc)
- Folosit si de Alpine Linux (referinta noastra)

### De ce Limine si nu GRUB?

- Configurare mult mai simpla (config text liniar vs Grub Magic)
- Suporta nativ protocoale multiple: Multiboot1/2, Limine, Linux
- ISO hibrid BIOS+UEFI dintr-o singura comanda
- Dezvoltare activa, codebase mic

### De ce initramfs, nu direct rootfs pe disk?

Pentru MVP, initramfs e suficient — totul traieste in RAM. Cand adaugam
instalatorul (Faza 4), rootul va fi pe disk (ext4), cu /init care decide
daca booteaza live sau din instalare persistenta.

## Package manager `cpm` (Faza 3)

### Format pachet

```
.cpm = antet binar (16 octeti) + manifest JSON + payload tar+zstd

Antet:
  [0-3]   Magic: "CPM\0"
  [4]     Versiune format (1)
  [5-7]   Rezervat (0)
  [8-11]  Lungime manifest (LE)
  [12-15] Lungime payload (LE)
```

### Manifest (JSON)

```json
{
  "nume": "bash",
  "versiune": "5.2.21",
  "arhitectura": "x86_64",
  "descriere": "Bourne Again SHell",
  "depinde_de": ["musl", "ncurses"],
  "conflicte_cu": [],
  "inainte_instalare": "...optional shell script...",
  "dupa_instalare": "..."
}
```

### Baza de date locala

```
/var/cpm/
├── db/
│   ├── installed/
│   │   └── <nume>-<versiune>/
│   │       ├── manifest.json
│   │       └── fisiere.txt
│   └── repo/
│       ├── carpatos-core.index
│       └── pachete/
└── cache/
```

### Comenzi

```
cpm install <pachet...>   — instaleaza pachete + dependente
cpm remove <pachet...>    — dezinstaleaza
cpm list                  — listeaza pachete instalate
cpm list -a               — listeaza toate pachetele disponibile
cpm search <termen>       — cautare in repo
cpm info <pachet>         — detalii pachet
cpm update                — actualizeaza indexul repo
cpm upgrade               — actualizeaza pachetele instalate
```

## Faze viitoare — preview tehnic

### Faza 4: Instalator

TUI simplu in C (probabil peste ncurses sau terminal raw). Pasii:
1. Selectie disk
2. Partitionare (GPT + ESP + root ext4)
3. Formatare
4. Montare + copiere filesystem initial din ISO
5. Instalare Limine pe disk
6. Reboot

### Faza 5: Retea

Kernel Linux ne da stack-ul TCP/IP gratis. Trebuie:
- DHCP client propriu (sau udhcpc static din busybox)
- Configuratie /etc/resolv.conf
- `cpm` cu suport HTTP prin libcurl static sau implementare proprie HTTP/1.1
  (cred ca scriem propriu, ~1500 LoC — e doar client GET, fara TLS initial)

### Faza 6+: Desktop

- Framebuffer direct (kernel DRM/KMS)
- Compositor simplu (event loop, double buffering)
- Toolkit UI propriu (butoane, liste, meniuri, ferestre)
- Shell grafic stil macOS (dock, menu bar, spotlight)

Pentru design-ul vizual vom itera mai intai ca mockup HTML/CSS in chat,
apoi portam design-ul in cod C nativ.
