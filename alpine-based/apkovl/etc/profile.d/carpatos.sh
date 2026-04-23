# carpatos.sh — personalizare shell CarpatOS pe Alpine
# Source-uit automat de /etc/profile la fiecare shell de login.

# Afiseaza banner CarpatOS (motd nu e afisat automat fara /bin/login)
if [ -r /etc/motd ] && [ -z "$CARPATOS_MOTD_SHOWN" ]; then
    cat /etc/motd
    export CARPATOS_MOTD_SHOWN=1
fi

export PS1='carpatos# '
export PATH="/usr/local/bin:$PATH"

alias ll='ls -la'
alias l='ls'
alias c='cpm'
