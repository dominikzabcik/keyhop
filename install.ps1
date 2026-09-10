# Installs the latest Switchr release for the current Windows user and starts the tray.
#
#   irm https://raw.githubusercontent.com/dominikzabcik/switchr/main/install.ps1 | iex
#
# To remove it again:
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/dominikzabcik/switchr/main/install.ps1))) -Uninstall
#
# No administrator rights: Switchr goes in %LOCALAPPDATA%\Programs\Switchr, on your PATH,
# in the Start menu, and opens at sign-in.
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = 'dominikzabcik/switchr'
$target = Join-Path $env:LOCALAPPDATA 'Programs\Switchr'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Switchr.lnk'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

$vt = $Host.UI.SupportsVirtualTerminal
function Paint([string]$text, [int[]]$rgb) {
  if ($vt) { "$([char]27)[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$text$([char]27)[0m" } else { $text }
}
$bone = 237, 231, 217
$amber = 207, 159, 87
$dim = 140, 158, 148
$rust = 214, 124, 108

function Step([string]$label, [scriptblock]$work) {
  Write-Host ('  ' + (Paint '━━━━━━━━━━━━' $dim) + '  ' + (Paint $label $dim)) -NoNewline
  try {
    & $work
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
  $release = $null
  $zip = $null
  Step 'Finding the latest release' {
    $script:release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'switchr-installer' }
    $script:zip = $script:release.assets | Where-Object { $_.name -like 'switchr-*-windows-x86_64.zip' } | Select-Object -First 1
    if (-not $script:zip) { throw "Release $($script:release.tag_name) has no Windows download." }
  }

  $archive = Join-Path $work $zip.name
  Step "Downloading Switchr $($release.tag_name.TrimStart('v'))" {
    Invoke-WebRequest -Uri $zip.browser_download_url -OutFile $archive -UseBasicParsing
    $sums = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1
    if (-not $sums) { throw 'The release has no checksum file.' }
    $listing = (Invoke-WebRequest -Uri $sums.browser_download_url -UseBasicParsing).Content
    if ($listing -is [byte[]]) { $listing = [Text.Encoding]::UTF8.GetString($listing) }
    $line = ($listing -split "`n") | Where-Object { $_ -match [Regex]::Escape($zip.name) + '\s*$' } | Select-Object -First 1
    if (-not $line) { throw "$($zip.name) is not in the release checksums." }
    $expected = ($line -split '\s+')[0].ToLower()
    $actual = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLower()
    if ($expected -ne $actual) { throw 'The download does not match the release checksum.' }
  }

  Step 'Installing' {
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

  Step 'Starting the tray' {
    Start-Process -FilePath (Join-Path $target 'switchr-tray.exe') -WorkingDirectory $target
  }
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('  ' + (Paint 'Switchr is in the notification area.' $bone) + ' ' + (Paint 'Click the two tracks to switch accounts.' $dim))
Write-Host ('  ' + (Paint "Open a new terminal to use 'switchr'. It opens at sign-in; turn that off in its menu." $dim))
Write-Host ''
