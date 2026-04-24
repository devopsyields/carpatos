# carpatos.sh — personalizare shell CarpatOS pe Alpine
# Source-uit automat de /etc/profile la fiecare shell de login.

# Setez hostname (apkovl-ul pune /etc/hostname = "carpatos" dar openrc
# hostname service poate rula inainte de overlay extract pe tmpfs; forte
# aici din shell, inofensiv daca e deja corect)
if [ -r /etc/hostname ]; then
    HN="$(cat /etc/hostname)"
    [ -n "$HN" ] && [ "$(hostname)" != "$HN" ] && hostname "$HN" 2>/dev/null
fi

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
