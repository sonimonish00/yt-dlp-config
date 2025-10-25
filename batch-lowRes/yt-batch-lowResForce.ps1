# Robust per-URL downloader (no goto/labels)
$URLFile = "YT-url.txt"
if (-not (Test-Path $URLFile)) {
    Write-Host "❌ File not found: $URLFile"
    exit 1
}

# Use android extractor to avoid SABR/nsig issues
$globalExtractorArgs = 'youtube:player_client=android'

# Read non-empty lines (skip blanks/comments)
$urls = Get-Content $URLFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') }
if ($urls.Count -eq 0) {
    Write-Host "No URLs found in $URLFile"
    exit 0
}

function Invoke-Download {
    param(
        [string]$InitialFormatSpec,
        [string]$Url
    )

    # Candidate attempts in order. Each has a FormatSpec and whether to use the android extractor.
    $attempts = @(
        @{ fmt = $InitialFormatSpec; useAndroid = $true; note = "Primary (with android extractor)" },
        @{ fmt = $InitialFormatSpec; useAndroid = $false; note = "Retry without android extractor" },
        @{ fmt = '18/best[height<=360]'; useAndroid = $false; note = "Fallback: 18 or best <=360" },
        @{ fmt = 'best[height<=360]'; useAndroid = $false; note = "Fallback: best <=360 (no explicit 18)" },
        @{ fmt = 'worst'; useAndroid = $false; note = "Ultimate fallback: worst quality" }
    )

    foreach ($att in $attempts) {
        $fmt = $att.fmt
        $useAndroid = $att.useAndroid
        $note = $att.note

        Write-Host ""
        Write-Host ("Attempt: {0}  | Format: {1}  | AndroidExtractor: {2}" -f $note, $fmt, $useAndroid)

        # Build options for this attempt
        $opts = @(
            '-f', $fmt,
            '--merge-output-format', 'mp4',
            '--downloader', 'aria2c',
            '--downloader-args', 'aria2c:-x 16 -k 5M -s 16 -j 16 -m 0',
            '-N', '8',
            '--http-chunk-size', '10M',
            '--cookies-from-browser', 'firefox',
            '-o', ("C:/Users/sonim/Downloads/%(title)s_{0}.%(ext)s" -f $fmt),
            $Url
        )

        # Add extractor-args if requested
        if ($useAndroid) {
            $opts = @('--extractor-args', $globalExtractorArgs) + $opts
        }

        # Run yt-dlp and capture output
        $procOutput = & yt-dlp @opts 2>&1
        $exit = $LASTEXITCODE
        # Print last few lines to give context
        $lastLines = ($procOutput -split "`n" | Select-Object -Last 10) -join "`n"
        Write-Host "ExitCode: $exit"
        Write-Host "Last output (trim):"
        Write-Host $lastLines

        if ($exit -eq 0) {
            Write-Host "✅ Download succeeded with format '$fmt' (attempt: $note)."
            return $true
        }
        else {
            # If failure message indicates "Requested format is not available" or "Only images are available" or extractor cookie skipping,
            # we will continue attempts. Otherwise continue as well but show output.
            if ($procOutput -match 'Requested format is not available' -or $procOutput -match 'Only images are available' -or $procOutput -match 'Skipping client "android"') {
                Write-Host "⚠️ Attempt failed with a format/availability issue; will try next fallback."
                # continue loop to next attempt
            }
            else {
                Write-Host "⚠️ Attempt failed (non-format error). Will try next fallback anyway."
            }
        }
    }

    Write-Host "❌ All attempts failed for $Url"
    return $false
}


foreach ($url in $urls) {
    Write-Host ""
    Write-Host ("=== Processing: {0} ===" -f $url)

    # Fetch JSON metadata for the URL
    Write-Host "Fetching formats (JSON)..."
    $jsonText = $null
    try {
        $jsonText = & yt-dlp '--extractor-args' $globalExtractorArgs '-J' '--no-warnings' $url 2>$null | Out-String
    }
    catch {
        Write-Host "⚠️ Failed to get JSON for $url : $_"
        Write-Host "Attempting conservative fallback download (format: 18/worst)..."
        Invoke-Download -FormatSpec '18/worst' -Url $url
        continue
    }

    # Parse JSON safely
    try {
        $meta = $jsonText | ConvertFrom-Json
    }
    catch {
        Write-Host "⚠️ JSON parse failed for $url. Falling back to selector '18/worst'."
        Invoke-Download -FormatSpec '18/worst' -Url $url
        continue
    }

    $formats = $meta.formats
    if (-not $formats) {
        Write-Host "⚠️ No formats found in metadata. Falling back to 'worst'."
        Invoke-Download -FormatSpec 'worst' -Url $url
        continue
    }

    # 1) Combined (video+audio) formats with height <= 360
    $combinedCandidates = $formats |
    Where-Object { ($_.vcodec -ne 'none') -and ($_.acodec -ne 'none') -and ($_.height -ne $null) -and ([int]$_.height -le 360) } |
    Sort-Object -Property @{Expression = { [int]$_.height }; Descending = $true }, @{Expression = { if ($_.filesize) { [int64]$_.filesize } else { 0 } }; Descending = $false }

    if ($combinedCandidates -and $combinedCandidates.Count -gt 0) {
        $selFormat = $combinedCandidates[0].format_id
        Write-Host ("Selected combined format: {0} (height {1})" -f $selFormat, $combinedCandidates[0].height)
        Invoke-Download -FormatSpec $selFormat -Url $url
        continue
    }

    # 2) Best video-only <=360 and best audio-only
    $videoOnlyCandidates = $formats |
    Where-Object { ($_.vcodec -ne 'none') -and ($_.acodec -eq 'none') -and ($_.height -ne $null) -and ([int]$_.height -le 360) } |
    Sort-Object -Property @{Expression = { [int]$_.height }; Descending = $true }, @{Expression = { if ($_.tbr) { [double]$_.tbr } else { 0 } }; Descending = $true }

    $audioOnlyCandidates = $formats |
    Where-Object { ($_.acodec -ne 'none') -and ($_.vcodec -eq 'none') } |
    Sort-Object -Property @{Expression = { if ($_.abr) { [double]$_.abr } else { 0 } }; Descending = $true }

    if (($videoOnlyCandidates -and $videoOnlyCandidates.Count -gt 0) -and ($audioOnlyCandidates -and $audioOnlyCandidates.Count -gt 0)) {
        $selFormat = "$($videoOnlyCandidates[0].format_id)+$($audioOnlyCandidates[0].format_id)"
        Write-Host ("Selected video+audio IDs: {0} (video height {1})" -f $selFormat, $videoOnlyCandidates[0].height)
        Invoke-Download -FormatSpec $selFormat -Url $url
        continue
    }

    # 3) Fallback to format 18 if present
    $f18 = $formats | Where-Object { $_.format_id -eq '18' }
    if ($f18) {
        Write-Host "Falling back to format 18."
        Invoke-Download -FormatSpec '18' -Url $url
        continue
    }

    # 4) Ultimate fallback to worst
    Write-Host ' No 360p candidates found — falling back to worst '
    Invoke-Download -FormatSpec 'worst' -Url $url
}

Write-Host ""
Write-Host '=== All URLs processed === '
