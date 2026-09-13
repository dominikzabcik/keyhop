# Builds the Windows release for this machine's architecture into build\windows\:
#   keyhop-<v>-windows-<x86_64|arm64>.zip   keyhop.exe, keyhop-tray.exe, the Swift runtime and the icon
# Run from a shell where `swift` works. KEYHOP_VERSION overrides the version in VERSION.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$version = if ($env:KEYHOP_VERSION) { $env:KEYHOP_VERSION } else { (Get-Content VERSION -Raw).Trim() }
$version = $version.TrimStart('v')
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x86_64' }

swift build -c release
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$bin = (swift build -c release --show-bin-path).Trim()

$out = 'build\windows'
$stage = Join-Path $out "keyhop-$version"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $stage | Out-Null

Copy-Item (Join-Path $bin 'Keyhop.exe') (Join-Path $stage 'keyhop.exe')
Copy-Item (Join-Path $bin 'KeyhopTray.exe') (Join-Path $stage 'keyhop-tray.exe')

# The Swift runtime DLLs, from the runtime folder the toolchain put on PATH.
$folders = $env:Path -split ';' | Where-Object { $_ -and (Test-Path (Join-Path $_ 'swiftCore.dll')) }
$runtime = ($folders | Where-Object { $_ -match 'Runtimes' } | Select-Object -First 1)
if (-not $runtime) { $runtime = $folders | Select-Object -First 1 }
if (-not $runtime) { throw 'Could not find the Swift runtime (swiftCore.dll) on PATH.' }
Write-Host "Swift runtime: $runtime"
Copy-Item (Join-Path $runtime '*.dll') $stage

# The Microsoft C++ runtime, which may ship beside an app.
foreach ($dll in 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll') {
  $path = Join-Path $env:SystemRoot "System32\$dll"
  if (Test-Path $path) { Copy-Item $path $stage }
}

Copy-Item packaging\windows\keyhop.ico $stage
Copy-Item LICENSE (Join-Path $stage 'LICENSE.txt')

& (Join-Path $stage 'keyhop.exe') version
if ($LASTEXITCODE) { throw 'The packaged keyhop.exe did not run.' }

# bsdtar writes forward slashes in entry names, which every unzip tool reads the same way.
tar.exe -a -c -f (Join-Path $out "keyhop-$version-windows-$arch.zip") -C $out "keyhop-$version"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Remove-Item -Recurse -Force $stage
Get-ChildItem $out
