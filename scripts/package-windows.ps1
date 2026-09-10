# Builds the Windows release into build\windows\:
#   switchr-<v>-windows-x86_64.zip   switchr.exe, switchr-tray.exe, the Swift runtime and the icon
# Run from a shell where `swift` works. SWITCHR_VERSION overrides the version in VERSION.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$version = if ($env:SWITCHR_VERSION) { $env:SWITCHR_VERSION } else { (Get-Content VERSION -Raw).Trim() }
$version = $version.TrimStart('v')

swift build -c release
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$bin = (swift build -c release --show-bin-path).Trim()

$out = 'build\windows'
$stage = Join-Path $out "switchr-$version"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $stage | Out-Null

Copy-Item (Join-Path $bin 'Switchr.exe') (Join-Path $stage 'switchr.exe')
Copy-Item (Join-Path $bin 'SwitchrTray.exe') (Join-Path $stage 'switchr-tray.exe')

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

Copy-Item packaging\windows\switchr.ico $stage
Copy-Item LICENSE (Join-Path $stage 'LICENSE.txt')

& (Join-Path $stage 'switchr.exe') version
if ($LASTEXITCODE) { throw 'The packaged switchr.exe did not run.' }

# bsdtar writes forward slashes in entry names, which every unzip tool reads the same way.
tar.exe -a -c -f (Join-Path $out "switchr-$version-windows-x86_64.zip") -C $out "switchr-$version"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
Remove-Item -Recurse -Force $stage
Get-ChildItem $out
