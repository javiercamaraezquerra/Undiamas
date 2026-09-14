$ErrorActionPreference = 'Stop'
$taskApp = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskRuntime = Join-Path (Split-Path $taskApp -Parent) 'undiamas-runtime'
$taskJava = 'C:\Users\Javi\Documents\MADE_WRONG\.local_tools\jdk-17\bin\java.exe'
$taskCache = 'C:\Users\Javi\.gradle\caches\modules-2\files-2.1'
function Get-TaskCachedJar([string]$relativeDirectory, [string]$fileName) {
    $taskMatches = @(Get-ChildItem -LiteralPath (Join-Path $taskCache $relativeDirectory) -Recurse -File -Filter $fileName)
    if ($taskMatches.Count -ne 1) { throw "Expected one cached dependency: $relativeDirectory/$fileName" }
    return $taskMatches[0].FullName
}
$taskCompiler = Get-TaskCachedJar 'org.jetbrains.kotlin\kotlin-compiler-embeddable\1.9.22' 'kotlin-compiler-embeddable-1.9.22.jar'
$taskStdlib = Get-TaskCachedJar 'org.jetbrains.kotlin\kotlin-stdlib\1.9.22' 'kotlin-stdlib-1.9.22.jar'
$taskScriptRuntime = Get-TaskCachedJar 'org.jetbrains.kotlin\kotlin-script-runtime\1.9.22' 'kotlin-script-runtime-1.9.22.jar'
$taskReflect = Get-TaskCachedJar 'org.jetbrains.kotlin\kotlin-reflect\1.6.10' 'kotlin-reflect-1.6.10.jar'
$taskTrove = Get-TaskCachedJar 'org.jetbrains.intellij.deps\trove4j\1.0.20200330' 'trove4j-1.0.20200330.jar'
$taskAnnotations = Get-TaskCachedJar 'org.jetbrains\annotations\13.0' 'annotations-13.0.jar'
$taskLogDirectory = Join-Path $taskApp 'build\validation'
$taskClasses = Join-Path $taskLogDirectory 'native-photo-policy-classes'
[IO.Directory]::CreateDirectory($taskClasses) | Out-Null
# The compiler version matches android/settings.gradle. The bundled Gradle
# cache supplies exactly the compiler's matching auxiliary JVM libraries.
# Avoid a Gradle lib wildcard: it discovers incompatible Kotlin scripting plugins.
$taskCompilerClasspath = "$taskCompiler;$taskStdlib;$taskScriptRuntime;$taskReflect;$taskTrove;$taskAnnotations"
$taskPolicy = Join-Path $taskApp 'android\app\src\main\kotlin\com\celsoriaapps\undiamas\PhotoImportPolicy.kt'
$taskTests = Join-Path $taskApp 'tool\native_photo_policy_test.kt'
'Compiling Kotlin photo policy with 1.9.22.' | Set-Content -LiteralPath (Join-Path $taskLogDirectory 'native-photo-policy-compile-v25.txt') -Encoding UTF8
& $taskJava -cp $taskCompilerClasspath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler `
    -no-stdlib -no-reflect -jvm-target 17 -classpath $taskStdlib -d $taskClasses $taskPolicy $taskTests `
    2>&1 | Tee-Object -Append -FilePath (Join-Path $taskLogDirectory 'native-photo-policy-compile-v25.txt')
if ($LASTEXITCODE -ne 0) { throw 'Kotlin photo policy compilation failed.' }
'Compilation passed.' | Add-Content -LiteralPath (Join-Path $taskLogDirectory 'native-photo-policy-compile-v25.txt') -Encoding UTF8
& $taskJava -cp "$taskClasses;$taskStdlib" com.celsoriaapps.undiamas.Native_photo_policy_testKt `
    2>&1 | Tee-Object -FilePath (Join-Path $taskLogDirectory 'native-photo-policy-tests-v25.txt')
if ($LASTEXITCODE -ne 0) { throw 'Native photo policy tests failed.' }

# Compile the actual Android plugin against the real API stubs and cached
# Flutter/Exif dependencies. This validates types, not Android bitmap behavior.
$taskAndroidJar = 'C:\Users\Javi\AppData\Local\Android\Sdk\platforms\android-36\android.jar'
$taskFlutterJar = Get-TaskCachedJar 'io.flutter\flutter_embedding_release\1.0.0-ef0cd000916d64fa0c5d09cc809fa7ad244a5767' 'flutter_embedding_release-1.0.0-ef0cd000916d64fa0c5d09cc809fa7ad244a5767.jar'
$taskExifFolder = Join-Path $taskRuntime 'gradle-home\caches\modules-2\files-2.1\androidx.exifinterface\exifinterface\1.3.7'
$taskExifAar = @(Get-ChildItem -LiteralPath $taskExifFolder -Recurse -File -Filter 'exifinterface-1.3.7.aar')[0].FullName
$taskExifJar = Join-Path $taskLogDirectory 'native-photo-exif-1.3.7.jar'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskExifArchive = [IO.Compression.ZipFile]::OpenRead($taskExifAar)
try {
    [IO.Compression.ZipFileExtensions]::ExtractToFile($taskExifArchive.GetEntry('classes.jar'), $taskExifJar, $true)
} finally {
    $taskExifArchive.Dispose()
}
$taskPlugin = Join-Path $taskApp 'android\app\src\main\kotlin\com\celsoriaapps\undiamas\PhotoImportPlugin.kt'
$taskPluginClasses = Join-Path $taskLogDirectory 'native-photo-plugin-classes'
[IO.Directory]::CreateDirectory($taskPluginClasses) | Out-Null
'Compiling Android photo plugin against API 36, Flutter and Exif.' | Set-Content -LiteralPath (Join-Path $taskLogDirectory 'native-photo-plugin-compile-v25.txt') -Encoding UTF8
& $taskJava -cp $taskCompilerClasspath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler `
    -no-stdlib -no-reflect -jvm-target 17 -classpath "$taskStdlib;$taskAndroidJar;$taskFlutterJar;$taskExifJar;$taskAnnotations" `
    -d $taskPluginClasses $taskPolicy $taskPlugin `
    2>&1 | Tee-Object -Append -FilePath (Join-Path $taskLogDirectory 'native-photo-plugin-compile-v25.txt')
if ($LASTEXITCODE -ne 0) { throw 'Android photo plugin compilation failed.' }
'Compilation passed.' | Add-Content -LiteralPath (Join-Path $taskLogDirectory 'native-photo-plugin-compile-v25.txt') -Encoding UTF8
'Android photo plugin compiled against API 36, Flutter embedding and Exif 1.3.7.'
