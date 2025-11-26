# YouTube Batch Downloader Script with Scoop/package management
# (same header and package functions as before)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Starting: Ensure Scoop and packages are installed/updated ===`n"

function Ensure-Scoop {
    Write-Host "Checking for scoop..."
    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue

    if (-not $scoopCmd) {
        Write-Host "Scoop not found. Installing scoop (this uses: irm get.scoop.sh | iex)..."
        try {
            irm 'https://get.scoop.sh' | iex
        }
        catch {
            Write-Host "❌ Failed to install scoop: $_"
            throw "Scoop installation failed. Aborting."
        }

        $scoopShims = Join-Path $env:USERPROFILE 'scoop\shims'
        if (Test-Path $scoopShims) {
            Write-Host "Adding Scoop shims to PATH for current session: $scoopShims"
            $env:Path = "$env:Path;$scoopShims"
        }
        else {
            Write-Host "⚠️ Scoop installed but shims path not found at $scoopShims. You may need to open a new shell."
        }
    }
    else {
        Write-Host "Scoop is installed."
    }

    Write-Host "Updating scoop... (scoop update)"
    try {
        scoop update
    }
    catch {
        Write-Host "⚠️ 'scoop update' returned an error: $_"
    }

    try {
        Write-Host "Scoop status:"
        scoop status
    }
    catch {
        # not fatal
    }

    Write-Host "=== Scoop check/update done ===`n"
}

function Ensure-Package {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    Write-Host "Checking package: $Name ..."
    $installed = $false
    try {
        $listOutput = scoop list 2>&1
        if ($listOutput -match ("^\s*{0}\s" -f [regex]::Escape($Name)) -or ($listOutput -match [regex]::Escape($Name))) {
            $installed = $true
        }
        else {
            if ($listOutput -match [regex]::Escape($Name)) { $installed = $true }
        }
    }
    catch {
        Write-Host "⚠️ Could not query 'scoop list'. Error: $_"
    }

    if ($installed) {
        Write-Host "Package '$Name' appears installed. Attempting to update (scoop update $Name)..."
        try {
            scoop update $Name
            Write-Host "Updated '$Name' (or already at latest)."
        }
        catch {
            Write-Host "⚠️ 'scoop update $Name' failed: $_"
        }
    }
    else {
        Write-Host "Package '$Name' not installed. Installing (scoop install $Name)..."
        try {
            scoop install $Name
            Write-Host "Installed '$Name'."
        }
        catch {
            Write-Host "❌ Failed to install '$Name': $_"
            throw "Installation failed for $Name. Aborting."
        }
    }
    Write-Host ""
}

try {
    Ensure-Scoop

    $packages = @('aria2', 'ffmpeg', 'yt-dlp', 'deno')
    foreach ($pkg in $packages) {
        Ensure-Package -Name $pkg
    }

    Write-Host "=== All required packages ensured. Proceeding to downloads ===`n"
}
catch {
    Write-Host "Fatal error during setup: $_"
    exit 1
}

# --------------------
# Now process YT-url.txt and run yt-dlp per group
# --------------------

$URLFile = "YT-url.txt"
Write-Host "Checking for URL file: $URLFile"

if (-not (Test-Path $URLFile)) {
    Write-Host "❌ File not found: $URLFile"
    exit 1
}

Write-Host "✅ URL file found. Reading URLs..."

# Read and normalise URLs (ignore empty lines and comments)
$rawLines = Get-Content $URLFile -ErrorAction Stop
$urls = @()
foreach ($line in $rawLines) {
    $s = $line.Trim()
    if ($s -and -not $s.StartsWith("#")) { $urls += $s }
}

if ($urls.Count -eq 0) {
    Write-Host "No valid URLs found in $URLFile. Exiting."
    exit 1
}

# Playlist IDs to detect
$knowledgePlaylistId = "PLTu-XI3mX86plCmateVrSYj8-pqD7H89S"
$entertainmentPlaylistId = "PLTu-XI3mX86pe2JzkPdNh5h9zhL0g2LJh"

# Target directories
$baseDownload = "C:\Users\sonim\Downloads"
$knowledgeDir = Join-Path $baseDownload "YT-Knowledge"
$entertainmentDir = Join-Path $baseDownload "YT-Entertainment"
$defaultDir = $baseDownload

# Create group lists
$groups = @{
    Knowledge     = @()
    Entertainment = @()
    Default       = @()
}

foreach ($u in $urls) {
    if ($u -match [regex]::Escape($knowledgePlaylistId)) {
        $groups.Knowledge += $u
    }
    elseif ($u -match [regex]::Escape($entertainmentPlaylistId)) {
        $groups.Entertainment += $u
    }
    else {
        $groups.Default += $u
    }
}

# Prepare common yt-dlp base options (without '-o' or '-a')
# NOTE: removed '--verbose' to reduce yt-dlp verbosity; aria2c console level set to WARN
# ***** FIXED: aria2c args wrapped in quotes after 'aria2c:' so yt-dlp won't split them *****
$ytBaseOptions = @(
    '-f', 'bestvideo[height<=2160]+bestaudio/bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080][ext=mp4]',
    '--merge-output-format', 'mp4',
    '--downloader', 'aria2c',
    '--downloader-args', 'aria2c:"-x 16 -k 5M -s 16 -j 16 -m 0 --console-log-level=warn"',
    '-N', '8',
    '--http-chunk-size', '10M',
    '--cookies-from-browser', 'firefox',
    '--newline',    # forces progress lines to be printed line-by-line
    '--no-color'
)

