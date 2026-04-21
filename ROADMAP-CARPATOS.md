# Foaie de parcurs — CarpatOS până la finalizare

Document de referință pentru tine (utilizator). Îți arată ce urmează, ce e MVP vs. ce e fază ulterioară, și cum verifici că fiecare etapă e gata.

---

## Fazele A-F (MVP complet bootabil cu `lup`)

Acestea sunt în promptul de onboarding. Target: **CarpatOS bootează în Parallels pe Apple Silicon și rulează `lup install hello` cu succes.** Durată estimată la Claude Code: 1-2 sesiuni de ~1h fiecare.

### Faza A — Recreare `lup` (~30 min)
**Acceptance:** `gcc -Wall -Wextra -Werror -O2 -o lup *.c` trece fără warnings. `./lup version` răspunde. `./lup build <dir>` produce un `.lup` valid verificabil cu `tar -tvf` pe payload.

### Faza B — Multi-arch toolchain (~20 min)
**Acceptance:** `docker build -t carpatos-toolchain toolchain/` construiește imaginea. În container, `aarch64-linux-musl-gcc --version` și `x86_64-linux-musl-gcc --version` răspund ambele. `qemu-system-aarch64 --version` merge.

### Faza C — Pachete demo (~15 min)
**Acceptance:** `./scripts/build-packages.sh aarch64` produce 4 fișiere `.lup` în directorul repo. `lup update` urmat de `lup list -a` le afișează pe toate.

### Faza D — Boot aarch64 în QEMU (~30-60 min, aici apar debuguri reale)
**Acceptance:**
```
$ make ARCH=aarch64 run-uefi
...
carpatos#
```
Plus `lup install hello && hello` să printeze "Salut din CarpatOS!".

**Probleme probabile:**
- Kernel nu bootează — lipsesc CONFIG_PCI_HOST_GENERIC sau CONFIG_VIRTIO_MMIO
- initramfs nu se montează — missing CONFIG_DEVTMPFS_MOUNT
- Serial mut — cmdline trebuie `console=ttyAMA0` pentru ARM, nu ttyS0

### Faza E — Test Parallels (~20 min)
**Acceptance:** VM creat în Parallels pornește de pe ISO, bootează în `carpatos#`.

### Faza F — Documentație finală (~20 min)
**Acceptance:** `README.md` are quick-start x86 + aarch64 + Parallels. `docs/LUPBUILD.md` are specificația completă pentru autori de pachete.

---

## Milestone M1 — MVP utilizabil (după Faza F)

Între Faza F și M1 e un salt mic dar important: **pachete reale instalabile**. Alpine-alike fără ce scrie Alpine în description e doar demo.

### M1.1 — Build system pentru pachete upstream
Adaugă suport în `lup build` pentru pachete care au cod upstream (fetch tarball, verifică hash, patch, configure, make). Model: `APKBUILD`-urile din Alpine. Un fișier `LUPBUILD` extins cu funcții `pregatire()`, `construire()`, `impachetare()` sursate ca shell.

### M1.2 — Primele pachete reale
În ordine (dependențele merg de sus în jos):
1. **musl-utils** — `ldd`, `iconv` minimal
2. **busybox** (sau alternative atomice) — `ls`, `cat`, `mv`, `cp`, `rm`, `mkdir`, `chmod`, `chown`, `mount`, `umount`, `ps`, `kill`, `dmesg`, `uname`, `date`, `sleep`
3. **bash** — shell full-featured, înlocuiește `msh` ca default dacă se vrea
4. **grep, sed, awk** (gawk sau mawk)
5. **tar, gzip, xz**
6. **less, vi** (busybox `vi` inițial, apoi `vim` sau `neovim` ca pachet separat)
7. **file, which, find**

**Acceptance M1:** După `lup install bash coreutils grep sed tar`, poți rula scripturi shell complexe. Sistem devine "Alpine-like utilizabil".

---

## Milestone M2 — Persistență și instalator (săptămâni 4-6)

