/* mesaje.h — Stringuri centralizate pentru CarpatOS
 *
 * Toate mesajele catre utilizator sunt in romana.
 * Pentru compatibilitate cu terminale care nu suporta UTF-8 la boot,
 * nu folosim diacritice in mesajele de boot timpuriu. Vom trece la
 * diacritice dupa ce avem localedef si consolefont incarcat corect.
 */
#ifndef CARPATOS_MESAJE_H
#define CARPATOS_MESAJE_H

#define CARPATOS_VERSIUNE "0.1.0-mvp"
#define CARPATOS_NUME     "CarpatOS"

#define MSG_BOOT_MOUNT_OK    "[init] sistemul de fisiere virtuale montat\n"
#define MSG_BOOT_TERMINAT    "[init] faza 1: boot MVP terminat cu succes\n"
#define MSG_BOOT_PORNESC_MSH "[init] pornesc shell-ul msh...\n"
#define MSG_BOOT_MSH_IESIT   "[init] msh a iesit, repornesc...\n"
#define MSG_BOOT_MSH_EROARE  "[init] EROARE: nu pot porni /bin/msh\n"

#define MSH_BANNER "msh — shell minim CarpatOS\n"
#define MSH_PROMPT "carpatos# "
#define MSH_BYE    "La revedere.\n"

#endif /* CARPATOS_MESAJE_H */