# Brief diagnostics (one-line versions)
try { $ytv = & yt-dlp --version 2>$null; Write-Host "yt-dlp version: $ytv" } catch { Write-Host "yt-dlp: not found" }
try { $av = (& aria2c --version 2>$null | Select-Object -First 1); Write-Host "aria2c: $av" } catch { Write-Host "aria2c: not found" }
try { $fv = (& ffmpeg -version 2>$null | Select-Object -First 1); Write-Host "ffmpeg: $fv" } catch { Write-Host "ffmpeg: not found" }

Write-Host "-------------------------------`n"

# Helper function to run yt-dlp for a list of URLs into a specific output dir
function Run-YtDlP {
    param(
        [Parameter(Mandatory = $true)][string[]]$Urls,
        [Parameter(Mandatory = $true)][string]$OutputDir,
        [Parameter(Mandatory = $true)][string]$GroupName
    )

    if (-not (Test-Path $OutputDir)) {
        try {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
            Write-Host "Created output directory: $OutputDir"
        }
        catch {
            Write-Host "❌ Failed to create output directory $OutputDir : $_"
            return @{ Code = 1; Log = $null }
        }
    }

    # write urls to a temp file for -a
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        $Urls | Out-File -FilePath $tempFile -Encoding UTF8
    }
    catch {
        Write-Host "❌ Failed to write temporary URL file: $_"
        return @{ Code = 1; Log = $null }
    }

    $outputTemplate = (Join-Path $OutputDir '%(title)s.%(ext)s')

    # Build full options for this run as an array
    $localOpts = @()
    $localOpts += $ytBaseOptions
    $localOpts += '-o'
    $localOpts += $outputTemplate
    $localOpts += '-a'
    $localOpts += $tempFile

    # resolve yt-dlp exe
    try {
        $ytExe = (Get-Command yt-dlp -ErrorAction Stop).Source
    }
    catch {
        Write-Host "❌ Cannot find 'yt-dlp' in PATH. Please ensure yt-dlp is installed and available. Aborting run."
        Remove-Item $tempFile -ErrorAction SilentlyContinue
        return @{ Code = 1; Log = $null }
    }

    # concise start message (no argument dump)
    Write-Host "`nStarting group '$GroupName' : $($Urls.Count) URL(s) -> $OutputDir"
    Write-Host "Live progress will appear below (download speed, percent, ETA)."

    # run with argument array so quoting is correct and Start-Process writes to current console
    try {
        $proc = Start-Process -FilePath $ytExe -ArgumentList $localOpts -NoNewWindow -Wait -PassThru
        $rc = $proc.ExitCode
        if ($rc -eq 0) {
            Write-Host "✅ Group '$GroupName' finished (exit 0)."
        }
        else {
            Write-Host "⚠️ Group '$GroupName' exited with code $rc."
        }
    }
    catch {
        Write-Host "❌ Exception while running yt-dlp for group '$GroupName' : $_"
        $rc = 1
    }
    finally {
        try { Remove-Item $tempFile -ErrorAction SilentlyContinue } catch {}
    }

    return @{ Code = $rc; Log = $null }
}

# Run groups sequentially and collect results
$results = @{}

if ($groups.Knowledge.Count -gt 0) {
    $r = Run-YtDlP -Urls $groups.Knowledge -OutputDir $knowledgeDir -GroupName "Knowledge"
    $results.Knowledge = $r
}

if ($groups.Entertainment.Count -gt 0) {
    $r = Run-YtDlP -Urls $groups.Entertainment -OutputDir $entertainmentDir -GroupName "Entertainment"
    $results.Entertainment = $r
}

if ($groups.Default.Count -gt 0) {
    $r = Run-YtDlP -Urls $groups.Default -OutputDir $defaultDir -GroupName "Default"
    $results.Default = $r
}

# FINAL: All runs completed. Behavior: CLEAR THE WHOLE YT-url.txt ONLY IF ALL runs returned 0
$allOk = $true
if ($results.Count -eq 0) {
    Write-Host "`n⚠️ No groups were executed. YT-url.txt left unchanged."
    exit 1
}
foreach ($k in $results.Keys) {
    if ($results[$k].Code -ne 0) { $allOk = $false; break }
}

if ($allOk) {
    try {
        Clear-Content $URLFile
        Write-Host "`n✅ All yt-dlp runs succeeded. Cleared ALL entries from $URLFile."
    }
    catch {
        Write-Host "`n⚠️ All runs succeeded but failed to clear $URLFile $_"
    }
}
else {
    Write-Host "`n⚠️ One or more yt-dlp runs failed. NOT clearing $URLFile. Remaining URLs preserved for retry."
    # ***** FIXED: ensure $leftover is always an array so .Count is safe *****
    $leftover = @(Get-Content $URLFile | Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") })
    if ($leftover.Count -gt 0) {
        Write-Host "Remaining URLs in $URLFile ($($leftover.Count))"
        foreach ($l in $leftover) { Write-Host " - $l" }
    }
}

# Exit with aggregated status (0 if all runs 0, else 1)
if ($allOk) { exit 0 } else { exit 1 }
