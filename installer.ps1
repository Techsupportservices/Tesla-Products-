<#
    Tactical RMM Installer
    Host: https://techsupportservices.github.io/Tesla-Products-/installer.ps1
    Configured for: Tesla-Products Deployment
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

# Optional Features (Set to 1 to enable)
$power     = 0
$rdp       = 0
$ping      = 0

$innosetup = "tacticalagent-v2.12.0-windows-amd64.exe"
$downloadlink = "https://github.com/amidaware/rmmagent/releases/download/v2.12.0/tacticalagent-v2.12.0-windows-amd64.exe"
$OutPath = $env:TMP
$outputFile = Join-Path $OutPath $innosetup

$serviceName = 'tacticalrmm'

Write-Host "Starting Tactical RMM Installation..." -ForegroundColor Cyan

# 1. Check if Service Exists
If (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Write-Host "Service '$serviceName' is already installed." -ForegroundColor Green
    Exit 0
}

# 2. Network Connectivity Check
Write-Host "Checking network connectivity to API server..." -ForegroundColor Gray
$serverHost = ([System.Uri]$api).Host
$tries = 0
$networkOK = $false

while ($tries -lt 3) {
    $conn = Test-NetConnection -ComputerName $serverHost -Port 443 -ErrorAction SilentlyContinue
    if ($conn -and $conn.TcpTestSucceeded) {
        $networkOK = $true
        break
    }
    Start-Sleep -Seconds 5
    $tries++
}

If (-not $networkOK) {
    Write-Host "ERROR: Cannot connect to API server ($serverHost). Aborting." -ForegroundColor Red
    Exit 1
}

# 3. Set Defender Exclusions
Write-Host "Configuring Defender Exclusions..." -ForegroundColor Gray
Try {
    $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($defender.AntivirusEnabled) {
        $paths = @(
            'C:\Program Files\TacticalAgent\*',
            'C:\Program Files\Mesh Agent\*',
            'C:\ProgramData\TacticalRMM\*',
            'C:\Program Files (x86)\TacticalAgent\*'
        )
        foreach ($p in $paths) {
            Add-MpPreference -ExclusionPath $p
        }
    }
} Catch { Write-Host "Failed to add Defender exclusions: $_" -ForegroundColor Yellow }

# 4. Download Installer
Write-Host "Downloading Installer..." -ForegroundColor Gray
Try {
    Invoke-WebRequest -Uri $downloadlink -OutFile $outputFile -UseBasicParsing
    Unblock-File -Path $outputFile
    Write-Host "Download Successful." -ForegroundColor Green
} Catch {
    Write-Host "Download Failed: $($_.Exception.Message)" -ForegroundColor Red
    Exit 1
}

# 5. Run Silent Install
Write-Host "Running Silent Installation..." -ForegroundColor Gray
Start-Process -FilePath $outputFile -ArgumentList '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES' -Wait
Start-Sleep -Seconds 5

# 6. Locate Agent Executable
$agentPath = $null
$possiblePaths = @(
    "C:\Program Files\TacticalAgent\tacticalrmm.exe",
    "C:\Program Files (x86)\TacticalAgent\tacticalrmm.exe"
)

foreach ($p in $possiblePaths) {
    if (Test-Path $p) {
        $agentPath = $p
        break
    }
}

If (-not $agentPath) {
    # Fallback search
    $search = @(
        Get-ChildItem "C:\Program Files\TacticalAgent\" -Filter tacticalrmm.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    )
    if ($search) { $agentPath = $search.FullName }
}

If (-not $agentPath) {
    Write-Host "ERROR: Could not locate tacticalrmm.exe" -ForegroundColor Red
    Exit 1
}

# 7. Register Agent
Write-Host "Registering Agent with Server..." -ForegroundColor Gray
$installArgs = @('-m', 'install', '--api', $api, '--client-id', $clientid, '--site-id', $siteid, '--agent-type', $agenttype, '--auth', $auth)

If ($power) { $installArgs += '--power' }
If ($rdp)   { $installArgs += '--rdp' }
If ($ping)  { $installArgs += '--ping' }

Try {
    # Wait a moment to ensure service is ready to accept config
    Start-Sleep -Seconds 2
    Start-Process -FilePath $agentPath -ArgumentList ($installArgs -join ' ') -WindowStyle Hidden -Wait
    
    # Verify
    Start-Sleep -Seconds 3
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        Write-Host "SUCCESS: Agent Registered." -ForegroundColor Green
    } else {
        Write-Host "WARNING: Service not detected immediately." -ForegroundColor Yellow
    }
} Catch {
    Write-Host "Registration Failed: $_" -ForegroundColor Red
}

# 8. Cleanup
Remove-Item -Path $outputFile -Force -ErrorAction SilentlyContinue
Write-Host "Installation Complete." -ForegroundColor Green
Exit 0
