param(
    [ValidateSet('Pub', 'Test', 'Analyze', 'Build', 'Dependencies')][string]$Mode = 'Test',
    [string[]]$TestTargets = @(),
    [string]$TestLog = 'tests-v25.txt'
)

# Local, isolated preview only. Uses the existing preview signing certificate.
$ErrorActionPreference = 'Stop'
$taskApp = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskRuntime = Join-Path (Split-Path $taskApp -Parent) 'undiamas-runtime'
$taskFlutter = Join-Path $taskRuntime 'flutter-3.32.8'
$taskJdk = 'C:\Users\Javi\Documents\MADE_WRONG\.local_tools\jdk-17'
$taskSdk = 'C:\Users\Javi\AppData\Local\Android\Sdk'
$taskLog = Join-Path $taskApp 'build\validation'
$taskEnv = @{
    JAVA_HOME = $taskJdk
    ANDROID_HOME = $taskSdk
    ANDROID_SDK_ROOT = $taskSdk
    ANDROID_USER_HOME = (Join-Path $taskRuntime 'android-user')
    GRADLE_USER_HOME = (Join-Path $taskRuntime 'gradle-home')
    GRADLE_RO_DEP_CACHE = 'C:\Users\Javi\.gradle\caches'
    PUB_CACHE = (Join-Path $taskRuntime 'pub-cache')
    APPDATA = (Join-Path $taskRuntime 'appdata')
    LOCALAPPDATA = (Join-Path $taskRuntime 'local-appdata')
    TEMP = (Join-Path $taskRuntime 'tmp')
    TMP = (Join-Path $taskRuntime 'tmp')
    JAVA_TOOL_OPTIONS = ('-Duser.home=' + (Join-Path $taskRuntime 'user-home') + ' -Djava.io.tmpdir=' + (Join-Path $taskRuntime 'tmp'))
    UDM_PREVIEW_KEYSTORE = 'C:\Users\Javi\.android\debug.keystore'
    FLUTTER_WINDOWS = 'false'
    FLUTTER_LINUX = 'false'
    FLUTTER_SUPPRESS_ANALYTICS = 'true'
    DART_SUPPRESS_ANALYTICS = 'true'
    FLUTTER_PREBUILT_ENGINE_VERSION = 'ef0cd000916d64fa0c5d09cc809fa7ad244a5767'
    PATH = (Join-Path $taskJdk 'bin') + ';' + (Join-Path $taskFlutter 'bin') + ';' + $env:PATH
}
$taskPrevious = @{}
$taskLocation = Get-Location
function Invoke-PhotoCommand {
    param([string]$Executable, [string[]]$Arguments, [string]$LogName)
    $taskPriorErrors = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Executable @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $taskLog $LogName)
        $taskExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $taskPriorErrors }
    if ($taskExit -ne 0) { throw "Command failed ($taskExit). See $LogName" }
}
try {
    [IO.Directory]::CreateDirectory($taskLog) | Out-Null
    foreach ($taskVariable in $taskEnv.Keys) {
        $taskPrevious[$taskVariable] = [Environment]::GetEnvironmentVariable($taskVariable, 'Process')
        [Environment]::SetEnvironmentVariable($taskVariable, $taskEnv[$taskVariable], 'Process')
    }
    Set-Location -LiteralPath $taskApp
    $taskFlutterCommand = Join-Path $taskFlutter 'bin\flutter.bat'
    if ($Mode -eq 'Pub') {
        Invoke-PhotoCommand $taskFlutterCommand @('config', '--no-enable-windows-desktop', '--no-enable-linux-desktop') 'config-v25.txt'
        Invoke-PhotoCommand $taskFlutterCommand @('pub', 'get', '--offline', '--enforce-lockfile') 'pub-v25.txt'
    }
    if ($Mode -eq 'Analyze') {
        Invoke-PhotoCommand $taskFlutterCommand @('analyze', '--no-pub', '--no-fatal-infos', '--no-fatal-warnings') 'analyze-v25.txt'
    }
    if ($Mode -eq 'Test') {
        Invoke-PhotoCommand $taskFlutterCommand (@('test', '--no-pub', '--concurrency=2', '--reporter', 'expanded') + $TestTargets) $TestLog
    }
    if ($Mode -eq 'Build' -or $Mode -eq 'Dependencies') {
        if (-not (Test-Path -LiteralPath $taskEnv.UDM_PREVIEW_KEYSTORE -PathType Leaf)) {
            throw 'The existing preview certificate is required; do not generate a replacement.'
        }
        $taskVersion = [regex]::Match((Get-Content -LiteralPath 'pubspec.yaml' -Raw), '(?m)^version:\s*([0-9.]+)\+([0-9]+)')
        if (-not $taskVersion.Success) { throw 'Missing version' }
        [IO.File]::WriteAllLines((Join-Path $taskApp 'android\local.properties'), @(
            'sdk.dir=' + $taskSdk.Replace('\', '/')
            'flutter.sdk=' + $taskFlutter.Replace('\', '/')
            'flutter.buildMode=release'
            'flutter.versionName=' + $taskVersion.Groups[1].Value
            'flutter.versionCode=' + $taskVersion.Groups[2].Value
        ), [Text.UTF8Encoding]::new($false))
        if ($Mode -eq 'Build') {
            $taskInputs = @(Get-ChildItem -LiteralPath 'lib','assets','android/app/src' -Recurse -File) +
                @(Get-Item -LiteralPath 'pubspec.yaml','pubspec.lock','android/app/build.gradle','android/build.gradle','android/settings.gradle','android/gradle.properties')
            $taskHashes = @($taskInputs | Sort-Object FullName | ForEach-Object {
                [ordered]@{ Path=$_.FullName.Substring($taskApp.Length + 1); SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
            })
            $taskHashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $taskLog 'source-before-build-v25.json') -Encoding UTF8
        }
        Set-Location -LiteralPath (Join-Path $taskApp 'android')
        $taskDefine = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('UDM_PREVIEW=true'))
        $taskBuildArguments = @(
            '--no-daemon', '--max-workers=2', '--console=plain',
            '-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m',
            '-Pkotlin.compiler.execution.strategy=in-process',
            '-Ptarget-platform=android-arm,android-arm64,android-x64',
            '-Ptarget=lib/main.dart', '-Pbase-application-name=android.app.Application',
            '-Pdart-obfuscation=false', '-Ptrack-widget-creation=true', '-Ptree-shake-icons=true',
            "-Pdart-defines=$taskDefine"
        )
        if ($Mode -eq 'Dependencies') {
            $taskBuildArguments += @(':app:dependencies', '--configuration', 'previewReleaseRuntimeClasspath')
        } else { $taskBuildArguments += 'assemblePreviewRelease' }
        Invoke-PhotoCommand (Join-Path $taskRuntime 'gradle-8.11.1\bin\gradle.bat') $taskBuildArguments "$Mode-v25.txt"
    }
} finally {
    Set-Location -LiteralPath $taskLocation
    foreach ($taskVariable in $taskPrevious.Keys) {
        [Environment]::SetEnvironmentVariable($taskVariable, $taskPrevious[$taskVariable], 'Process')
    }
}
