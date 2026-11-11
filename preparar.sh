#!/bin/bash
# preparar.sh - Prepara una plantilla Ubuntu (Server o Desktop) per a IsardVDI
#
# Ús: sudo bash preparar.sh [--sense-ssh] [--key "ssh-ed25519 AAAA..."] [--no-corrector] [--user isard]
#
# Fa:
#  1. Instal·la auditd i openssh-server (si no es passa --sense-ssh)
#  2. Inici de sessió automàtic (GDM, LightDM o consola tty1)
#  3. Sudo sense contrasenya per a l'usuari
#  4. Desktop: treu bloqueig i apagat de pantalla
#     Server: treu l'espera de xarxa de 2 minuts a l'arrencada
#  5. Crea l'usuari de reserva "corrector" (grup sudo, amb contrasenya)
#  6. Configura l'SSH (clau opcional)
#  7. Registre de comandes amb auditd
#  8. Data i hora a l'historial de bash
#  9. Journal persistent

set -e

USUARI="isard"
AMB_SSH=1
CLAU=""
AMB_CORRECTOR=1

while [ $# -gt 0 ]; do
    case "$1" in
        --sense-ssh)    AMB_SSH=0 ;;
        --key)          CLAU="$2"; shift ;;
        --no-corrector) AMB_CORRECTOR=0 ;;
        --user)         USUARI="$2"; shift ;;
        *) echo "Opció desconeguda: $1"; exit 1 ;;
    esac
    shift
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Executa-ho amb sudo: sudo bash $0"
    exit 1
fi

if ! id "$USUARI" >/dev/null 2>&1; then
    echo "L'usuari $USUARI no existeix"
    exit 1
fi

# Detectar tipus de màquina
if [ -f /etc/gdm3/custom.conf ]; then
    TIPUS="gdm"
elif [ -d /etc/lightdm ]; then
    TIPUS="lightdm"
else
    TIPUS="server"
fi
echo ">> Màquina detectada: $TIPUS   Usuari: $USUARI"

# 1. Paquets
echo ">> Instal·lant paquets"
apt-get update -q
PAQUETS="auditd"
[ "$AMB_SSH" -eq 1 ] && PAQUETS="$PAQUETS openssh-server"
DEBIAN_FRONTEND=noninteractive apt-get install -y -q $PAQUETS

# 2. Inici de sessió automàtic
echo ">> Configurant inici de sessió automàtic"
case "$TIPUS" in
    gdm)
        F=/etc/gdm3/custom.conf
        sed -i '/^#*\s*AutomaticLoginEnable\s*=/d; /^#*\s*AutomaticLogin\s*=/d' "$F"
        grep -q '^\[daemon\]' "$F" || echo '[daemon]' >> "$F"
        sed -i "/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin=$USUARI" "$F"
        ;;
    lightdm)
        mkdir -p /etc/lightdm/lightdm.conf.d
        cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<EOF
[Seat:*]
autologin-user=$USUARI
autologin-user-timeout=0
EOF
        ;;
    server)
        mkdir -p /etc/systemd/system/getty@tty1.service.d
        cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USUARI --noclear %I \$TERM
EOF
        ;;
esac

# 3. Sudo sense contrasenya
echo ">> Sudo sense contrasenya per a $USUARI"
usermod -aG sudo "$USUARI"
echo "$USUARI ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$USUARI"
chmod 440 "/etc/sudoers.d/90-$USUARI"
if ! visudo -cf "/etc/sudoers.d/90-$USUARI" >/dev/null; then
    echo "ERROR al fitxer sudoers, l'esborro"
    rm -f "/etc/sudoers.d/90-$USUARI"
fi

# 4. Específic Desktop / Server
if [ "$TIPUS" = "server" ]; then
    echo ">> Traient l'espera de xarxa a l'arrencada"
    systemctl mask systemd-networkd-wait-online.service || true
else
    echo ">> Traient bloqueig i apagat de pantalla"
    mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
    if [ ! -f /etc/dconf/profile/user ]; then
        printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
    elif ! grep -q 'system-db:local' /etc/dconf/profile/user; then
        echo 'system-db:local' >> /etc/dconf/profile/user
    fi
    cat > /etc/dconf/db/local.d/00-isard <<EOF
[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false

[org/gnome/desktop/lockdown]
disable-lock-screen=true

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
EOF
    dconf update || true
fi

# 5. Usuari corrector
if [ "$AMB_CORRECTOR" -eq 1 ]; then
    if ! id corrector >/dev/null 2>&1; then
        echo ">> Creant usuari corrector"
        adduser --disabled-password --gecos "" corrector
        usermod -aG sudo corrector
        echo "Posa una contrasenya per a corrector:"
        passwd corrector
    else
        echo ">> L'usuari corrector ja existeix"
    fi
fi

# 6. SSH
if [ "$AMB_SSH" -eq 1 ]; then
    echo ">> Configurant SSH"
    systemctl enable --now ssh || true
    if [ -n "$CLAU" ]; then
        CASA=$(getent passwd "$USUARI" | cut -d: -f6)
        mkdir -p "$CASA/.ssh"
        grep -qxF "$CLAU" "$CASA/.ssh/authorized_keys" 2>/dev/null || echo "$CLAU" >> "$CASA/.ssh/authorized_keys"
        chmod 700 "$CASA/.ssh"
        chmod 600 "$CASA/.ssh/authorized_keys"
        chown -R "$USUARI:$USUARI" "$CASA/.ssh"
    fi
fi

# 7. Registre de comandes amb auditd
echo ">> Configurant auditd"
cat > /etc/audit/rules.d/90-correccio.rules <<EOF
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=unset -k cmd
-a always,exit -F arch=b32 -S execve -F auid>=1000 -F auid!=unset -k cmd
EOF
systemctl enable auditd
augenrules --load || true

# 8. Data i hora a l'historial de bash
echo ">> Historial amb data i hora"
grep -q 'HISTTIMEFORMAT' /etc/bash.bashrc || cat >> /etc/bash.bashrc <<'EOF'

# Historial amb data i hora (preparar.sh)
export HISTTIMEFORMAT="%F %T  "
shopt -s histappend
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF

# 9. Journal persistent
echo ">> Journal persistent"
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal || true
systemctl restart systemd-journald || true

systemctl daemon-reload

echo
echo "=== Fet. Reinicia amb: sudo reboot ==="
echo "Després comprova:"
echo "  - Entra sol com a $USUARI"
echo "  - sudo -k; sudo whoami   -> root sense contrasenya"
echo "  - systemd-analyze        -> pocs segons"
echo "  - sudo ausearch -k cmd -i | tail"
