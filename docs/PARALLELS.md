# Rularea CarpatOS in Parallels Desktop (Apple Silicon)

Acest document descrie cum sa bootezi ISO-ul CarpatOS intr-o masina
virtuala Parallels Desktop pe un Mac cu Apple Silicon (M1/M2/M3/M4).

Pe Apple Silicon, Parallels ruleaza doar masini virtuale **aarch64** —
deci ai nevoie de `carpatos-aarch64.iso`.

## 1. Construieste ISO-ul aarch64

In container-ul toolchain:

```bash
make ARCH=aarch64 iso
```

Rezultatul: `build/aarch64/carpatos-aarch64.iso`.

Daca rulezi pe un Mac gazduind containerul, trebuie sa copiezi ISO-ul
din container pe Mac (montajul `-v "$(pwd):/src"` face asta automat —
ISO-ul e direct in `./build/aarch64/`).

## 2. Creeaza masina in Parallels

1. **Parallels Desktop** → `File` → `New…`
2. Alege **Install Windows, Linux or macOS from an image file**.
3. Apasa **Continue** si fa click pe **Choose Manually** daca Parallels
   nu recunoaste ISO-ul (CarpatOS e prea minimalist ca sa fie detectat).
4. Selecteaza `build/aarch64/carpatos-aarch64.iso`.
5. La pasul **Select Operating System**, alege **Other Linux** (orice
   subvariant, nu conteaza pentru MVP).
6. Setari recomandate:
   - **RAM**: 1 GB (256 MB ar fi suficient dar Parallels nu merge mai jos)
   - **CPU**: 2 vCPU-uri
   - **Disk**: 1 GB (inutil pentru MVP, dar cerut de Parallels)
   - **Boot order**: CD/DVD → Hard Disk
   - **Firmware**: UEFI (Parallels ARM ruleaza intotdeauna UEFI)
7. Bifeaza **Customize settings before installation** si apoi in **Hardware**:
   - **Boot order** → mai intai `CD/DVD` (cu ISO-ul montat)
   - Optional: dezactiveaza reteaua (nu e folosita in MVP)

## 3. Porneste masina

La pornire ar trebui sa vezi:

1. Bannerul Limine (3 secunde timeout)
2. Intrarea selectata implicit: `CarpatOS MVP`
3. Kernel Linux pornind — vei vedea log-ul pe ecran
4. ASCII banner-ul CarpatOS
5. `msh` prompt: `carpatos#`

Poti comuta pe intrarea `CarpatOS MVP (verbose)` din meniul Limine
daca vrei log-uri detaliate de boot.

## 4. Verificare

In shell-ul `msh`:

```
carpatos# versiune
CarpatOS 0.1.0
carpatos# cpm list -a
...
carpatos# cpm install hello
Instalez hello-1.0 (din ...)
carpatos# hello
Salut din CarpatOS!
```

## Note Apple Silicon

- Parallels foloseste virtualizarea nativa Apple Hypervisor — kernel
  ruleaza la viteza nativa pe M1+ pe aarch64.
- Consola graficala (framebuffer `FB_SIMPLE`) e activata in config, deci
  ar trebui sa vezi output pe display-ul masinii virtuale. Daca ramane
  negru, deschide **View → Enter Full Screen** si apoi apasa o tasta.
- Tastatura se comporta normal, dar nu e definita layout — este US prin
  implicit, ce poate fi enervant pentru `-`, `_`, `=`.

## Probleme cunoscute

### Parallels refuza sa boot-eze: "No bootable device"

Verifica:
1. CD/DVD e inainte de Hard Disk in `Boot Order`.
2. ISO-ul chiar e `carpatos-aarch64.iso` (nu x86_64). Ruleaza pe Mac:
   ```bash
   file build/aarch64/carpatos-aarch64.iso
   ```
   Ar trebui sa zica "ISO 9660" si sa contina `EFI/BOOT/BOOTAA64.EFI`.

### Kernel panic "Unable to mount rootfs"

Cmdline-ul trebuie sa aiba `rdinit=/init`. Daca ai modificat
`boot/limine.conf`, verifica.

### Ecran negru dar serial output OK in QEMU

Parallels foloseste framebuffer, nu serial, asa ca ai nevoie de
`CONFIG_FB_SIMPLE=y` + `CONFIG_FRAMEBUFFER_CONSOLE=y`. Acestea sunt
deja in `kernel/Makefile` pentru aarch64.

## Alternative

- **UTM** (gratis, open-source): acelasi ISO functioneaza in UTM in mod
  Virtualize (hypervisor nativ) sau Emulate (QEMU-based).
- **QEMU direct** (fara container): `make ARCH=aarch64 run-iso` daca ai
  `qemu-system-aarch64` si AAVMF instalate.

## Oprire curata

CarpatOS MVP nu are `shutdown` inca. Din Parallels:
**Actions** → **Stop** → **Force Stop**. Nu exista nimic persistent
pe disk, deci nu pierzi nimic.
