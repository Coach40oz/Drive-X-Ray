Drive-X-Ray
Advanced PowerShell Disk Space Analyzer with Enhanced GUI

DriveX-Ray is a comprehensive disk space analyzer tool that helps you understand what's consuming space on your drives. With its colorful, user-friendly console interface, DriveX-Ray provides clear visibility into your file system without requiring any additional software installation.

🔍 Features
High-Performance .NET Scanning: Uses [System.IO.Directory]::EnumerateFileSystemEntries() for 3-5x faster scanning with automatic Get-ChildItem fallback
Adaptive Deep Scan: Automatically adjusts scan depth (6-8 levels) based on drive size
Largest Files Detection: Identifies files over 1 MB consuming your storage
Folder Space Usage: Tracks folders over 5 MB with percentage-of-drive breakdowns
File Type Analysis: Visual breakdown of space usage by file extension with color-coded categories
Treemap Visualization: Horizontal bar chart showing relative folder sizes at a glance
Post-Scan Menu: Rescan, switch drives, or export results to CSV without restarting
CSV Export: One-click export of file and folder results to your Desktop
Emoji Auto-Detection: Uses emoji on PowerShell 7+ and ASCII fallbacks on older terminals
Dynamic Console Layout: Adapts box widths and tables to your actual terminal size
Graceful Admin Handling: Runs with or without Administrator privileges — prompts instead of refusing
Session-Clean: Uses $script: scoping so nothing pollutes your PowerShell session after exit
⚙️ Requirements
Windows operating system
PowerShell 5.1 or higher
Administrator privileges (recommended for full system access, but not required)
📥 Installation & Running
Method 1: Download and Run Locally
Clone or download this repository
Navigate to the folder containing the script
Right-click on DriveX-Ray.ps1 and select "Run with PowerShell" (or run as Administrator for full access)
Method 2: Run Directly from GitHub
Execute the following command in PowerShell (Run as Administrator for best results):


Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Coach40oz/Drive-X-Ray/main/DriveX-Ray.ps1'))
Method 3: One-liner for PowerShell 7+

irm https://raw.githubusercontent.com/Coach40oz/Drive-X-Ray/main/DriveX-Ray.ps1 | iex
🚀 Usage
Launch DriveX-Ray — it will detect available drives and display their usage
If not running as Administrator, you'll be prompted to continue with limited access
Select a drive letter to analyze
Wait for the scan to complete (a live spinner shows files/folders scanned)
Review the results:
Treemap Visualization — horizontal bar chart of top 25 folders by size
Largest Folders — top 25 folders with size, % of drive, and depth
Largest Files — top 25 files with size, type, and last modified date
File Type Analysis — top 20 extensions by total size with visual distribution bars
Use the post-scan menu:
[R] Rescan the current drive
[D] Scan a different drive
[E] Export results to CSV on your Desktop
[Q] Quit
📊 Example Output
When you run DriveX-Ray, you'll see:

A colorful ASCII art banner
Drive statistics showing total, used, and free space with a visual progress bar
Scan progress with a live spinner and file/folder counts
Treemap visualization of folder sizes
Tables showing largest folders and files sorted by size
File extension analysis with color-coded type categories
🛠️ Technical Details
Scan Engine: .NET EnumerateFileSystemEntries with Get-ChildItem fallback
Performance: Deferred sorting — results are collected during scan and sorted once at the end
Size Handling: All sizes use [uint64] to avoid overflow on large drives (multi-TB)
Exclusions: Automatically skips $Recycle.Bin, System Volume Information, Recovery, Config.Msi, and system page/swap files
Scoping: All state is $script: scoped — no global variable pollution
📝 License
This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.

👤 Author
Created by Ulises Paiz

🤝 Contributing
Contributions, issues, and feature requests are welcome! Feel free to check the issues page.
