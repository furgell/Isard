# Login automàtic (nologin) a Windows (IsardVDI)

Màquines: **Windows Server** i **Windows 10/11**, usuari administrador `isard` (contrasenya `pirineus`, la de les plantilles d'Isard).

L'objectiu és el mateix que a Ubuntu: que la màquina entri sola amb `isard` i no es bloquegi mai, perquè quan s'obre amb el visor del navegador d'Isard l'escriptori ja estigui a punt per treballar o corregir.

## Amb el script preparar-windows.ps1

Tot ho fa [`preparar-windows.ps1`](preparar-windows.ps1). És el mateix per a Windows Server i per a Windows 10/11.

1. Engega la màquina que serà la plantilla.
2. Obre una PowerShell **com a administrador**: clic dret al botó d'Inici → *Windows PowerShell (administrador)*. El títol de la finestra ha de dir "Administrador".
3. Descarrega i executa el script:
   ```powershell
   cd $env:TEMP
   iwr https://raw.githubusercontent.com/furgell/isard/main/preparar-windows.ps1 -OutFile preparar-windows.ps1 -UseBasicParsing
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\preparar-windows.ps1
   ```
4. Et demanarà una contrasenya per a `corrector`. Ha d'acabar amb el missatge verd **Fet**.
5. Reinicia i fes les comprovacions de més avall.
6. Si tot és correcte, apaga la màquina i converteix-la en plantilla a IsardVDI.

Opcions: `-NoCorrector` (no crea `corrector`), `-SenseSSH` (no activa SSH), `-PublicKey "ssh-ed25519 AAAA..."`, `-AutoUser nom -AutoPassword contrasenya` (si l'usuari no és `isard`).

### Què fa

| Pas | Què fa |
| --- | --- |
| 1. Inici de sessió automàtic | Claus `Winlogon` del registre (vegeu més avall). No demana Ctrl+Alt+Supr. |
| 1. Sense bloqueig | Pantalla, repòs i hibernació a "mai", no demana contrasenya en tornar, sense salvapantalles ni pantalla de bloqueig. Es fixa per directiva perquè la plantilla d'Isard té una GPO d'energia. |
| 2. SSH | Instal·la OpenSSH Server, l'arrenca automàticament, obre el port 22 a tots els perfils i posa PowerShell com a shell. |
| 3. Usuari `corrector` | Administrador de reserva amb contrasenya pròpia, que no caduca. |
| 4. Registre de PowerShell | Transcripció de totes les sessions a `C:\Logs\PS`, i registre de script blocks i mòduls. |
| 5. Auditoria de processos | Cada programa que s'obre, amb la línia de comandes (esdeveniment 4688 del registre Security). |
| 6. Mida dels registres | Security 1 GB, PowerShell 512 MB, System i Application 256 MB. |

## A mà: només el login automàtic

Si només vols el nologin, sense la resta del script. En una PowerShell d'administrador:

```powershell
$wl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty $wl AutoAdminLogon    "1"
Set-ItemProperty $wl DefaultUserName   "isard"
Set-ItemProperty $wl DefaultPassword   "pirineus"
Set-ItemProperty $wl DefaultDomainName $env:COMPUTERNAME
Remove-ItemProperty $wl AutoLogonCount -ErrorAction SilentlyContinue
```

El mateix des de `cmd` (d'administrador):

```bat
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d isard /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d pirineus /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /t REG_SZ /d %COMPUTERNAME% /f
```

| Valor | Per a què serveix |
| --- | --- |
| `AutoAdminLogon = 1` | Activa l'inici de sessió automàtic |
| `DefaultUserName` | Usuari que entra |
| `DefaultPassword` | Contrasenya d'aquest usuari, en clar |
| `DefaultDomainName` | Nom de l'equip (usuari local) o del domini |
| `AutoLogonCount` | Si existeix, limita el nombre d'inicis automàtics. S'esborra perquè no s'acabi. |

La contrasenya queda en clar al registre. Com que `pirineus` és la contrasenya coneguda de les plantilles d'Isard, no és un problema. Si algun dia l'usuari té una contrasenya que no ha de ser visible, fes servir [Autologon de Sysinternals](https://learn.microsoft.com/sysinternals/downloads/autologon), que la desa xifrada:

```
Autologon64.exe isard %COMPUTERNAME% pirineus /accepteula
```

Una altra manera, gràfica: `netplwiz` → desmarcar "Els usuaris han d'escriure un nom d'usuari i una contrasenya". A Windows 10/11 aquesta casella no apareix si està activat l'inici de sessió només amb Windows Hello.

### Que no es bloquegi

Les ordres del script que fan que la sessió no es bloquegi ni s'apagui la pantalla:

```powershell
# No demanar Ctrl+Alt+Supr
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" DisableCAD 1 -Type DWord

# Energia per directiva: pantalla, repòs, hibernació = mai; no demanar contrasenya en despertar
$pp = "HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings"
foreach ($g in "3C0BC021-C8A8-4E07-A973-6B14CBCB2B7E", "29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA",
               "9D7815A6-7EE4-497E-8888-515A05F02364", "0E796BDB-100D-47D6-A2D5-F7D2DAA51F51") {
    if (-not (Test-Path "$pp\$g")) { New-Item "$pp\$g" -Force | Out-Null }
    Set-ItemProperty "$pp\$g" ACSettingIndex 0 -Type DWord
    Set-ItemProperty "$pp\$g" DCSettingIndex 0 -Type DWord
}

# Sense pantalla de bloqueig (Windows Server i edicions Enterprise/Education)
$pz = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
if (-not (Test-Path $pz)) { New-Item $pz -Force | Out-Null }
Set-ItemProperty $pz NoLockScreen 1 -Type DWord
```

## Comprovacions després de reiniciar

| Què comprovar | Ordre | Resultat esperat |
| --- | --- | --- |
| Autologin | (cap) | Entra sol a l'escriptori com a `isard` |
| Valors del registre | `Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" \| Select AutoAdminLogon,DefaultUserName,DefaultDomainName` | `1`, `isard`, nom de l'equip |
| Sense bloqueig | Deixar-la quieta 15 minuts i obrir-la amb el visor | L'escriptori obert, sense demanar contrasenya |
| Usuari corrector | `Get-LocalUser corrector` | Existeix i està `Enabled` |
| SSH | `Get-Service sshd` i, des d'una altra màquina, `ssh isard@<IP>` | `Running`, i hi entra |
| Registre de PowerShell | `Get-ChildItem C:\Logs\PS -Recurse` | Fitxers de transcripció |

## Problemes trobats i solucions

### "La ejecución de scripts está deshabilitada en este sistema"

Passa a Windows 10/11, que per defecte no deixa executar scripts. A Windows Server sí que es pot. Abans d'executar el script:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
```

`-Scope Process` només afecta aquella finestra. Quan es tanca, Windows torna a bloquejar els scripts i la plantilla no queda oberta.

### "Hay una configuración de invalidación de directiva de grupo para esta combinación o configuración de energía"

La plantilla d'Isard té una directiva (GPO) d'energia que mana sobre `powercfg`, i per això `powercfg /change ...` no fa res. El script ara escriu els valors directament a la directiva (`HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings`) i amaga l'avís.

### `iwr` no pot descarregar el script

A versions antigues (Windows Server 2016, Windows 10 antic), PowerShell pot no fer servir TLS 1.2 i GitHub rebutja la connexió. Executa això abans de l'`iwr`:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
```

### El script no troba OpenSSH (pas 2)

`Add-WindowsCapability` descarrega OpenSSH de Windows Update. La màquina ha de tenir internet (xarxa *Default* d'Isard) i, a Windows 10, ser la versió 1809 o posterior (`winver`). Si no, executa el script amb `-SenseSSH`.

### La pantalla de bloqueig apareix igualment (Windows 10/11 Pro)

La directiva `NoLockScreen` només té efecte a Windows Server i a les edicions Enterprise i Education. Com que la sessió no es bloqueja per inactivitat, en principi no la veuràs.

### L'alumne converteix el servidor en controlador de domini

Els usuaris locals passen a ser del domini i l'autologin pot deixar de funcionar. Cal canviar el domini al registre:

```powershell
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" DefaultDomainName "NOMDOMINI"
```

Si no, entra pel visor amb `NOMDOMINI\isard` o `NOMDOMINI\corrector` (el botó de Ctrl+Alt+Supr del visor ho permet).

### L'alumne canvia la contrasenya d'isard

L'autologin deixa de funcionar perquè `DefaultPassword` ja no coincideix. Entra amb `corrector` i torna a posar la contrasenya nova a `DefaultPassword`, o restableix la de `isard`:

```powershell
net user isard pirineus
```

## Desfer el login automàtic

```powershell
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" AutoAdminLogon "0"
Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" DefaultPassword
```
