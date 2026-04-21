/* ecou — echo minim: scrie argv[1..] separat prin spatiu, terminat cu \n */
#include <unistd.h>
#include <string.h>

static void scrie_tot(int fd, const char *s, unsigned long n) {
    while (n > 0) {
        long r = write(fd, s, n);
        if (r <= 0) return;
        s += r;
        n -= (unsigned long)r;
    }
}

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        scrie_tot(1, argv[i], strlen(argv[i]));
        if (i + 1 < argc) scrie_tot(1, " ", 1);
    }
    scrie_tot(1, "\n", 1);
    return 0;
}
