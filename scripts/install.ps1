$ErrorActionPreference = "Stop"

$repository = if ($env:ALFREDO_GITHUB_REPOSITORY) {
    $env:ALFREDO_GITHUB_REPOSITORY
} else {
    "faustobdls/alfredo"
}
$installDir = if ($env:ALFREDO_INSTALL_DIR) {
    $env:ALFREDO_INSTALL_DIR
} else {
    Join-Path $HOME ".alfredo\bin"
}

$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
if ($architecture -ne "X64") {
    throw "Unsupported Windows architecture: $architecture. The current release provides Windows x64."
}

$asset = "alfredo-windows-x64.zip"
$baseUrl = if ($env:ALFREDO_DOWNLOAD_BASE_URL) {
    $env:ALFREDO_DOWNLOAD_BASE_URL
} else {
    "https://github.com/$repository/releases/latest/download"
}
$baseUrl = $baseUrl.TrimEnd("/")
$temporaryDir = Join-Path ([System.IO.Path]::GetTempPath()) ("alfredo-" + [guid]::NewGuid())

try {
    New-Item -ItemType Directory -Path $temporaryDir | Out-Null
    $archive = Join-Path $temporaryDir $asset
    $checksums = Join-Path $temporaryDir "SHA256SUMS"

    Write-Host "Downloading $asset..."
    Invoke-WebRequest -Uri "$baseUrl/$asset" -OutFile $archive -UseBasicParsing
    Invoke-WebRequest -Uri "$baseUrl/SHA256SUMS" -OutFile $checksums -UseBasicParsing

    $checksumLine = Get-Content $checksums | Where-Object { $_ -match "\s+$([regex]::Escape($asset))$" } | Select-Object -First 1
    if (-not $checksumLine) {
        throw "No checksum found for $asset."
    }
    $expectedChecksum = ($checksumLine -split "\s+")[0].ToUpperInvariant()
    $actualChecksum = (Get-FileHash -Path $archive -Algorithm SHA256).Hash
    if ($actualChecksum -ne $expectedChecksum) {
        throw "Checksum verification failed for $asset."
    }

    Expand-Archive -Path $archive -DestinationPath $temporaryDir -Force
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Copy-Item -Path (Join-Path $temporaryDir "alfredo.exe") -Destination (Join-Path $installDir "alfredo.exe") -Force

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $normalizedInstallDir = $installDir.TrimEnd("\")
    $userPathContainsInstallDir = $false
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        foreach ($entry in @($userPath -split ";")) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }
            if ($entry.TrimEnd("\") -ieq $normalizedInstallDir) {
                $userPathContainsInstallDir = $true
                break
            }
        }
    }
    if (-not $userPathContainsInstallDir) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
            $installDir
        } else {
            "$($userPath.TrimEnd(';'));$installDir"
        }
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    }
    $processPathContainsInstallDir = $false
    if (-not [string]::IsNullOrWhiteSpace($env:Path)) {
        foreach ($entry in @($env:Path -split ";")) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }
            if ($entry.TrimEnd("\") -ieq $normalizedInstallDir) {
                $processPathContainsInstallDir = $true
                break
            }
        }
    }
    if (-not $processPathContainsInstallDir) {
        $env:Path = "$installDir;$env:Path"
    }

    Write-Host "Alfredo installed at $(Join-Path $installDir 'alfredo.exe')"
    Write-Host "The user PATH was updated. Open a new terminal to use alfredo."
} finally {
    if (Test-Path $temporaryDir) {
        Remove-Item -Path $temporaryDir -Recurse -Force
    }
}
