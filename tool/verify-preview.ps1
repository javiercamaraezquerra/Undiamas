# Verify the isolated local preview before copying the delivery APK.
# This inspects public APK signatures; it never reads a private signing key.
$ErrorActionPreference = 'Stop'
$taskApp = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskApk = Join-Path $taskApp 'build\app\outputs\apk\preview\release\app-preview-release.apk'
$taskPreviousApk = 'C:\Users\Javi\Documents\Quinielalab\dist\UnDiaMas-privacidad-v22\dist\UnDiaMas-privacidad-1.0.2-22.apk'
$taskTools = 'C:\Users\Javi\AppData\Local\Android\Sdk\build-tools\36.0.0'
$taskJava = 'C:\Users\Javi\Documents\MADE_WRONG\.local_tools\jdk-17\bin\java.exe'
$taskLogs = Join-Path $taskApp 'build\validation'
$taskDelivery = Join-Path $taskApp 'dist'
if (-not (Test-Path -LiteralPath $taskApk -PathType Leaf)) { throw 'No v24 APK has been built.' }
if (-not (Test-Path -LiteralPath $taskPreviousApk -PathType Leaf)) { throw 'The v22 reference APK is required to verify update compatibility.' }
[IO.Directory]::CreateDirectory($taskLogs) | Out-Null

$taskBadging = & (Join-Path $taskTools 'aapt.exe') dump badging $taskApk
if ($LASTEXITCODE -ne 0) { throw 'aapt verification failed.' }
$taskBadging | Set-Content -LiteralPath (Join-Path $taskLogs 'apk-badging-v24.txt') -Encoding UTF8
$taskManifestText = $taskBadging -join "`n"
foreach ($taskRequired in @(
    "package: name='com.celsoriaapps.undiamas.privacidad' versionCode='24' versionName='1.0.4'",
    "sdkVersion:'24'", "targetSdkVersion:'36'",
    "application-label:'Un Día Más'",
    "application-label-en:'One More Day'",
    "uses-permission: name='android.permission.POST_NOTIFICATIONS'",
    "uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'",
    "native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'"
)) {
    if (-not $taskManifestText.Contains($taskRequired)) { throw "Unexpected APK manifest: $taskRequired" }
}
foreach ($taskUnneededPermission in @('android.permission.SCHEDULE_EXACT_ALARM',
    'android.permission.USE_EXACT_ALARM', 'android.permission.USE_FULL_SCREEN_INTENT',
    'android.permission.READ_MEDIA_IMAGES', 'android.permission.READ_MEDIA_VIDEO',
    'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
    'android.permission.READ_EXTERNAL_STORAGE', 'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.MANAGE_EXTERNAL_STORAGE', 'android.permission.CAMERA')) {
    if ($taskManifestText.Contains($taskUnneededPermission)) {
        throw "Unexpected restricted permission: $taskUnneededPermission"
    }
}
$taskApplicationLabels = @($taskBadging | Where-Object { $_ -match '^application-label' })
if (-not $taskApplicationLabels.Count -or ($taskApplicationLabels -join "`n") -match '(?i)privacidad|privacy|fotos|preview') {
    throw 'The visible application name must remain the original name.'
}
$taskXmlTree = & (Join-Path $taskTools 'aapt.exe') dump xmltree $taskApk AndroidManifest.xml
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the packaged manifest.' }
$taskXmlTree | Set-Content -LiteralPath (Join-Path $taskLogs 'apk-manifest-v24.txt') -Encoding UTF8
foreach ($taskReceiver in @('ScheduledNotificationReceiver',
    'ScheduledNotificationBootReceiver', 'android.intent.action.BOOT_COMPLETED',
    'android.intent.action.MY_PACKAGE_REPLACED')) {
    if (-not ($taskXmlTree -join "`n").Contains($taskReceiver)) {
        throw "The packaged manifest is missing $taskReceiver"
    }
}

$taskCertificateHashes = @()
foreach ($taskSignedApk in @($taskPreviousApk, $taskApk)) {
    $taskSignature = & $taskJava -jar (Join-Path $taskTools 'lib\apksigner.jar') verify --verbose --print-certs $taskSignedApk
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $taskSignedApk" }
    $taskLogVersion = if ($taskSignedApk -eq $taskApk) { 'v24' } else { 'v22' }
    $taskSignature | Set-Content -LiteralPath (Join-Path $taskLogs "apk-signature-$taskLogVersion.txt") -Encoding UTF8
    $taskMatch = [regex]::Match(($taskSignature -join "`n"), 'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]{64})')
    if (-not $taskMatch.Success) { throw 'Certificate digest missing.' }
    $taskCertificateHashes += $taskMatch.Groups[1].Value.ToUpperInvariant()
}
if ($taskCertificateHashes[0] -ne $taskCertificateHashes[1]) { throw 'The new APK does not use the v22 certificate.' }

