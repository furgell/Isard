<#
  preparar-windows.ps1
  Prepara una maquina Windows Server o Windows 10/11 d'IsardVDI per convertir-la en plantilla:
  inici de sessio automatic (nologin), sense bloqueig de pantalla, SSH, usuari 'corrector'
  i registre de l'activitat.

  Executa-ho UNA vegada a la maquina base, en una PowerShell "Com a administrador":

    cd $env:TEMP
    iwr https://raw.githubusercontent.com/furgell/isard/main/preparar-windows.ps1 -OutFile preparar-windows.ps1 -UseBasicParsing
    Set-ExecutionPolicy -Scope Process Bypass -Force
    .\preparar-windows.ps1

  Activa SSH (usuari i contrasenya) per si de cas; la correccio es fa pel visor VNC.
  Opcions:  -SenseSSH  (no activar-lo)   -PublicKey "ssh-ed25519 AAAA..."  (opcional)
#>
param(
    [string]$AutoUser     = "isard",
    [string]$AutoPassword = "pirineus",
    [string]$PublicKey    = "",
    [switch]$NoCorrector,            # no crear l'usuari 'corrector'
    [switch]$SenseSSH                # no activar el servidor OpenSSH
)

$ErrorActionPreference = "Stop"
function Pas($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
# Crea una clau del registre nomes si no existeix (New-Item -Force esborraria els valors que ja te)
function Clau($p) { if (-not (Test-Path $p)) { New-Item $p -Force | Out-Null } }

# ---------------------------------------------------------------------------
Pas "1. Inici de sessio automatic ($AutoUser)"
$wl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty $wl -Name AutoAdminLogon    -Value "1"
Set-ItemProperty $wl -Name DefaultUserName   -Value $AutoUser
Set-ItemProperty $wl -Name DefaultPassword   -Value $AutoPassword
Set-ItemProperty $wl -Name DefaultDomainName -Value $env:COMPUTERNAME
Remove-ItemProperty $wl -Name AutoLogonCount -ErrorAction SilentlyContinue
# No demanar Ctrl+Alt+Supr
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name DisableCAD -Value 1 -Type DWord

# Energia: la maquina te una directiva (GPO) que mana sobre powercfg,
# aixi que fixem els valors directament a la directiva (0 = mai / no demanar contrasenya)
$pp = "HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings"
$energia = @{
    "3C0BC021-C8A8-4E07-A973-6B14CBCB2B7E" = 0   # apagar pantalla: mai
    "29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA" = 0   # repos: mai
    "9D7815A6-7EE4-497E-8888-515A05F02364" = 0   # hibernar: mai
    "0E796BDB-100D-47D6-A2D5-F7D2DAA51F51" = 0   # demanar contrasenya en despertar: no
}
foreach ($g in $energia.Keys) {
    Clau "$pp\$g"
    Set-ItemProperty "$pp\$g" -Name ACSettingIndex -Value $energia[$g] -Type DWord
    Set-ItemProperty "$pp\$g" -Name DCSettingIndex -Value $energia[$g] -Type DWord
}
# I tambe al pla actual (si la directiva no ho permet, ho ignorem)
cmd /c "powercfg /change monitor-timeout-ac 0 >nul 2>&1"
cmd /c "powercfg /change standby-timeout-ac 0 >nul 2>&1"
cmd /c "powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 >nul 2>&1"
cmd /c "powercfg /SETACTIVE SCHEME_CURRENT >nul 2>&1"
# Sense salvapantalles amb bloqueig (tambe per directiva, per a tots els usuaris)
Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name ScreenSaveActive -Value "0"
$ss = "HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop"
Clau $ss
Set-ItemProperty $ss -Name ScreenSaveActive    -Value "0"
Set-ItemProperty $ss -Name ScreenSaverIsSecure -Value "0"
# Sense pantalla de bloqueig
Clau "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name NoLockScreen -Value 1 -Type DWord

# ---------------------------------------------------------------------------
if (-not $SenseSSH) {
    Pas "2. Servidor OpenSSH (entrada amb usuari i contrasenya des de qualsevol maquina)"
    $cap = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"
    if ($cap.State -ne "Installed") { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
    Set-Service sshd -StartupType Automatic
    Start-Service sshd
    # Port 22 obert a qualsevol origen i a tots els perfils de xarxa (public, privat, domini)
    if (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue) {
        Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True -Profile Any -RemoteAddress Any
    } else {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
            -Profile Any -RemoteAddress Any | Out-Null
    }
    # Shell per defecte: PowerShell
    Clau "HKLM:\SOFTWARE\OpenSSH"
    Set-ItemProperty "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    # Clau publica: opcional (amb contrasenya ja s'hi pot entrar)
    if ($PublicKey) {
        $ak = "C:\ProgramData\ssh\administrators_authorized_keys"
        if (-not ((Test-Path $ak) -and (Select-String -Path $ak -SimpleMatch $PublicKey -Quiet))) {
            Add-Content -Path $ak -Value $PublicKey
        }
        icacls $ak /inheritance:r /grant "*S-1-5-32-544:F" /grant "SYSTEM:F" | Out-Null
        Write-Host "Clau publica afegida a $ak"
    }
} else { Pas "2. SSH: no s'activa (-SenseSSH)" }

# ---------------------------------------------------------------------------
if (-not $NoCorrector) {
    Pas "3. Usuari 'corrector' (per entrar pel visor si l'alumne canvia la contrasenya d'$AutoUser)"
    if (-not (Get-LocalUser -Name corrector -ErrorAction SilentlyContinue)) {
        $pw = Read-Host "Contrasenya per a 'corrector' (no la donis als alumnes)" -AsSecureString
        New-LocalUser -Name corrector -Password $pw -PasswordNeverExpires `
            -Description "Compte del professor - NO TOCAR" | Out-Null
        # S-1-5-32-544 = Administradors (funciona en qualsevol idioma)
        Add-LocalGroupMember -SID "S-1-5-32-544" -Member corrector
    }
}

# ---------------------------------------------------------------------------
Pas "4. Registre de PowerShell (transcripcio + script blocks + moduls)"
$ps = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell"
Clau "$ps\Transcription"
Clau "$ps\ScriptBlockLogging"
Clau "$ps\ModuleLogging\ModuleNames"
New-Item "C:\Logs\PS" -ItemType Directory -Force | Out-Null
Set-ItemProperty "$ps\Transcription" -Name EnableTranscripting    -Value 1 -Type DWord
Set-ItemProperty "$ps\Transcription" -Name EnableInvocationHeader -Value 1 -Type DWord
Set-ItemProperty "$ps\Transcription" -Name OutputDirectory        -Value "C:\Logs\PS"
Set-ItemProperty "$ps\ScriptBlockLogging" -Name EnableScriptBlockLogging -Value 1 -Type DWord
Set-ItemProperty "$ps\ModuleLogging" -Name EnableModuleLogging -Value 1 -Type DWord
Set-ItemProperty "$ps\ModuleLogging\ModuleNames" -Name "*" -Value "*"

# ---------------------------------------------------------------------------
Pas "5. Auditoria de processos amb linia de comandes (cmd, netsh, mmc...)"
# GUID de 'Process Creation' -> independent de l'idioma del Windows
auditpol /set /subcategory:"{0CCE922B-69AE-11D9-BED3-505054503030}" /success:enable | Out-Null
$aud = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
Clau $aud
Set-ItemProperty $aud -Name ProcessCreationIncludeCmdLine_Enabled -Value 1 -Type DWord

# ---------------------------------------------------------------------------
Pas "6. Mida dels registres d'esdeveniments"
wevtutil sl Security /ms:1073741824                               # 1 GB
wevtutil sl System   /ms:268435456                                # 256 MB
wevtutil sl Application /ms:268435456
wevtutil sl "Microsoft-Windows-PowerShell/Operational" /ms:536870912
wevtutil sl "Windows PowerShell" /ms:268435456

# ---------------------------------------------------------------------------
Pas "Fet"
Write-Host @"
Comprova:
  - Reinicia: ha d'entrar sol com a $AutoUser.
  - Obre-la amb el visor del navegador de l'Isard: ha de mostrar l'escriptori.
  - ssh $AutoUser@<IP>   (des de qualsevol maquina amb acces a la xarxa de l'Isard)
  - Get-ChildItem C:\Logs\PS -Recurse   despres d'obrir una PowerShell
Despres ja la pots apagar i convertir en plantilla.
"@ -ForegroundColor Green
