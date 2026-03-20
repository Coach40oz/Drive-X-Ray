# 🔍 Drive-X-Ray

**Advanced PowerShell Disk Space Analyzer with Enhanced GUI**

Drive-X-Ray is a comprehensive disk space analyzer that helps you understand what's consuming space on your drives. With its colorful, user-friendly console interface, it provides clear visibility into your file system — no additional software required.

---

## Features

- **High-Performance .NET Scanning** — Uses `[System.IO.Directory]::EnumerateFileSystemEntries()` for 3–5x faster scanning with automatic `Get-ChildItem` fallback
- **Adaptive Deep Scan** — Automatically adjusts scan depth (6–8 levels) based on drive size
- **Largest Files Detection** — Identifies files over 1 MB consuming your storage
- **Folder Space Usage** — Tracks folders over 5 MB with percentage-of-drive breakdowns
- **File Type Analysis** — Visual breakdown of space usage by extension with color-coded categories
- **Treemap Visualization** — Horizontal bar chart showing relative folder sizes at a glance
- **Post-Scan Menu** — Rescan, switch drives, or export results to CSV without restarting
- **CSV Export** — One-click export of file and folder results to your Desktop
- **Emoji Auto-Detection** — Uses emoji on PowerShell 7+ and ASCII fallbacks on older terminals
- **Dynamic Console Layout** — Adapts box widths and tables to your actual terminal size
- **Graceful Admin Handling** — Runs with or without Administrator privileges
- **Session-Clean** — Uses `$script:` scoping so nothing pollutes your PowerShell session after exit

## Requirements

- Windows operating system
- PowerShell 5.1 or higher
- Administrator privileges recommended for full system access (not required)

## Quick Start

### Option 1: Run Directly from GitHub

Run in an elevated PowerShell prompt:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Coach40oz/Drive-X-Ray/main/DriveX-Ray.ps1'))
```

### Option 2: One-Liner (PowerShell 7+)

```powershell
irm https://raw.githubusercontent.com/Coach40oz/Drive-X-Ray/main/DriveX-Ray.ps1 | iex
```

### Option 3: Download and Run Locally

```powershell
git clone https://github.com/Coach40oz/Drive-X-Ray.git
cd Drive-X-Ray
.\DriveX-Ray.ps1
```

> Right-click `DriveX-Ray.ps1` and select **Run with PowerShell**, or run as Administrator for full access.

## Usage

1. Launch Drive-X-Ray — it detects available drives and displays their usage
2. If not running as Administrator, you'll be prompted to continue with limited access
3. Select a drive letter to analyze
4. Wait for the scan to complete (a live spinner shows files/folders scanned)
5. Review the results:
   - **Treemap Visualization** — horizontal bar chart of the top 25 folders by size
   - **Largest Folders** — top 25 folders with size, % of drive, and depth
   - **Largest Files** — top 25 files with size, type, and last modified date
   - **File Type Analysis** — top 20 extensions by total size with visual distribution bars
6. Use the post-scan menu:

| Key | Action |
|-----|--------|
| `R` | Rescan the current drive |
| `D` | Scan a different drive |
| `E` | Export results to CSV on your Desktop |
| `Q` | Quit |

## Example Output

When you run Drive-X-Ray, you'll see:

- A colorful ASCII art banner
- Drive statistics with total, used, and free space via a visual progress bar
- Scan progress with a live spinner and file/folder counts
- Treemap visualization of folder sizes
- Tables showing largest folders and files sorted by size
- File extension analysis with color-coded type categories

> **Tip:** Add a screenshot to a `screenshots/` folder and uncomment the image line above — it makes a huge difference for repo engagement.

## Technical Details

| Component | Detail |
|-----------|--------|
| Scan Engine | .NET `EnumerateFileSystemEntries` with `Get-ChildItem` fallback |
| Performance | Deferred sorting — results collected during scan, sorted once at the end |
| Size Handling | All sizes use `[uint64]` to avoid overflow on multi-TB drives |
| Exclusions | `$Recycle.Bin`, `System Volume Information`, `Recovery`, `Config.Msi`, system page/swap files |
| Scoping | All state is `$script:` scoped — no global variable pollution |

## Contributing

Contributions, issues, and feature requests are welcome. Check the [issues page](https://github.com/Coach40oz/Drive-X-Ray/issues).

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

## Author

Created by [Ulises Paiz](https://github.com/Coach40oz)
