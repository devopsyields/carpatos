/* init.c — Procesul PID 1 pentru CarpatOS
 *
 * Responsabilitati in MVP:
 *   1. Montare filesystem-uri virtuale (proc, sys, dev, tmp, run)
 *   2. Redirectare stdin/stdout/stderr catre consola
 *   3. Recoltare procese zombie (reaping)
 *   4. Spawn shell (msh) si respawn automat daca iese
 *
 * Compilat static cu musl (fara dependente runtime).
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../common/mesaje.h"

/* Scriere directa pe fd, fara buffering — evitam stdio la boot */
static void scrie(int fd, const char *s) {
    size_t len = strlen(s);
    while (len > 0) {
        ssize_t n = write(fd, s, len);
        if (n <= 0) return;
        s += n;
        len -= (size_t)n;
    }
}

static void mesaj(const char *s) { scrie(1, s); }
static void eroare(const char *s) { scrie(2, s); }

/* Montare cu mkdir + mount, tolerant la erori (pseudo-fs-urile pot
 * fi deja montate de initramfs, sau directorul deja exista) */
static void monteaza(const char *sursa, const char *tinta,
                      const char *tip, unsigned long flags) {
    mkdir(tinta, 0755);
    if (mount(sursa, tinta, tip, flags, NULL) < 0 && errno != EBUSY) {
        eroare("[init] avertisment: nu pot monta ");
        eroare(tinta);
        eroare("\n");
    }
}

static void afiseaza_banner(void) {
    mesaj("\n");
    mesaj("   ____                         _    ___  ____\n");
    mesaj("  / ___|__ _ _ __ _ __   __ _  | |_ / _ \\/ ___|\n");
    mesaj(" | |   / _` | '__| '_ \\ / _` | | __| | | \\___ \\\n");
    mesaj(" | |__| (_| | |  | |_) | (_| | | |_| |_| |___) |\n");
    mesaj("  \\____\\__,_|_|  | .__/ \\__,_|  \\__|\\___/|____/\n");
    mesaj("                 |_|\n");
    mesaj("\n  " CARPATOS_NUME " " CARPATOS_VERSIUNE
          " — versiune bootabila minima\n\n");
}

/* Handler SIGCHLD: recolteaza toate procesele zombie disponibile */
static void reaper(int semnal) {
    (void)semnal;
    while (waitpid(-1, NULL, WNOHANG) > 0) {
        /* bucla goala — scopul e doar sa consume zombies */
    }
}

/* Scriu un mesaj de debug in kernel log ring buffer (apare in dmesg /
 * pe console) — util cand stdout-ul init-ului nu e inca conectat. */
static void kmsg(const char *s) {
    int fd = open("/dev/kmsg", O_WRONLY);
    if (fd < 0) return;
    size_t len = strlen(s);
    write(fd, s, len);
    close(fd);
}

/* Astept ca framebuffer + VT sa fie gata (virtio-gpu pe Apple Vz, simpleFB
 * pe QEMU/Parallels). Pragul e /sys/class/drm/card0 pentru DRM sau
 * /dev/fb0 pentru fbdev clasic. Timeout 2 secunde ca sa nu blocam daca
 * hardware-ul nu are framebuffer deloc (ex: QEMU -nographic). */
static int asteapta_framebuffer(void) {
    for (int i = 0; i < 200; i++) {  /* 200 * 10ms = 2s */
        if (access("/sys/class/drm/card0", F_OK) == 0) return 1;
        if (access("/dev/fb0", F_OK) == 0) return 1;
        usleep(10000);
    }
    return 0;
}

/* Redirectez stdin/stdout/stderr catre prima consola utilizabila.
 * Prioritate: /dev/tty1 daca framebuffer-ul e gata (display + tastatura
 * in fereastra VM pe Apple Vz / Parallels / bare metal); fallback la
 * /dev/console, hvc0, ttyAMA0 pentru serial-only boot (QEMU -nographic). */
static void atasare_consola(void) {
    const char *candidati[5];
    int n = 0;
    if (asteapta_framebuffer()) {
        kmsg("[init] framebuffer gata, prefer /dev/tty1\n");
        candidati[n++] = "/dev/tty1";
    } else {
        kmsg("[init] fara framebuffer, folosesc serial/virtio-console\n");
    }
    candidati[n++] = "/dev/console";
    candidati[n++] = "/dev/hvc0";
    candidati[n++] = "/dev/ttyAMA0";
    candidati[n] = NULL;

    int fd = -1;
    for (int i = 0; candidati[i]; i++) {
        fd = open(candidati[i], O_RDWR);
        if (fd >= 0) {
            kmsg("[init] consola: ");
            kmsg(candidati[i]);
            kmsg("\n");
            break;
        }
    }
    if (fd < 0) {
        kmsg("[init] EROARE: nicio consola nu a putut fi deschisa\n");
        return;
    }
    /* Sesiune noua + controlling terminal pentru tty1 — altfel Ctrl+C nu
     * ajunge la msh si citirile blocheaza fara input handling corect.
     * setsid() esueaza silent daca suntem deja leader (PID 1 e). */
    setsid();
    ioctl(fd, TIOCSCTTY, 0);
    dup2(fd, 0);
    dup2(fd, 1);
    dup2(fd, 2);
    if (fd > 2) close(fd);
}

int main(void) {
    /* 0. Semnal early in kernel log ca init ruleaza (inainte de mounts,
     *    /dev/kmsg e accesibil pentru ca devtmpfs e auto-mounted) */
    kmsg("[init] main() a pornit\n");

    /* 1. Montez pseudo-filesystem-urile esentiale */
    monteaza("proc",     "/proc", "proc",     0);
    monteaza("sysfs",    "/sys",  "sysfs",    0);
    monteaza("devtmpfs", "/dev",  "devtmpfs", 0);
    monteaza("tmpfs",    "/tmp",  "tmpfs",    0);
    monteaza("tmpfs",    "/run",  "tmpfs",    0);

    /* 2. Atasez consola */
    kmsg("[init] atasare consola\n");
    atasare_consola();
    kmsg("[init] consola atasata, incerc banner\n");

    /* 3. Instalez handler pentru SIGCHLD */
    struct sigaction sa = {0};
    sa.sa_handler = reaper;
    sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;
    sigaction(SIGCHLD, &sa, NULL);

    /* 4. Banner de boot */
    afiseaza_banner();
    mesaj(MSG_BOOT_MOUNT_OK);
    mesaj(MSG_BOOT_TERMINAT);
    mesaj(MSG_BOOT_PORNESC_MSH);
    mesaj("\n");

    /* 5. Bucla respawn pentru shell */
    for (;;) {
        pid_t pid = fork();
        if (pid < 0) {
            eroare("[init] fork() a esuat, astept 5 secunde\n");
            sleep(5);
            continue;
        }
        if (pid == 0) {
            /* Copil: exec msh */
            execl("/bin/msh", "msh", (char *)NULL);
            eroare(MSG_BOOT_MSH_EROARE);
            _exit(127);
        }
        /* Parinte: astept shell-ul sa iasa */
        int status;
        waitpid(pid, &status, 0);
        mesaj(MSG_BOOT_MSH_IESIT);
        sleep(1);
    }

    /* niciodata atins */
    return 0;
}
