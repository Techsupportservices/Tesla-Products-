<#
Author: Adapted from https://github.com/bradhawkins85
Updated: Tactical RMM Installer v2.12.0
#>

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- CONFIGURATION ---
$api       = "https://api.dylanservers.top"
$clientid  = "1"
$siteid    = "1"
$agenttype = "server"
$auth      = "dd9052c2685252cfd79a37a459bc3e35543e5b92114068ffd85214704167ff76"

$innosetup    = "tacticalagent-v2.12.0-windows-amd64.exe"
$downloadlink = "https://github.com/amidaware/rmmagent/releases/download/v2.12.0/tacticalagent-v2.12.0-windows-amd64.exe"
$OutPath      = $env:TMP
$outputFile   = Join-Path $OutPath $innosetup

# Agent executable locations to check
$pathsToCheck = @(
    "C:\Program Files\TacticalAgent\tacticalrmm.exe",
    "C:\Program Files (x86)\TacticalAgent\tacticalrmm.exe"
)

# Optional Features (Set to 1 to enable)
$power       = 0
$rdp         = 0
$ping        = 0

Write-Host "Checking if Tactical RMM is already installed..."

# --- CHECK SERVICE ---
If (Get-Service -Name 'tacticalrmm' -ErrorAction SilentlyContinue) {
    Write-Host "Tactical RMM Service is already installed." -ForegroundColor Green
    Exit 0
}

# --- NETWORK CHECK ---
Write-Host "Checking network connectivity..."
$serverUrl = ([System.Uri]$api).Host
$X = 0
$connectResult = $null

do {
    Write-Output "Waiting for network connection ($X/3 attempts)..."
    Start-Sleep -Seconds 5
    $connectResult = Test-NetConnection -ComputerName $serverUrl -Port 443 -ErrorAction SilentlyContinue
    $X++    
} until ($connectResult.TcpTestSucceeded -or $X -eq 3)

If (-not $connectResult.TcpTestSucceeded) {
    Write-Host "ERROR: Unable to connect to server" -ForegroundColor Red
    Exit 1
}

Write-Host "Network OK."

# --- ANTI-VIRUS EXCLUSIONS ---
Try {
    $defenderStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object -ExpandProperty AntivirusEnabled
    
    If ($defenderStatus -eq $true) {
        Write-Host "Adding Defender exclusions..."
        Add-MpPreference -ExclusionPath 'C:\Program Files\TacticalAgent\*' -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath 'C:\Program Files\Mesh Agent\*' -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath 'C:\ProgramData\TacticalRMM\*' -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath 'C:\Program Files (x86)\TacticalAgent\*' -ErrorAction SilentlyContinue
    }
} Catch {
    Write-Host "Could not set Defender exclusions: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- DOWNLOAD ---
Write-Host "Downloading installer..."
Try {
    Invoke-WebRequest -Uri $downloadlink -OutFile $outputFile -UseBasicParsing -TimeoutSec 60
    Unblock-File -Path $outputFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path ("$outputFile:Zone.Identifier") -ErrorAction SilentlyContinue
    Write-Host "Download complete." -ForegroundColor Green
} Catch {
    Write-Host "FAIL: Download error. $($_.Exception.Message)" -ForegroundColor Red
    Exit 1
}

# --- INSTALL ---
Write-Host "Running silent installation..."
Start-Process -FilePath $outputFile -ArgumentList '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES' -Wait

Write-Host "Waiting for executable to extract..."
Start-Sleep -Seconds 10

# Locate the executable
$agentExePath = $null
$pathsToCheck | ForEach-Object {
    If (Test-Path $_) {
        $agentExePath = $_
        Break
    }
}

# If not found in standard paths, search for it
If (-not $agentExePath) {
    $found = Get-ChildItem "C:\Program Files\TacticalAgent\" -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $foundAlt = Get-ChildItem "C:\Program Files (x86)\TacticalAgent\" -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    If ($found) { $agentExePath = $found.FullName }
    If ($foundAlt -and -not $agentExePath) { $agentExePath = $foundAlt.FullName }
}

If (-not $agentExePath) {
    Write-Host "ERROR: Could not locate tacticalrmm.exe after installation." -ForegroundColor Red
    # Clean up installer and exit
    Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue
    Exit 1
}

# --- REGISTER AGENT ---
Write-Host "Registering agent to server..."
$installArgs = @(
    '-m', 'install',
    '--api', $api,
    '--client-id', $clientid,
    '--site-id', $siteid,
    '--agent-type', $agenttype,
    '--auth', $auth
)

# Add optional args
If ($power) { $installArgs += '--power' }
If ($rdp)   { $installArgs += '--rdp' }
If ($ping)  { $installArgs += '--ping' }

Try {
    Start-Process -FilePath $agentExePath -ArgumentList ($installArgs -join ' ') -WindowStyle Hidden -Wait
    Start-Sleep -Seconds 3

    # Verify service started
    If (Get-Service -Name 'tacticalrmm' -ErrorAction SilentlyContinue) {
        Write-Host "SUCCESS: Agent registered and service running." -ForegroundColor Green
    } Else {
        Write-Host "WARNING: Service not detected immediately. Check manually." -ForegroundColor Yellow
    }
} Catch {
    Write-Host "FAIL: Registration error. $($_.Exception.Message)" -ForegroundColor Red
    Exit 1
}

# --- CLEANUP ---
Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue
Write-Host "Installation complete."
Exit 0