### M2.1 — Rootfs pe disk
Adaugă la kernel support pentru NVMe + virtio-blk (ok deja în config). `init.c` detectează dacă bootează live sau instalat, montează rootul corect.

### M2.2 — Instalator TUI
Binar nou: `instalare` în C, interacțiune prin shell raw (nu ncurses inițial). Flow:
1. Detectează discuri din `/sys/block/`
2. Prompt "Selectează disk"
3. Partiționare GPT (ESP 512MB + root restul) — folosește `sgdisk` sau implementare proprie
4. `mkfs.ext4` pentru root (musl-static ext4 tools sau scriere proprie a superblock-ului ext4)
5. Montare, copiere rootfs, `limine install` pe ESP
6. Reboot

### M2.3 — fstab, hostname, config
Configurație persistentă în `/etc/`. `init.c` citește `/etc/inittab` propriu.

**Acceptance M2:** Instalezi CarpatOS pe un disk în Parallels, rebootezi fără ISO, pornește de pe disk, salvezi fișiere care persistă între reboot-uri.

---

## Milestone M3 — Rețea + repo remote (săptămâni 7-9)

### M3.1 — Driver virtio-net + DHCP
Kernel config: deja activat. Userspace trebuie un DHCP client. Opțiuni:
- **Busybox udhcpc** — simplu, proven
- **Propriu** — ~500 LoC C pentru DHCP + resolv.conf + ip addr/route (learning project bun)

### M3.2 — HTTP client în `lup`
Implementare proprie HTTP/1.1 GET (~300 LoC), fără TLS inițial. Plain HTTP pentru repo-uri interne. Adăugare `lup_fetch(url, dest)` + modificare `lup update` să citească `/etc/lup/repos.conf`.

### M3.3 — Repo remote
Host un repo static pe un GitHub Pages sau S3:
```
https://carpatos.dev/repo/carpatos-core/aarch64/
  ├── index.txt
  └── *.lup
```

### M3.4 — TLS
Adăugare `mbedtls` static, sau OpenSSL static. Opțiunea ușoară: mbedtls.

**Acceptance M3:** `lup update && lup install bash` funcționează dintr-un sistem nou instalat, fără ISO atașat.

---

## Milestone M4 — Desktop grafic (luni, nu săptămâni)

Aici suntem în teritoriul "proiect de 1-2 ani". Voi schița dar nu pot estima realist.

### M4.1 — Framebuffer + input
Kernel: DRM/KMS (simpledrm inițial). Userspace:
- Librărie proprie pentru access framebuffer (mmap /dev/dri/card0)
- Input events: `/dev/input/event*`, parse kernel input_event struct

### M4.2 — Compositor minimal
Fără Wayland, fără X — compositor direct pe framebuffer. Features:
- Event loop (epoll pe input + pipe client)
- Double buffering
- Client-server protocol propriu (socket Unix domain)

### M4.3 — Toolkit UI
Bibliotecă proprie `libcarpat-ui`:
- Primitive grafice (rect, line, text via stb_truetype)
- Widget-uri: button, label, textfield, list, menu, window
- Layout (flex-like)

### M4.4 — Shell grafic ~ macOS-like
Elemente:
- **Menu bar** sus (ca pe Mac)
- **Dock** jos (cu aplicațiile curente + fixed)
- **Spotlight** (Cmd+Space → launcher)
- **Window chrome** cu traffic lights (close, minimize, maximize)
- **Finder-like** file manager

### M4.5 — Aplicații de bază
- Terminal grafic
- Text editor
- File manager
- System preferences

**Ajutor de la Claude în faza asta:** Artifacts / Visualizer e extrem de util pentru **design-ul vizual**. Iterăm în HTML/CSS interactiv ca să stabilim cum arată (typography, spacing, paleta, iconuri, animații). Apoi portăm design-ul în cod C. Claude Code nu poate scrie compositor-ul, tu-l scrii cu asistența mea în code review + implementare incrementală.

**Acceptance M4:** Bootezi CarpatOS și vezi un desktop cu dock + menu bar + un terminal deschis.