& (Join-Path $taskTools 'zipalign.exe') -c -P 16 -v 4 $taskApk | Set-Content -LiteralPath (Join-Path $taskLogs 'apk-alignment-v24.txt') -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw 'APK alignment verification failed.' }
# ZIP alignment and ELF segment alignment are separate Android 16 KiB checks.
$taskReadElf = 'C:\Users\Javi\AppData\Local\Android\Sdk\ndk\28.1.13356709\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe'
$taskElfDirectory = Join-Path $taskLogs 'native-libraries-v24'
$taskElfReport = [Collections.Generic.List[object]]::new()
$taskPreviewAdReport = [Collections.Generic.List[object]]::new()
$taskTestBannerId = 'ca-app-pub-3940256099942544/6300978111'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskZip = [IO.Compression.ZipFile]::OpenRead($taskApk)
try {
    foreach ($taskEntry in $taskZip.Entries) {
        if ($taskEntry.FullName -notmatch '^lib/(arm64-v8a|armeabi-v7a|x86_64)/([A-Za-z0-9_.-]+\.so)$') { continue }
        $taskAbi = $Matches[1]
        $taskLibrary = $Matches[2]
        $taskNativeDirectory = Join-Path $taskElfDirectory $taskAbi
        [IO.Directory]::CreateDirectory($taskNativeDirectory) | Out-Null
        $taskNativeFile = Join-Path $taskNativeDirectory $taskLibrary
        [IO.Compression.ZipFileExtensions]::ExtractToFile($taskEntry, $taskNativeFile, $true)
        if ($taskLibrary -eq 'libapp.so') {
            # The compile-time UDM_PREVIEW branch must retain Google's test
            # banner identifier in each AOT payload, including the 32-bit APK.
            $taskPayload = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($taskNativeFile))
            if (-not $taskPayload.Contains($taskTestBannerId)) {
                throw "The preview test banner is missing from $($taskEntry.FullName). Do not distribute this APK."
            }
            $taskPreviewAdReport.Add([ordered]@{ ABI=$taskAbi; TestBannerIdPresent=$true })
            $taskPayload = $null
        }
        if ($taskAbi -eq 'armeabi-v7a') { continue }
        $taskHeaders = & $taskReadElf --program-headers --wide $taskNativeFile
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect ELF: $($taskEntry.FullName)" }
        $taskHeaders | Set-Content -LiteralPath "$taskNativeFile.headers.txt" -Encoding UTF8
        $taskLoadSegments = @($taskHeaders | Where-Object { $_ -match '^\s*LOAD\s' })
        if (-not $taskLoadSegments.Count) { throw "Missing ELF LOAD segments: $($taskEntry.FullName)" }
        $taskAlignments = @(foreach ($taskSegment in $taskLoadSegments) {
            $taskHex = [regex]::Match($taskSegment, '0x([0-9a-fA-F]+)\s*$')
            if (-not $taskHex.Success) { throw 'ELF alignment field missing.' }
            $taskAlignment = [Convert]::ToInt64($taskHex.Groups[1].Value, 16)
            if ($taskAlignment -lt 16384) { throw "ELF below 16 KiB alignment: $($taskEntry.FullName)" }
            $taskAlignment
        })
        $taskElfReport.Add([ordered]@{ Library=$taskEntry.FullName; LoadAlignments=$taskAlignments })
    }
} finally { $taskZip.Dispose() }
if ($taskElfReport.Count -lt 4) { throw 'Expected the 64-bit Flutter engine and app libraries for both ABIs.' }
if ($taskPreviewAdReport.Count -ne 3) { throw 'Expected the test banner in all three app ABIs.' }
$taskElfReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskLogs 'apk-elf-alignment-v24.json') -Encoding UTF8
$taskPreviewAdReport | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskLogs 'apk-preview-ads-v24.json') -Encoding UTF8
$taskHash = (Get-FileHash -LiteralPath $taskApk -Algorithm SHA256).Hash
[IO.Directory]::CreateDirectory($taskDelivery) | Out-Null
$taskDeliveredApk = Join-Path $taskDelivery 'UnDiaMas-1.0.4-24-fotos-fase1.apk'
Copy-Item -LiteralPath $taskApk -Destination $taskDeliveredApk
if ((Get-FileHash -LiteralPath $taskDeliveredApk -Algorithm SHA256).Hash -ne $taskHash) { throw 'Delivery copy hash mismatch.' }
"$taskHash  UnDiaMas-1.0.4-24-fotos-fase1.apk" | Set-Content -LiteralPath (Join-Path $taskDelivery 'SHA256.txt') -Encoding ASCII
$taskReport = [ordered]@{
    VerifiedAt = (Get-Date).ToString('o')
    Package = 'com.celsoriaapps.undiamas.privacidad'
    Version = '1.0.4+24'
    VisibleName = 'Un Día Más'
    EnglishVisibleName = 'One More Day'
    MinSdk = 24
    TargetSdk = 36
    ABIs = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
    CertificateSha256 = $taskCertificateHashes[1]
    SameCertificateAsV22 = $true
    SignatureVerified = $true
    ZipAlignment16KiB = $true
    Elf64BitLoadAlignment16KiB = $true
    NotificationPermissionPresent = $true
    RebootReschedulingDeclared = $true
    ExactAlarmOrFullScreenPermissions = $false
    BroadGalleryOrStoragePermissions = $false
    CameraPermission = $false
    PreviewTestBannerPresentInAllABIs = $true
    PreviewBannerId = $taskTestBannerId
    Sha256 = $taskHash
    Bytes = (Get-Item -LiteralPath $taskDeliveredApk).Length
    DeviceRuntimeTested = $false
}
$taskReport | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskDelivery 'verificacion-android.json') -Encoding UTF8
$taskReport | ConvertTo-Json
