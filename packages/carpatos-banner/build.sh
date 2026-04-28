#!/bin/sh
# build.sh — instaleaza banner-uri pentru /etc/issue, issue.net, motd
set -eu

install -d "$DESTDIR/etc"

# /etc/motd — afisat dupa login. Foloseste box-drawing (UTF-8) +
# stilizare cu munti pentru tema Carpati. Functioneaza pe orice
# console UTF-8 (default in Ubuntu/CarpatOS).
cat > "$DESTDIR/etc/motd" <<'EOF'

       /\           /\           /\           /\
      /  \         /  \         /  \         /  \
     / /\ \       / /\ \       / /\ \       / /\ \
    / /  \ \     / /  \ \     / /  \ \     / /  \ \
   /_/    \_\   /_/    \_\   /_/    \_\   /_/    \_\

      ╔═══════════════════════════════════╗
      ║         CarpatOS Desktop          ║
      ║              v1.0                 ║
      ╚═══════════════════════════════════╝

   Bun venit. Proiect personal Catalin Popescu.
   https://github.com/devopsyields/carpatos

EOF

# /etc/issue — afisat inainte de prompt-ul de login pe TTY.
# Escape-uri getty: \n=hostname, \l=tty
cat > "$DESTDIR/etc/issue" <<'EOF'

      CarpatOS Desktop 1.0
      \n  (\l)

EOF

# /etc/issue.net — login retea (telnet/ssh banner). Fara escape-uri.
cat > "$DESTDIR/etc/issue.net" <<'EOF'
CarpatOS Desktop 1.0
EOF

chmod 0644 "$DESTDIR/etc/motd" "$DESTDIR/etc/issue" "$DESTDIR/etc/issue.net"

# /etc/legal — Ubuntu pune un text "The programs included with the Ubuntu
# system are free software; ...". Suprascriem cu un text scurt CarpatOS.
cat > "$DESTDIR/etc/legal" <<'EOF'
CarpatOS Desktop — distributie Linux peste Ubuntu LTS.
Toate pachetele incluse au licente proprii — vezi /usr/share/doc/<pachet>.
EOF
chmod 0644 "$DESTDIR/etc/legal"

# /etc/update-motd.d — script-uri executabile rulate la SSH/TTY login.
# Ubuntu pune aici "Welcome to Ubuntu", "documentation: https://help.ubuntu.com",
# "esm-apps", "release-upgrade", etc. Le suprascriem cu fisiere goale
# (fara executable bit) ca sa nu mai ruleze.
install -d "$DESTDIR/etc/update-motd.d"
for f in 00-header 10-help-text 50-motd-news 90-updates-available \
         91-contract-ubuntu-support 91-release-upgrade 95-hwe-eol \
         98-fsck-at-reboot 98-reboot-required; do
    install -m 0644 /dev/null "$DESTDIR/etc/update-motd.d/$f"
done

# Adaug propriul nostru header carpatos (executat la login interactiv)
cat > "$DESTDIR/etc/update-motd.d/01-carpatos" <<'EOF'
#!/bin/sh
# 01-carpatos — header dinamic la login.
echo
echo "  CarpatOS Desktop 1.0  ($(uname -m))"
echo "  https://github.com/devopsyields/carpatos"
echo
EOF
chmod 0755 "$DESTDIR/etc/update-motd.d/01-carpatos"

# Shell prompt CarpatOS — suprascrie /etc/bash.bashrc COMPLET, in plus
# fata de profile.d (care NU e sourceat de gnome-terminal — non-login).
# Continut: minimum-viable + PS1 carpatos verde/auriu/albastru.
install -d "$DESTDIR/etc"
cat > "$DESTDIR/etc/bash.bashrc" <<'EOF'
# /etc/bash.bashrc — CarpatOS Desktop default bash interactive setup.
# Suprascrie default-ul Ubuntu pentru a aplica PS1 specific carpatos.

# Daca shell non-interactiv, exit
[ -z "$PS1" ] && return

# Pastrare history
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend
shopt -s checkwinsize

# Lesspipe (pentru less pe arhive etc., daca e instalat)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# PS1 CarpatOS: user verde + @host auriu + :path albastru + $ default
PS1='\[\033[01;32m\]\u\[\033[00m\]@\[\033[01;33m\]\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Aliases standard
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Bash completion (daca e instalat)
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# Sourceaza /etc/bash.bashrc.d/* daca exista
if [ -d /etc/bash.bashrc.d ]; then
    for f in /etc/bash.bashrc.d/*.sh; do
        [ -r "$f" ] && . "$f"
    done
    unset f
fi
EOF
chmod 0644 "$DESTDIR/etc/bash.bashrc"

# /etc/skel/.bashrc — pentru utilizatorii noi (live user "ubuntu" e
# creat din /etc/skel la session start). Suprascriem cu varianta
# minimala care nu reseteaza PS1-ul nostru din bash.bashrc.
install -d "$DESTDIR/etc/skel"
cat > "$DESTDIR/etc/skel/.bashrc" <<'EOF'
# /etc/skel/.bashrc — CarpatOS user default. PS1-ul e setat in
# /etc/bash.bashrc, NU il resetam aici (cum face Ubuntu's default).

# Shell non-interactiv -> exit
[ -z "$PS1" ] && return

# History merge cu setarile din /etc/bash.bashrc
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend
shopt -s checkwinsize

# Aliases personale (simplu set, fara override la PS1)
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
EOF
chmod 0644 "$DESTDIR/etc/skel/.bashrc"
