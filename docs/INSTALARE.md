# Instalarea CarpatOS

> **Notă**: In MVP (Faza 1), CarpatOS ruleaza doar live din ISO.
> Instalarea pe disk persistent vine in Faza 4.

## Rulare live in QEMU (metoda recomandata pentru MVP)

```bash
# Dupa ce ai construit ISO-ul (vezi CONSTRUIRE.md)
make run-iso       # BIOS
# sau
make run-uefi      # UEFI
```

## Rulare pe hardware real (testare)

### De pe USB (BIOS sau UEFI)

```bash
# ATENTIE: inlocuieste sdX cu device-ul USB-ului tau
# VERIFICA cu 'lsblk' inainte sa nu stergi ceva important
sudo dd if=build/carpatos.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Apoi bootezi calculatorul din USB. Vei vedea meniul Limine; selecteaza
"CarpatOS MVP (x86_64)".

### Limitari MVP pe hardware real

In Faza 1, kernelul are doar un set minim de drivere. Functioneaza bine
pe hardware standard din ultimii ~10 ani (Intel/AMD cu SATA, USB HID,
VGA standard). Pentru drivere mai exotice (WiFi, GPU accelerate, NVMe
proprietare) trebuie extinsa configuratia kernelului in Faza 5.

## Instalare persistenta pe disk

**(Faza 4 — nu este inca implementata.)**

Cand va fi gata, procesul va arata cam asa:

```
# Booteaza live din USB/ISO
# La promptul msh:

carpatos# instalare

  === Instalator CarpatOS ===

  Discuri disponibile:
    1) /dev/sda — 500 GB  ATA SSD
    2) /dev/sdb — 2 TB    ATA HDD

  Selecteaza disk [1-2]: 1

  ATENTIE: Tot continutul de pe /dev/sda va fi sters.
  Confirma? [da/nu]: da

  ...partitionare, formatare, copiere, install bootloader...

  Instalarea s-a terminat cu succes. Reboot? [da/nu]:
```

## Suport

Pentru probleme / intrebari:
- Issues pe repo
- cpopescu.dev
