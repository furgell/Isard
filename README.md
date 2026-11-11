# isard

Scripts i notes per preparar plantilles Ubuntu i Windows a IsardVDI.

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

## preparar-windows.ps1

Prepara una màquina Windows Server o Windows 10/11 per convertir-la en plantilla:

- Inici de sessió automàtic (nologin) amb l'usuari `isard`
- Sense Ctrl+Alt+Supr, sense bloqueig ni apagat de pantalla, sense repòs
- Usuari de reserva `corrector` (administrador, amb contrasenya)
- SSH, registre de PowerShell, auditoria de processos amb línia de comandes

### Ús dins la màquina (PowerShell com a administrador)

```
cd $env:TEMP
iwr https://raw.githubusercontent.com/furgell/isard/main/preparar-windows.ps1 -OutFile preparar-windows.ps1 -UseBasicParsing
Set-ExecutionPolicy -Scope Process Bypass -Force
.\preparar-windows.ps1
Restart-Computer
```

Opcions: `-SenseSSH`, `-PublicKey "ssh-ed25519 AAAA..."`, `-NoCorrector`, `-AutoUser isard -AutoPassword pirineus`

Explicacions, ordres per fer-ho a mà i problemes trobats: [autologin-windows.md](autologin-windows.md).

## Documents

- [GUIA.md](GUIA.md): guia completa (pas a pas, comprovacions i problemes trobats)
- [autologin-ubuntu-server.md](autologin-ubuntu-server.md): com es va configurar l'autologin a la primera plantilla Server
- [autologin-windows.md](autologin-windows.md): login automàtic (nologin) a Windows Server i Windows 10/11, a mà i amb el script
