# Plantilles Ubuntu a IsardVDI: autologin i sudo sense contrasenya

## Objectiu

Les plantilles Ubuntu (Server i Desktop) han d'entrar soles amb l'usuari `isard` i no han de demanar mai la contrasenya de `sudo`. A més, el Server ha d'arrencar en pocs segons i no en més de 2 minuts.

Tot es fa un sol cop a la màquina que farà de plantilla. Les màquines creades a partir d'ella ja ho porten fet.

## El script preparar.sh

Tot el procés el fa un sol script, [`preparar.sh`](preparar.sh). Detecta sol si la màquina és Server o Desktop.

| Què fa | Server | Desktop |
| --- | --- | --- |
| Inici de sessió automàtic amb `isard` | Consola tty1 (agetty) | GDM o LightDM |
| `sudo` sense contrasenya per a `isard` | Sí | Sí |
| Treure l'espera de xarxa de 2 minuts | Sí | No cal |
| Treure bloqueig i apagat de pantalla | No cal | Sí |
| Usuari de reserva `corrector` (sudo amb contrasenya) | Sí | Sí |
| SSH, registre de comandes (auditd), historial amb data i hora, journal persistent | Sí | Sí |

Opcions: `--no-corrector` (no crea `corrector`), `--sense-ssh`, `--key "ssh-ed25519 AAAA..."`, `--user nom`.

## Pas a pas

Es fa igual a Server i a Desktop. Les ordres són curtes perquè es puguin escriure a mà, ja que la consola SPICE no permet enganxar.

1. Engega la màquina que serà la plantilla i obre un terminal.
2. Descarrega el script:
   ```
   wget https://raw.githubusercontent.com/furgell/isard/main/preparar.sh
   ```
3. Comprova que s'ha descarregat bé. La primera línia ha de ser `#!/bin/bash`:
   ```
   head -1 preparar.sh
   ```
4. Executa'l. Et demanarà una contrasenya per a `corrector` (afegeix `--no-corrector` si no el vols):
   ```
   sudo bash preparar.sh
   ```
5. Reinicia:
   ```
   sudo reboot
   ```
6. Fes les comprovacions de la secció següent.
7. Si tot és correcte, apaga la màquina i converteix-la en plantilla a IsardVDI.

## Comprovacions després de reiniciar

| Què comprovar | Ordre | Resultat esperat |
| --- | --- | --- |
| Autologin | (cap) | Entra sol com a `isard`, sense demanar usuari ni contrasenya |
| Grup sudo | `id` | Hi surt `(sudo)` |
| Sudo sense contrasenya | `sudo -k` i després `sudo whoami` | `root`, sense demanar res |
| Arrencada ràpida | `systemd-analyze` | Pocs segons, no més de 2 minuts |
| Espera de xarxa desactivada (Server) | `systemctl is-enabled systemd-networkd-wait-online` | `masked` |
| Xarxa activa | `ip -br a` | Interfície `UP` i amb IP |
| Registre de comandes | `sudo ausearch -k cmd -i \| tail` | Hi surten les comandes executades |
| Pantalla (Desktop) | Deixar-la quieta 10 minuts | No es bloqueja |

## Problemes trobats i solucions

### Ubuntu Server tarda més de 2 minuts a arrencar

`systemd-analyze blame` mostrava `systemd-networkd-wait-online.service` amb 2 min 222 ms. El sistema esperava que totes les interfícies de xarxa tinguessin IP, i a IsardVDI alguna no en rep. La solució, que el script ja aplica:

```
sudo systemctl mask systemd-networkd-wait-online
```

A Desktop la xarxa la gestiona NetworkManager i normalment no passa. Si passa, la solució és `sudo systemctl mask NetworkManager-wait-online`.

### No es pot enganxar text a la consola SPICE

El visor del navegador d'Isard no passa el porta-retalls. Per això el script es descarrega amb `wget` des de GitHub en lloc d'enganxar-lo. Altres opcions: connectar-se per SSH des del PC, o fer servir el client `remote-viewer` amb `spice-vdagent` instal·lat a la màquina.

### Per a què serveix l'usuari corrector

És un usuari de reserva amb sudo i contrasenya pròpia, sense autologin. Permet entrar a la màquina si l'alumne trenca `isard` sense voler, i corregir sense barrejar les teves comandes amb el seu historial. Com que `isard` és root, l'alumne el podria esborrar, així que protegeix contra accidents, no contra algun canvi fet expressament. Si no el vols, executa el script amb `--no-corrector` o esborra'l amb `sudo deluser --remove-home corrector`.

### Seguretat

Amb `sudo` sense contrasenya, qualsevol que obri la consola de la màquina és root. A IsardVDI no sol ser un problema, perquè cada alumne només veu la seva còpia.
