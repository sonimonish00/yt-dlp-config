Pre-requiste : python, ffmpeg \
[Guide](https://www.rapidseedbox.com/blog/yt-dlp-complete-guide)

Save Location : 
> Windows: C:\Users\sonim\yt-dlp.conf (Or see https://github.com/yt-dlp/yt-dlp/#configuration) \
> Linux/macOS: ~/.config/yt-dlp/config

Windows (PowerShell or Explorer): %APPDATA%\yt-dlp\config.txt (e.g., C:\Users\<YourName>\AppData\Roaming\yt-dlp\config.txt)

Script : New Config(4K then 1080p) + Throttle Fix. Download aria2c via scoop (powershell) - ask chatgpt \
**Update** : via pip bcz i installed via pip & python not python3 (CMD) : python -m pip install -U "yt-dlp[default]" \
For Batch Download via txt file : yt-dlp -a mylist.txt

