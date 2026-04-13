param(
    [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$buildOutput = Join-Path $projectRoot "build/web"
$trackedVercelConfig = Join-Path $projectRoot "vercel.json"
$builtVercelConfig = Join-Path $buildOutput "vercel.json"
$rootVercelDir = Join-Path (Split-Path -Parent $projectRoot) ".vercel"
$buildVercelDir = Join-Path $buildOutput ".vercel"
$webEnvAsset = Join-Path $projectRoot "assets/config/web.env"
$resolvedEnvFile = Join-Path $projectRoot $EnvFile

Push-Location $projectRoot
try {
    if (-not (Test-Path $resolvedEnvFile)) {
        throw "Expected environment file at '$resolvedEnvFile', but it was not found."
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $webEnvAsset) -Force | Out-Null
    Copy-Item -LiteralPath $resolvedEnvFile -Destination $webEnvAsset -Force

    flutter build web --dart-define-from-file=$EnvFile

    if (-not (Test-Path $buildOutput)) {
        throw "Expected web build output at '$buildOutput', but it was not created."
    }

    Copy-Item -LiteralPath $trackedVercelConfig -Destination $builtVercelConfig -Force

    if (Test-Path $rootVercelDir) {
        New-Item -ItemType Directory -Path $buildVercelDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $rootVercelDir "project.json") -Destination (Join-Path $buildVercelDir "project.json") -Force
        Copy-Item -LiteralPath (Join-Path $rootVercelDir "README.txt") -Destination (Join-Path $buildVercelDir "README.txt") -Force
    }
    else {
        throw "Expected a linked Vercel project at '$rootVercelDir'. Run 'vercel link' from the repo root first."
    }

    Push-Location $buildOutput
    try {
        npx.cmd vercel deploy . --prod --yes
    }
    finally {
        Pop-Location
    }
}
finally {
    Pop-Location
}
