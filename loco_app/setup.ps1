# LOCO - one-time project setup (Windows PowerShell)
# Run inside the loco_app folder:
#   powershell -ExecutionPolicy Bypass -File setup.ps1
$ErrorActionPreference = "Stop"

function Step($label, [scriptblock]$cmd) {
    Write-Host ""
    Write-Host "==> $label" -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) { throw "Failed: $label" }
}

Step "1/5  Create the Android project files" {
    flutter create --org com.elgringo --project-name loco --platforms=android .
}
Step "2/5  Download packages" { flutter pub get }
Step "3/5  Create the app icon (the LOCO logo)" { dart run flutter_launcher_icons }
Step "4/5  Create the splash screen" { dart run flutter_native_splash:create }

Write-Host ""
Write-Host "==> 5/5  Android permissions and app name" -ForegroundColor Cyan
$manifest = "android\app\src\main\AndroidManifest.xml"
if (-not (Test-Path $manifest)) { throw "Manifest not found: $manifest" }
$xml = Get-Content $manifest -Raw

if ($xml -notmatch "RECORD_AUDIO") {
    $perms = @'
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-feature android:name="android.hardware.microphone" android:required="false"/>

'@
    $xml = [regex]::Replace($xml, "<application", ($perms + "    <application"), 1)
}
$xml = $xml -replace 'android:label="[^"]*"', 'android:label="LOCO"'
Set-Content -Path $manifest -Value $xml -Encoding UTF8

Write-Host ""
Write-Host "Done. Next:" -ForegroundColor Green
Write-Host "  1) Put your Render address in lib\config.dart (or enter it inside the app)"
Write-Host "  2) flutter run                       (test on your phone)"
Write-Host "  3) flutter build apk --release --split-per-abi --no-shrink"