---

## Post-M4 — polish / nice-to-haves (sky's the limit)

- Port-uri de aplicații complexe (firefox, libreoffice) — aici mori, necesită GPU acceleration + fonturi complete + i18n
- Audio stack (ALSA + server audio propriu)
- WiFi stack (wpa_supplicant + drivere)
- Power management (suspend, hibernate)
- Localizare UTF-8 completă cu diacritice românești peste tot
- Store de aplicații cu GUI peste `lup`
- Multi-user (useradd, login screen grafic)
- Containere / namespaces (deja în kernel, trebuie userland)

---

## Strategie pentru finalizare — câteva principii

**1. Cicluri scurte.** După fiecare fază minoră, boot în QEMU și verifică manual. Nu stiva multiple refactorizări fără test între ele.

**2. Git commits frecvente.** Mesaje descriptive în română. Un commit per fază/sub-fază. Tag la milestone-uri (M1, M2, M3, M4).

**3. CI de la început.** Odată ce Dockerfile-ul e stabil, pune un GitHub Actions care face build + boot smoke test în QEMU la fiecare push. 10 minute de setup acum, ore economisite ulterior.

**4. Alegeri reversibile.** Dacă ești blocat pe o decizie (e.g. "compresie gzip vs zstd"), alege cea mai simplă, commit, merge mai departe. Revii dacă dor.

**5. Când te blochezi la un kernel config lipsă** și QEMU nu pornește, nu te lupta — folosește `make ARCH=arm64 virt_defconfig` ca baseline și copiază fragmentele din `buildroot` sau `alpine-aports` pentru ARM64. Reinventezi dacă vrei plăcerea, dar pentru a înainta, copiatul din distro-uri existente e scurtătura.

**6. Pentru desktop (M4), iterează design vizual cu Claude Artifacts înainte să scrii cod.** O săptămână de design în HTML/CSS te scapă de o lună de rescris în C.

---

## Estimare onestă

| Milestone | Persoană cu experiență DevOps, 10-15h/săpt | Full-time |
|---|---|---|
| MVP (Faze A-F) | 1-2 săpt | 3-5 zile |
| M1 — Alpine-like utilizabil | +3-4 săpt | +1-2 săpt |
| M2 — Instalator + persistență | +3-4 săpt | +1-2 săpt |
| M3 — Rețea + remote repo | +3-4 săpt | +1-2 săpt |
| M4 — Desktop grafic | +6-12 luni | +3-6 luni |

Total până la "distribuție Linux minimalistă cu CLI-ul complet, fără desktop": **~3 luni** part-time, **~1 lună** full-time. **Asta e proiect serios, nu weekend hack.**

Dar MVP (Faza F) — sistem care bootează în Parallels cu prompt, `lup` funcțional, 4 pachete demo instalabile — e chestiune de **câteva sesiuni de Claude Code de 1h fiecare**. Ăla trebuie să fie obiectivul tău imediat.

---

## Cum folosești Claude Code concret

1. Descarcă `carpatos-mvp-v0.1.zip` și dezarhivează
2. `cd carpatos && git init && git add . && git commit -m "initial MVP scaffold"`
3. Pornește Claude Code în director
4. Primul mesaj: conținutul din `PROMPT-CLAUDE-CODE.md` (între marcajele BEGIN/END)
5. Lasă Claude Code să facă Faza A — vei vedea cum creează 13 fișiere și rulează gcc
6. Review, commit, continuă cu Faza B
7. La fiecare "Boot failed" / "kernel panic" dă output-ul complet al QEMU; Claude Code îl citește și ajustează kernel config / cmdline

Pentru Milestone-urile M1+ fă sesiuni noi cu context nou — nu încerca să împingi totul într-o singură sesiune lungă (asta ne-a crăpat containerul azi). Fiecare milestone = un ciclu nou de planning + implementare + verificare.

Succes. Când ai boot-ul funcțional pe Parallels, dă-mi screenshot — vreau să-l văd.
