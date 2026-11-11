# Login automàtic a Ubuntu Server (IsardVDI)

Màquina: **UBUNTU SERVER Nologin2** (`isardvdi`), usuari `isard`.

## Com es va configurar

No es va fer a mà. Es va fer amb el script `~/preparar.sh` (`preparar-plantilla-ubuntu.sh`). Segons `/var/log/auth.log`:

| Data | Ordre |
|---|---|
| 25/10/2026 08:29 | `sudo nano preparar.sh` |
| 25/10/2026 08:40 | `sudo bash preparar.sh` |

El fitxer `autologin.conf` es va crear el 25/10 a les 08:40. És la mateixa hora en què es va executar el script.

## Ordres que fa el script (cas Server, consola tty1)

```bash
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin isard --noclear %I \$TERM
EOF
systemctl daemon-reload
```

Contingut final de `/etc/systemd/system/getty@tty1.service.d/autologin.conf`:

```ini
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin isard --noclear %I $TERM
```

Alternativa manual, amb el mateix resultat:

```bash
sudo systemctl edit getty@tty1
# enganxar les 3 línies de dalt, desar
sudo systemctl daemon-reload
sudo systemctl restart getty@tty1
```

## Cas Desktop (GDM)

A les versions Desktop, el script edita `/etc/gdm3/custom.conf` i hi posa això a la secció `[daemon]`:

```ini
AutomaticLoginEnable=true
AutomaticLogin=isard
```

Amb LightDM, crea `/etc/lightdm/lightdm.conf.d/50-autologin.conf`:

```ini
[Seat:*]
autologin-user=isard
autologin-user-timeout=0
```

## Què més fa `preparar.sh`

1. Instal·la paquets: `auditd` i `openssh-server`. L'SSH s'instal·la si no es passa `--sense-ssh`.
2. Configura l'inici de sessió automàtic.
3. A Desktop, desactiva el bloqueig i l'apagat de pantalla.
4. Crea l'usuari de reserva `corrector`, del grup sudo.
5. Configura l'SSH, amb clau opcional.
6. Configura el registre de comandes amb auditd (`/etc/audit/rules.d/90-correccio.rules`).
7. Afegeix data i hora al historial de bash, per a tots els usuaris, a `/etc/bash.bashrc`.
8. Fa que el journal sigui persistent (`/var/log/journal`).

### Ús

```bash
sudo bash preparar.sh [--sense-ssh] [--key "ssh-ed25519 AAAA..."] [--no-corrector] [--user isard]
```

### Comprovacions

- Reinicia la màquina: ha d'entrar sola com a `isard`.
- Obre-la amb el visor del navegador de l'Isard: ha de mostrar la sessió oberta.
- `ssh isard@<IP>`
- `sudo ausearch -k cmd -i | tail`: ha de mostrar comandes.
- Després, apaga-la i converteix-la en plantilla.

## Com es va trobar

```bash
zgrep -i command /var/log/auth.log*          # comandes executades amb sudo
find /etc/systemd/system -name autologin.conf -ls   # data del fitxer
zgrep -h 2026-10-25 /var/log/auth.log.1 /var/log/auth.log.2.gz
```
