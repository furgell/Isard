# isard

Scripts i notes per preparar plantilles Ubuntu a IsardVDI.

## preparar.sh

Prepara una màquina Ubuntu (Server o Desktop) per convertir-la en plantilla:

- Inici de sessió automàtic amb l'usuari `isard`
- `sudo` sense contrasenya per a `isard`
- Server: treu l'espera de xarxa de 2 minuts a l'arrencada
- Desktop: treu el bloqueig i l'apagat de pantalla
- Usuari de reserva `corrector` (grup sudo, amb contrasenya)
- SSH, registre de comandes amb auditd, historial amb data i hora, journal persistent

### Ús dins la màquina

```
wget https://raw.githubusercontent.com/furgell/isard/main/preparar.sh
sudo bash preparar.sh
sudo reboot
```

Opcions: `--sense-ssh`, `--key "ssh-ed25519 AAAA..."`, `--no-corrector`, `--user isard`

### Comprovacions després de reiniciar

```
sudo -k
sudo whoami                 # root, sense demanar contrasenya
systemd-analyze             # pocs segons
sudo ausearch -k cmd -i | tail
```

Quan tot funcioni, apaga la màquina i converteix-la en plantilla.

## Documents

- [autologin-ubuntu-server.md](autologin-ubuntu-server.md): com es va configurar l'autologin a la primera plantilla Server
