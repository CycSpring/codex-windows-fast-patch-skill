[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$MsixPath,
  [string]$PackageName = 'OpenAI.Codex',
  [string]$CertThumbprint,
  [switch]$SkipCurrentUserTrust,
  [switch]$SkipLocalMachineTrust,
  [switch]$NoLaunch,
  [string]$StatusPath
)

$ErrorActionPreference = 'Stop'
$LogPrefix = '[codex-msix-install-helper]'

function Write-StatusLine {
  param([string]$Message)

  if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    return
  }

  $statusDir = Split-Path -Parent $StatusPath
  if ($statusDir) {
    New-Item -ItemType Directory -Force -Path $statusDir | Out-Null
  }
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "$timestamp $Message" | Add-Content -Path $StatusPath -Encoding UTF8
}

function Write-Log {
  param([string]$Message)

  Write-Host "$LogPrefix $Message"
  Write-StatusLine $Message
}

function Fail {
  param([string]$Message)

  throw "$LogPrefix error: $Message"
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-ExistingFile {
  param([string]$Path)

  $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $resolved) {
    Fail "file not found: $Path"
  }
  return $resolved.ProviderPath
}

function Get-MsixPublisher {
  param([string]$PackagePath)

  $tempDir = Join-Path $env:TEMP ('codex-msix-install-manifest-' + [guid]::NewGuid().ToString('N'))
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($PackagePath, $tempDir)
    $manifestPath = Join-Path $tempDir 'AppxManifest.xml'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
      Fail "AppxManifest.xml not found inside MSIX: $PackagePath"
    }
    [xml]$manifest = Get-Content -Raw -LiteralPath $manifestPath
    $publisher = [string]$manifest.Package.Identity.Publisher
    if ([string]::IsNullOrWhiteSpace($publisher)) {
      Fail "publisher not found in AppxManifest.xml: $manifestPath"
    }
    return $publisher
  } finally {
    if (Test-Path -LiteralPath $tempDir) {
      Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Find-CertificateByThumbprint {
  param([string]$Thumbprint)

  $normalized = ($Thumbprint -replace '\s+', '').ToUpperInvariant()
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return $null
  }

  $stores = @(
    'Cert:\CurrentUser\My',
    'Cert:\CurrentUser\TrustedPeople',
    'Cert:\CurrentUser\Root',
    'Cert:\LocalMachine\My',
    'Cert:\LocalMachine\TrustedPeople',
    'Cert:\LocalMachine\Root'
  )

  foreach ($store in $stores) {
    $cert = Get-ChildItem -LiteralPath $store -ErrorAction SilentlyContinue |
      Where-Object { $_.Thumbprint -eq $normalized } |
      Select-Object -First 1
    if ($cert) {
      return $cert
    }
  }

  return $null
}

function Find-CertificateByPublisher {
  param([string]$Publisher)

  $stores = @(
    'Cert:\CurrentUser\My',
    'Cert:\CurrentUser\TrustedPeople',
    'Cert:\CurrentUser\Root',
    'Cert:\LocalMachine\My',
    'Cert:\LocalMachine\TrustedPeople',
    'Cert:\LocalMachine\Root'
  )

  foreach ($store in $stores) {
    $cert = Get-ChildItem -LiteralPath $store -ErrorAction SilentlyContinue |
      Where-Object { $_.Subject -eq $Publisher } |
      Sort-Object NotAfter -Descending |
      Select-Object -First 1
    if ($cert) {
      return $cert
    }
  }

  return $null
}

function Trust-Certificate {
  param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)

  $tempCert = Join-Path $env:TEMP ('codex-msix-signing-' + $Cert.Thumbprint + '.cer')
  Export-Certificate -Cert $Cert -FilePath $tempCert -Force | Out-Null
  try {
    if (-not $SkipCurrentUserTrust) {
      Import-Certificate -FilePath $tempCert -CertStoreLocation Cert:\CurrentUser\TrustedPeople | Out-Null
      Import-Certificate -FilePath $tempCert -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
      Write-Log 'certificate imported into CurrentUser stores'
    }

    if (-not $SkipLocalMachineTrust) {
      if (Test-IsAdministrator) {
        Import-Certificate -FilePath $tempCert -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
        Import-Certificate -FilePath $tempCert -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
        Write-Log 'certificate imported into LocalMachine stores'
      } else {
        Write-Log 'not running as administrator; skipped LocalMachine certificate import'
      }
    }
  } finally {
    Remove-Item -LiteralPath $tempCert -Force -ErrorAction SilentlyContinue
  }
}

function Stop-PackageProcesses {
  param([string]$Name)

  $installed = Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $installed -or -not $installed.InstallLocation) {
    return
  }

  $installRoot = $installed.InstallLocation.TrimEnd('\')
  $processes = Get-Process -Name 'Codex' -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase)
  }
  foreach ($process in $processes) {
    Write-Log "stopping running package process pid=$($process.Id)"
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }
}

function Try-LaunchInstalledPackage {
  param([string]$Name)

  $installed = Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $installed -or -not $installed.InstallLocation) {
    Write-Log "installed package not found after Add-AppxPackage: $Name"
    return
  }

  $exe = Join-Path $installed.InstallLocation 'app\Codex.exe'
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    Write-Log "installed Codex executable not found: $exe"
    return
  }

  try {
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe)
    Write-Log "launched Codex from $exe"
  } catch {
    Write-Log "warning: package installed but launch failed: $($_.Exception.Message)"
  }
}

try {
  if (-not [string]::IsNullOrWhiteSpace($StatusPath)) {
    $statusDir = Split-Path -Parent $StatusPath
    if ($statusDir) {
      New-Item -ItemType Directory -Force -Path $statusDir | Out-Null
    }
    Set-Content -Path $StatusPath -Value '' -Encoding UTF8
  }

  $resolvedMsix = Resolve-ExistingFile $MsixPath
  Write-Log "install helper started: $resolvedMsix"

  $cert = $null
  if (-not [string]::IsNullOrWhiteSpace($CertThumbprint)) {
    $cert = Find-CertificateByThumbprint $CertThumbprint
    if (-not $cert) {
      Fail "certificate not found by thumbprint: $CertThumbprint"
    }
    Write-Log "using certificate thumbprint $($cert.Thumbprint)"
  } else {
    $publisher = Get-MsixPublisher $resolvedMsix
    Write-Log "detected package publisher: $publisher"
    $cert = Find-CertificateByPublisher $publisher
    if ($cert) {
      Write-Log "using certificate thumbprint $($cert.Thumbprint)"
    } else {
      Write-Log 'warning: matching signing certificate not found in local stores; proceeding without importing trust'
    }
  }

  if ($cert) {
    Trust-Certificate $cert
  }

  Stop-PackageProcesses $PackageName
  Add-AppxPackage -Path $resolvedMsix -ErrorAction Stop
  Write-Log 'patched MSIX installed'

  if (-not $NoLaunch) {
    Try-LaunchInstalledPackage $PackageName
  }

  Write-Log 'install helper completed'
} catch {
  Write-Log ('ERROR: ' + $_.Exception.Message)
  throw
}
