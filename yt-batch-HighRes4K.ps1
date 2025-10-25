# -------------------------------
# YouTube Batch Downloader Script with Scoop/package management
# - Ensures Scoop is installed & up-to-date
# - Ensures aria2, ffmpeg, yt-dlp are installed & updated via scoop
# - Then runs yt-dlp using inline options (no separate config file)
# -------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Starting: Ensure Scoop and packages are installed/updated ===`n"

function Ensure-Scoop {
    Write-Host "Checking for scoop..."
    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue

    if (-not $scoopCmd) {
        Write-Host "Scoop not found. Installing scoop (this uses: irm get.scoop.sh | iex)..."
        try {
            # Install scoop (user requested form). This uses Invoke-RestMethod alias `irm`.
            irm 'https://get.scoop.sh' | iex
        }
        catch {
            Write-Host "❌ Failed to install scoop: $_"
            throw "Scoop installation failed. Aborting."
        }
        # Ensure the current session sees scoop shims immediately
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

    # Try to update scoop itself
    Write-Host "Updating scoop... (scoop update)"
    try {
        scoop update
    }
    catch {
        Write-Host "⚠️ 'scoop update' returned an error: $_"
        # not fatal — continue
    }

    # Optional: show scoop status (non-fatal)
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
    # Get installed package list and check presence
    $installed = $false
    try {
        $listOutput = scoop list 2>&1
        if ($listOutput -match ("^\s*{0}\s" -f [regex]::Escape($Name)) -or ($listOutput -match ("^\s*{0}\s" -f [regex]::Escape($Name)))) {
            $installed = $true
        }
        else {
            # Sometimes scoop list prints headers; fallback to substring
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
    # 1) Ensure scoop
    Ensure-Scoop

    # 2) Ensure packages (aria2, ffmpeg, yt-dlp) — in that order
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
# Now run yt-dlp (with inline options) against YT-url.txt
# --------------------

# Set the input text file path
$URLFile = "YT-url.txt"

Write-Host "Checking for URL file: $URLFile"
if (-not (Test-Path $URLFile)) {
    Write-Host "❌ File not found: $URLFile"
    exit 1
}

Write-Host "✅ URL file found. Preparing yt-dlp options..."

# Build yt-dlp options array
$ytOptions = @(
    # --- Format Selection ---
    '-f', 'bestvideo[height<=2160]+bestaudio/bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080][ext=mp4]',

    # Always merge into MP4
    '--merge-output-format', 'mp4',
    # --- Fix YouTube extractor ---
    # --extractor-args
    # youtube:player_client=default,-tv

    # --- Output Settings ---
    '-o', 'C:/Users/sonim/Downloads/%(title)s.%(ext)s',

    # --- Speed Optimizations ---
    '--downloader', 'aria2c',
    '--downloader-args', 'aria2c:-x 16 -k 5M -s 16 -j 16 -m 0',
    '-N', '8',
    '--http-chunk-size', '10M',

    # --- Authentication via cookies ---
    '--cookies-from-browser', 'firefox',

    # Input file
    '-a', $URLFile
)

# Run yt-dlp
Write-Host "Starting downloads with yt-dlp..."
try {
    # If the scoop-installed yt-dlp is available on PATH this will run it.
    & yt-dlp @ytOptions
}
catch {
    Write-Host "❌ Failed to run yt-dlp: $_"
    exit 1
}

Write-Host "`n=== All tasks complete ==="
