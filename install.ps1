# Installs the latest Switchr release for the current Windows user and starts the tray.
#
#   irm https://raw.githubusercontent.com/dominikzabcik/switchr/main/install.ps1 | iex
#
# To remove it again:
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/dominikzabcik/switchr/main/install.ps1))) -Uninstall
#
# No administrator rights: Switchr goes in %LOCALAPPDATA%\Programs\Switchr, on your PATH,
# in the Start menu, and opens at sign-in. -From installs from a folder holding a release zip and
# its SHA256SUMS instead of GitHub, for testing unpublished builds.
param([switch]$Uninstall, [string]$From, [switch]$NoStart)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = 'dominikzabcik/switchr'
$target = Join-Path $env:LOCALAPPDATA 'Programs\Switchr'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Switchr.lnk'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x86_64' }

$vt = $Host.UI.SupportsVirtualTerminal
function Paint([string]$text, [int[]]$rgb) {
  if ($vt) { "$([char]27)[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$text$([char]27)[0m" } else { $text }
}
$bone = 237, 231, 217
$amber = 207, 159, 87
$dim = 140, 158, 148
$rust = 214, 124, 108

# The block runs in this function's scope, so its parameter must not share a name with anything
# the steps use, such as $work.
function Step([string]$label, [scriptblock]$action) {
  Write-Host ('  ' + (Paint '━━━━━━━━━━━━' $dim) + '  ' + (Paint $label $dim)) -NoNewline
  try {
    & $action
  } catch {
    Write-Host ''
    Write-Host ('  ' + (Paint "$label failed: $($_.Exception.Message)" $rust))
    exit 1
  }
  Write-Host ("`r  " + (Paint '━━━━━━━━━━━━' $amber) + '  ' + $label + '   ')
}

function Stop-Tray {
  Get-Process -Name 'switchr-tray' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 400
}

function Set-UserPath([bool]$add) {
  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = @($current -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $target })
  if ($add) { $parts += $target }
  [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}

# The file for this computer: arm64 when the release has one, otherwise x86_64, which Windows on
# Arm runs too.
function Select-Zip($names) {
  $native = $names | Where-Object { $_ -like "switchr-*-windows-$arch.zip" } | Select-Object -First 1
  if ($native) { return $native }
  return $names | Where-Object { $_ -like 'switchr-*-windows-x86_64.zip' } | Select-Object -First 1
}

Write-Host ''
Write-Host ('  ' + (Paint 'Switchr' $bone) + '  ' + (Paint 'Your AI accounts, one click apart.' $dim))
Write-Host ''

if ($Uninstall) {
  Step 'Stopping the tray' { Stop-Tray }
  Step 'Removing Switchr' {
    Remove-ItemProperty -Path $runKey -Name 'Switchr' -ErrorAction SilentlyContinue
    if (Test-Path $shortcut) { Remove-Item $shortcut }
    Set-UserPath $false
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
  }
  Write-Host ''
  Write-Host ('  ' + (Paint 'Switchr is removed. Saved logins and usage history stay in' $dim) + " $env:LOCALAPPDATA\Switchr; run 'switchr reset' first to remove them too.")
  exit 0
}

if (-not [Environment]::Is64BitOperatingSystem) {
  Write-Host (Paint '  Switchr needs 64-bit Windows 10 or later.' $rust)
  exit 1
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("switchr-" + [Guid]::NewGuid())
New-Item -ItemType Directory $work | Out-Null
try {
  $script:zipName = $null
  $script:version = $null
  $archive = $null

  if ($From) {
    Step 'Reading the local release' {
      $folder = (Resolve-Path $From).Path
      $script:zipName = Select-Zip (Get-ChildItem $folder -Filter 'switchr-*-windows-*.zip').Name
      if (-not $script:zipName) { throw "No Windows zip in $folder." }
      Copy-Item (Join-Path $folder $script:zipName) $work
      Copy-Item (Join-Path $folder 'SHA256SUMS') $work
    }
  } else {
    Step 'Finding the latest release' {
      $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'switchr-installer' }
      $script:zipName = Select-Zip $release.assets.name
      if (-not $script:zipName) { throw "Release $($release.tag_name) has no Windows download." }
      $script:assets = $release.assets
    }
    Step "Downloading $script:zipName" {
      foreach ($name in $script:zipName, 'SHA256SUMS') {
        $asset = $script:assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $asset) { throw "The release has no $name." }
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile (Join-Path $work $name) -UseBasicParsing
      }
    }
  }
  $archive = Join-Path $work $script:zipName
  $script:version = ($script:zipName -replace '^switchr-', '') -replace '-windows-.*$', ''

  Step 'Verifying checksum' {
    $line = Get-Content (Join-Path $work 'SHA256SUMS') | Where-Object { $_ -match ('\s\*?' + [Regex]::Escape($script:zipName) + '\s*$') } | Select-Object -First 1
    if (-not $line) { throw "$script:zipName is not in the release checksums." }
    $expected = ($line -split '\s+')[0].ToLower()
    $actual = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLower()
    if ($expected -ne $actual) { throw 'The download does not match the release checksum.' }
  }

  Step "Installing Switchr $script:version" {
    Stop-Tray
    Expand-Archive -Path $archive -DestinationPath $work -Force
    $source = Get-ChildItem $work -Directory | Where-Object { $_.Name -like 'switchr-*' } | Select-Object -First 1
    if (-not $source) { throw 'The download has an unexpected layout.' }
    New-Item -ItemType Directory -Force $target | Out-Null
    Copy-Item (Join-Path $source.FullName '*') $target -Recurse -Force
    Set-UserPath $true

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = Join-Path $target 'switchr-tray.exe'
    $link.WorkingDirectory = $target
    $link.IconLocation = (Join-Path $target 'switchr.ico') + ',0'
    $link.Description = 'Switch Claude Code, Cursor and Codex accounts'
    $link.Save()

    Set-ItemProperty -Path $runKey -Name 'Switchr' -Value ('"' + (Join-Path $target 'switchr-tray.exe') + '"')
  }

  if (-not $NoStart) {
    Step 'Starting the tray' {
      Start-Process -FilePath (Join-Path $target 'switchr-tray.exe') -WorkingDirectory $target
    }
  }
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('  ' + (Paint 'Switchr is in the notification area.' $bone) + ' ' + (Paint 'Click the two tracks to switch accounts.' $dim))
Write-Host ('  ' + (Paint "Open a new terminal to use 'switchr'. It opens at sign-in; turn that off in its menu." $dim))
Write-Host ''
