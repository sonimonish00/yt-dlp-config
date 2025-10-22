# -------------------------------
# YouTube Batch Downloader Script
# Updates yt-dlp and aria2, then downloads videos from a text file
# -------------------------------

Write-Host "=== Updating yt-dlp and aria2 ==="

# Update yt-dlp via pip
python -m pip install -U "yt-dlp[default]"

# Update aria2 via scoop
scoop update aria2

Write-Host "=== Update complete. Starting downloads... ==="

# Set the input text file path
$URLFile = "YT-url.txt"

# Check if file exists
if (Test-Path $URLFile) {
    # Download all videos listed in the file
    yt-dlp -a $URLFile
} 
else {
    Write-Host "❌ File not found: $URLFile"
}

Write-Host "=== All tasks complete ==="