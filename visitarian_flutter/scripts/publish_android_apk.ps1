param(
  [string]$BuildOutputDir = "build\app\outputs\flutter-apk",
  [string]$PublishedFileName = "app-arm64-v8a-release.apk"
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$apkOutputDir = Join-Path $projectRoot $BuildOutputDir
$downloadsDir = Join-Path $projectRoot "web\downloads"
$publishedApkPath = Join-Path $downloadsDir $PublishedFileName

$candidateApks = @(
  "app-arm64-v8a-release.apk",
  "app-release.apk"
)

if (-not (Test-Path -LiteralPath $apkOutputDir)) {
  throw "APK output directory was not found: $apkOutputDir`nRun flutter build apk --release --split-per-abi first."
}

$sourceApkPath = $null
foreach ($candidate in $candidateApks) {
  $candidatePath = Join-Path $apkOutputDir $candidate
  if (Test-Path -LiteralPath $candidatePath) {
    $sourceApkPath = $candidatePath
    break
  }
}

if ($null -eq $sourceApkPath) {
  throw "No APK was found in $apkOutputDir. Expected one of: $($candidateApks -join ', ')"
}

if (-not (Test-Path -LiteralPath $downloadsDir)) {
  New-Item -ItemType Directory -Path $downloadsDir | Out-Null
}

Copy-Item -LiteralPath $sourceApkPath -Destination $publishedApkPath -Force

$fileSizeMb = [math]::Round((Get-Item -LiteralPath $publishedApkPath).Length / 1MB, 2)
Write-Host "Published APK: $publishedApkPath ($fileSizeMb MB)"
Write-Host "Expected download URL: https://www.visitarian.app/downloads/$PublishedFileName"
