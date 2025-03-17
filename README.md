# Drive-X-Ray

Advanced PowerShell Disk Space Analyzer with Enhanced GUI

DriveX-Ray is a comprehensive disk space analyzer tool that helps you understand what's consuming space on your drives. With its colorful, user-friendly console interface, DriveX-Ray provides clear visibility into your file system without requiring any additional software installation.

## 🔍 Features

- **Comprehensive Drive Analysis**: Scan any drive to discover what's taking up space
- **Largest Files Detection**: Identify the biggest files consuming your precious storage 
- **Folder Space Usage**: See which folders are the biggest space consumers
- **File Type Analysis**: Break down space usage by file extension
- **Interactive Console UI**: Colorful, easy-to-read interface with progress indicators
- **Customizable Scanning**: Adjust scan depth, result counts, and exclude specific folders
- **Administrator-Friendly**: Run with elevated permissions for complete system access

## ⚙️ Requirements

- Windows operating system
- PowerShell 5.1 or higher
- Administrator privileges (recommended for full system access)

## 📥 Installation & Running

### Method 1: Download and Run Locally

1. Clone or download this repository
2. Navigate to the folder containing the script
3. Right-click on `DriveX-Ray.ps1` and select "Run with PowerShell" (or run as Administrator for full access)

### Method 2: Run Directly from GitHub

Execute the following command in PowerShell (Run as Administrator for best results):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Coach40oz/Drive-X-Ray/main/DriveX-Ray.ps1'))
```

### Method 3: One-liner for PowerShell 7+ 

```powershell
irm https://raw.githubusercontent.com/Coach40oz/Drive-X-Ray/main/DriveX-Ray.ps1 | iex
```

## 🚀 Usage

1. After launching DriveX-Ray, you'll see the main menu with available drives
2. Configure scan options or proceed with defaults:
   - Max Directory Depth: Controls how deep the scan goes (default: 3)
   - Top Files to Show: Number of largest files to display (default: 20)
   - Top Folders to Show: Number of largest folders to display (default: 20)
   - Excluded Folders: System folders that are skipped during scan
3. Select "Scan a Drive" and choose the drive letter to analyze
4. Wait for the scan to complete (time depends on drive size and selected depth)
5. Review the detailed results showing:
   - Largest folders with size and percentage of drive space
   - Largest files with size, type, and last modified date
   - File types consuming the most space with visual indicators

## 📊 Example Output

When you run DriveX-Ray, you'll see:

1. A colorful ASCII art banner
2. Drive statistics showing total, used, and free space
3. Visual representation of disk usage
4. Tables showing largest folders sorted by size
5. Tables showing largest files with type information
6. File extension analysis showing which types of files use the most space

## 🛠️ Configuration

You can configure the following settings from the menu:

- **Max Directory Depth**: Higher values scan deeper but take longer (1-10)
- **Top Files/Folders to Show**: Adjust the number of results displayed (5-100)
- **Excluded Folders**: Add or remove folders from the exclusion list

## 📝 License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.

## 👤 Author

Created by Ulises Paiz

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page.
