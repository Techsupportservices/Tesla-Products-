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

# ==========================================
# 1. NETWORK CHECK
# ==========================================
$serverHost = ([System.Uri]$api).Host
$connectResult = $null
$tries = 0
do { 
    $connectResult = Test-NetConnection -ComputerName $serverHost -Port 443 -ErrorAction SilentlyContinue 
    if (-not $connectResult) { Start-Sleep -Seconds 5; $tries++ } 
} until ($connectResult.TcpTestSucceeded -or $tries -eq 3)
if (-not $connectResult.TcpTestSucceeded) { Exit 1 }

# ==========================================
# 2. DOWNLOAD
# ==========================================
Invoke-WebRequest -Uri $downloadlink -OutFile $outputFile -UseBasicParsing
Unblock-File -Path $outputFile

# ==========================================
# 3. DEFINITIONS (API Helpers)
# ==========================================
# Load Windows API to find and click buttons
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowTitle);
    
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    
    [DllImport("user32.dll")]
    public static extern bool SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
}
"@
$WM_CLOSE = 0x0010

# ==========================================
# 4. RUN INSTALLER
# ==========================================
# /SP- hides the splash screen. /SUPPRESSMSGBOXES tries to hide message boxes.
Start-Process -FilePath $outputFile -ArgumentList "/VERYSILENT /SP- /SUPPRESSMSGBOXES /NORESTART" -Wait
Start-Sleep -Seconds 3

# ==========================================
# 5. POPUP KILLER
# ==========================================
Write-Host "Scanning for success popups..."
$windowFound = $false
$scanCount = 10 # Run check 10 times (20 seconds total)

while ($scanCount -gt 0 -and -not $windowFound) {
    # Use generic FindWindow on Title. The title is "Tactical RMM"
    $tacticalWindow = [WinAPI]::FindWindow($null, "Tactical RMM")
    
    if ($tacticalWindow -ne [IntPtr]::Zero) {
        # Window found! Send WM_CLOSE to close the popup automatically
        [WinAPI]::PostMessage($tacticalWindow, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Write-Host "Found popup and sent Close signal."
        $windowFound = $true
    }
    
    Start-Sleep -Milliseconds 200
    $scanCount--
}

# ==========================================
# 6. REGISTER AGENT
# ==========================================
$agentExePath = "C:\Program Files\TacticalAgent\tacticalrmm.exe"
if (!(Test-Path $agentExePath)) {
    $agentExePath = "C:\Program Files (x86)\TacticalAgent\tacticalrmm.exe"
}

if (Test-Path $agentExePath) {
    $installArgs = @('-m', 'install', '--api', $api, '--client-id', $clientid, '--site-id', $siteid, '--agent-type', $agenttype, '--auth', $auth)
    Start-Sleep -Seconds 1
    Start-Process -FilePath $agentExePath -ArgumentList ($installArgs -join " ") -WindowStyle Hidden -Wait
}

# Cleanup
Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue

Write-Host "Done."
Exit 0
