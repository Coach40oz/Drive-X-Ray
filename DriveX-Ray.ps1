#requires -RunAsAdministrator
<#
.SYNOPSIS
    DriveX-Ray - Fixed PowerShell Disk Space Analyzer (WinDirStat-like)
.DESCRIPTION
    A comprehensive disk space analyzer that discovers large files and folders,
    identifies space usage patterns with visual representations.
.NOTES
    Author: Fixed version
    Version: 1.1 - Fixed array handling and improved functionality
#>

# Set console properties for better display
$Host.UI.RawUI.WindowTitle = "DriveX-Ray v1.1 - Fixed"
if ($Host.UI.RawUI.WindowSize.Width -lt 120) {
    try {
        $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(120, 40)
    } catch {
        Write-Host "Window size could not be adjusted automatically. For best experience, please maximize your terminal window." -ForegroundColor Yellow
    }
}

# Global variables to track analysis
$Global:AnalysisResults = @{
    LargestFiles = [System.Collections.ArrayList]::new()
    LargestFolders = [System.Collections.ArrayList]::new()
    FileExtensions = @{}
    TotalScanned = 0
    FilesScanned = 0
}

function Show-InfoBox {
    param (
        [string]$Title,
        [string[]]$Content,
        [string]$BorderColor = "Cyan",
        [string]$TitleColor = "Yellow",
        [string]$ContentColor = "White",
        [switch]$Center
    )
    
    $titleLength = $Title.Length
    $contentLength = ($Content | Measure-Object -Maximum -Property Length).Maximum
    $width = [Math]::Max($titleLength, $contentLength) + 6
    
    # Top border with title
    Write-Host "┌─" -NoNewline -ForegroundColor $BorderColor
    Write-Host "".PadRight(($width - $Title.Length) / 2 - 2, "─") -NoNewline -ForegroundColor $BorderColor
    Write-Host " $Title " -NoNewline -ForegroundColor $TitleColor
    Write-Host "".PadRight(($width - $Title.Length) / 2 - 2, "─") -NoNewline -ForegroundColor $BorderColor
    Write-Host "─┐" -ForegroundColor $BorderColor
    
    # Content lines
    foreach ($line in $Content) {
        Write-Host "│ " -NoNewline -ForegroundColor $BorderColor
        
        if ($Center) {
            $padding = [Math]::Max(0, ($width - $line.Length - 4) / 2)
            Write-Host "".PadRight($padding, " ") -NoNewline
            Write-Host "$line" -NoNewline -ForegroundColor $ContentColor
            Write-Host "".PadRight($width - $line.Length - 4 - $padding, " ") -NoNewline
        } else {
            Write-Host "$line" -NoNewline -ForegroundColor $ContentColor
            Write-Host "".PadRight($width - $line.Length - 4, " ") -NoNewline
        }
        
        Write-Host " │" -ForegroundColor $BorderColor
    }
    
    # Bottom border
    Write-Host "└" -NoNewline -ForegroundColor $BorderColor
    Write-Host "".PadRight($width, "─") -NoNewline -ForegroundColor $BorderColor
    Write-Host "┘" -ForegroundColor $BorderColor
}

function Show-ProgressBar {
    param (
        [int]$PercentComplete,
        [int]$Width = 50,
        [string]$FillColor = "Green",
        [string]$EmptyColor = "DarkGray",
        [switch]$ShowPercent
    )
    
    $fillWidth = [Math]::Round(($PercentComplete / 100) * $Width)
    $emptyWidth = $Width - $fillWidth
    
    Write-Host "[" -NoNewline -ForegroundColor White
    if ($fillWidth -gt 0) {
        Write-Host "".PadRight($fillWidth, "■") -NoNewline -ForegroundColor $FillColor
    }
    
    if ($emptyWidth -gt 0) {
        Write-Host "".PadRight($emptyWidth, "□") -NoNewline -ForegroundColor $EmptyColor
    }
    
    Write-Host "]" -NoNewline -ForegroundColor White
    
    if ($ShowPercent) {
        Write-Host " $PercentComplete%" -NoNewline -ForegroundColor Cyan
    }
}

function Format-FileSize {
    param ([uint64]$Size)

    if ($Size -ge 1TB) {
        return "{0:N2} TB" -f ($Size / 1TB)
    } elseif ($Size -ge 1GB) {
        return "{0:N2} GB" -f ($Size / 1GB)
    } elseif ($Size -ge 1MB) {
        return "{0:N2} MB" -f ($Size / 1MB)
    } elseif ($Size -ge 1KB) {
        return "{0:N2} KB" -f ($Size / 1KB)
    } else {
        return "{0} Bytes" -f $Size
    }
}

function Get-AvailableDrives {
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and $_.Free -ne $null }
    
    $drivesContent = @("The following drives are available for analysis:")
    
    foreach ($drive in $drives) {
        $total = $drive.Used + $drive.Free
        $usedPercent = [Math]::Round(($drive.Used / $total) * 100, 1)
        $drivesContent += "$($drive.Name): - $(Format-FileSize $drive.Used) used (${usedPercent}%) of $(Format-FileSize $total)"
    }
    
    Show-InfoBox -Title "AVAILABLE DRIVES" -Content $drivesContent -BorderColor Yellow -TitleColor Green -ContentColor White
    return $drives
}

function Get-DirectorySize {
    param (
        [string]$Path,
        [int]$CurrentDepth = 0,
        [int]$MaxDepth = 3,
        [array]$ExcludeFolders = @(),
        [ref]$ProgressCounter
    )
    
    if ($CurrentDepth -gt $MaxDepth) {
        return 0
    }
    
    $directorySize = 0
    $items = $null
    
    try {
        $items = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue
    } catch {
        return 0
    }
    
    if (-not $items) {
        return 0
    }
    
    foreach ($item in $items) {
        try {
            # Update progress every 100 items
            $ProgressCounter.Value++
            if ($ProgressCounter.Value % 100 -eq 0) {
                $cursorChars = '|', '/', '-', '\'
                $progressChar = $cursorChars[($ProgressCounter.Value / 100) % $cursorChars.Length]
                Write-Host "`rScanning: $progressChar $($item.Name)" -NoNewline
            }
            
            # Skip excluded folders
            if ($item.PSIsContainer -and ($ExcludeFolders -contains $item.Name)) {
                continue
            }
            
            if (-not $item.PSIsContainer) {
                # It's a file
                $directorySize += $item.Length
                $Global:AnalysisResults.FilesScanned++
                
                # Track file extension statistics
                $extension = if ($item.Extension) { $item.Extension.ToLower() } else { "(no extension)" }
                if (-not $Global:AnalysisResults.FileExtensions.ContainsKey($extension)) {
                    $Global:AnalysisResults.FileExtensions[$extension] = @{
                        Size = [uint64]0
                        Count = 0
                    }
                }
                $Global:AnalysisResults.FileExtensions[$extension].Size += $item.Length
                $Global:AnalysisResults.FileExtensions[$extension].Count++
                
                # Track largest files (using ArrayList for better performance)
                $fileObject = [PSCustomObject]@{
                    Path = $item.FullName
                    Name = $item.Name
                    Extension = $extension
                    Size = [uint64]$item.Length
                    SizeFormatted = Format-FileSize $item.Length
                    Created = $item.CreationTime
                    Modified = $item.LastWriteTime
                }
                
                # Add to largest files list and keep it sorted
                if ($Global:AnalysisResults.LargestFiles.Count -lt 50 -or $item.Length -gt $Global:AnalysisResults.LargestFiles[-1].Size) {
                    [void]$Global:AnalysisResults.LargestFiles.Add($fileObject)
                    
                    # Sort and trim if necessary
                    if ($Global:AnalysisResults.LargestFiles.Count -gt 1) {
                        $sortedFiles = $Global:AnalysisResults.LargestFiles | Sort-Object -Property Size -Descending
                        $Global:AnalysisResults.LargestFiles.Clear()
                        
                        # Keep only top 50
                        for ($i = 0; $i -lt [Math]::Min(50, $sortedFiles.Count); $i++) {
                            [void]$Global:AnalysisResults.LargestFiles.Add($sortedFiles[$i])
                        }
                    }
                }
            } else {
                # It's a directory
                $subdirSize = Get-DirectorySize -Path $item.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -ExcludeFolders $ExcludeFolders -ProgressCounter $ProgressCounter
                $directorySize += $subdirSize
                
                # Track largest folders (only immediate children)
                if ($CurrentDepth -eq 0 -and $subdirSize -gt 0) {
                    $folderObject = [PSCustomObject]@{
                        Path = $item.FullName
                        Name = $item.Name
                        Size = [uint64]$subdirSize
                        SizeFormatted = Format-FileSize $subdirSize
                        SizePercentage = 0  # Will be calculated later
                    }
                    
                    # Add to largest folders list
                    if ($Global:AnalysisResults.LargestFolders.Count -lt 30 -or $subdirSize -gt $Global:AnalysisResults.LargestFolders[-1].Size) {
                        [void]$Global:AnalysisResults.LargestFolders.Add($folderObject)
                        
                        # Sort and trim if necessary
                        if ($Global:AnalysisResults.LargestFolders.Count -gt 1) {
                            $sortedFolders = $Global:AnalysisResults.LargestFolders | Sort-Object -Property Size -Descending
                            $Global:AnalysisResults.LargestFolders.Clear()
                            
                            # Keep only top 30
                            for ($i = 0; $i -lt [Math]::Min(30, $sortedFolders.Count); $i++) {
                                [void]$Global:AnalysisResults.LargestFolders.Add($sortedFolders[$i])
                            }
                        }
                    }
                }
            }
        } catch {
            # Skip items we can't access
            continue
        }
    }
    
    return $directorySize
}

function Show-TreemapVisualization {
    param (
        [array]$FolderData,
        [uint64]$TotalSize
    )
    
    if (-not $FolderData -or $FolderData.Count -eq 0) {
        return
    }
    
    Write-Host "`nDISK SPACE TREEMAP (Top Folders)" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    $maxBarWidth = 80
    $topFolders = $FolderData | Select-Object -First 20
    
    foreach ($folder in $topFolders) {
        $percentage = if ($TotalSize -gt 0) { ($folder.Size / $TotalSize) * 100 } else { 0 }
        $barWidth = [Math]::Max(1, [Math]::Round(($percentage / 100) * $maxBarWidth))
        
        # Color based on size
        $barColor = if ($percentage -gt 20) { "Red" }
                    elseif ($percentage -gt 10) { "Yellow" }
                    elseif ($percentage -gt 5) { "Green" }
                    else { "Cyan" }
        
        $bar = "".PadRight($barWidth, "█")
        $folderName = if ($folder.Name.Length -gt 25) { $folder.Name.Substring(0, 22) + "..." } else { $folder.Name }
        
        Write-Host ("{0,-25}" -f $folderName) -NoNewline -ForegroundColor White
        Write-Host " " -NoNewline
        Write-Host $bar -NoNewline -ForegroundColor $barColor
        Write-Host (" {0,8} ({1,5:F1}%)" -f $folder.SizeFormatted, $percentage) -ForegroundColor Gray
    }
}

function Analyze-DriveSpace {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DriveLetter,
        [int]$MaxDepth = 2,
        [array]$ExcludeFolders = @('$Recycle.Bin', 'System Volume Information', 'Windows', 'Program Files', 'Program Files (x86)')
    )
    
    # Format drive letter correctly
    if (-not $DriveLetter.EndsWith(":")) {
        $DriveLetter = "$($DriveLetter):"
    }
    
    # Reset global analysis results
    $Global:AnalysisResults.LargestFiles.Clear()
    $Global:AnalysisResults.LargestFolders.Clear()
    $Global:AnalysisResults.FileExtensions.Clear()
    $Global:AnalysisResults.TotalScanned = 0
    $Global:AnalysisResults.FilesScanned = 0
    
    Write-Host "`nStarting analysis of drive $DriveLetter..." -ForegroundColor Cyan
    Write-Host "This may take several minutes depending on drive size..." -ForegroundColor Yellow
    
    $startTime = Get-Date
    
    # Get drive info
    try {
        $driveInfo = Get-PSDrive -Name $DriveLetter[0] -PSProvider FileSystem
        $totalSize = $driveInfo.Used + $driveInfo.Free
        $usedSpace = $driveInfo.Used
        $freeSpace = $driveInfo.Free
        $usedPercent = if ($totalSize -gt 0) { [Math]::Round(($usedSpace / $totalSize) * 100, 1) } else { 0 }
    } catch {
        Write-Host "Error accessing drive $DriveLetter" -ForegroundColor Red
        return
    }
    
    # Show drive stats
    Write-Host "`n" -NoNewline
    Show-InfoBox -Title "DRIVE STATISTICS" -Content @(
        "Drive: $DriveLetter",
        "Total Size: $(Format-FileSize $totalSize)",
        "Used Space: $(Format-FileSize $usedSpace) ($usedPercent%)",
        "Free Space: $(Format-FileSize $freeSpace)"
    ) -BorderColor Green -TitleColor Yellow
    
    # Progress counter
    $progressCounter = [ref]0
    
    # Start the analysis
    Write-Host "`nScanning drive structure..." -ForegroundColor Cyan
    $totalScannedSize = Get-DirectorySize -Path "$DriveLetter\" -MaxDepth $MaxDepth -ExcludeFolders $ExcludeFolders -ProgressCounter $progressCounter
    
    # Clear the scanning line
    Write-Host "`r" + " " * 120 + "`r" -NoNewline
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Calculate percentages for folders
    foreach ($folder in $Global:AnalysisResults.LargestFolders) {
        $folder.SizePercentage = if ($usedSpace -gt 0) { [Math]::Round(($folder.Size / $usedSpace) * 100, 1) } else { 0 }
    }
    
    Write-Host "Analysis complete!" -ForegroundColor Green
    Write-Host "Time taken: $($duration.Minutes) minutes, $($duration.Seconds) seconds" -ForegroundColor Gray
    Write-Host "Files scanned: $($Global:AnalysisResults.FilesScanned)" -ForegroundColor Gray
    Write-Host "Total scanned size: $(Format-FileSize $totalScannedSize)" -ForegroundColor Gray
    
    # Show treemap visualization
    Show-TreemapVisualization -FolderData $Global:AnalysisResults.LargestFolders -TotalSize $usedSpace
    
    # Display the largest folders
    if ($Global:AnalysisResults.LargestFolders.Count -gt 0) {
        Write-Host "`n" -NoNewline
        Show-InfoBox -Title "LARGEST FOLDERS (Top 15)" -Content @("Space consumption by folder:") -BorderColor Yellow -TitleColor Cyan
        
        Write-Host "┌─────┬─────────────────────────────────────────────────────────┬─────────────────┬──────────┐" -ForegroundColor Cyan
        Write-Host "│ No. │ Folder Path                                             │ Size            │ % Drive  │" -ForegroundColor White
        Write-Host "├─────┼─────────────────────────────────────────────────────────┼─────────────────┼──────────┤" -ForegroundColor Cyan
        
        $topFolders = $Global:AnalysisResults.LargestFolders | Select-Object -First 15
        for ($i = 0; $i -lt $topFolders.Count; $i++) {
            $folder = $topFolders[$i]
            $displayPath = if ($folder.Path.Length -gt 55) { $folder.Path.Substring(0, 52) + "..." } else { $folder.Path }
            
            Write-Host ("│ {0,3} │ {1,-55} │ {2,15} │ {3,7:F1}% │" -f 
                ($i + 1), $displayPath, $folder.SizeFormatted, $folder.SizePercentage) -ForegroundColor Green
        }
        
        Write-Host "└─────┴─────────────────────────────────────────────────────────┴─────────────────┴──────────┘" -ForegroundColor Cyan
    }
    
    # Display the largest files
    if ($Global:AnalysisResults.LargestFiles.Count -gt 0) {
        Write-Host "`n" -NoNewline
        Show-InfoBox -Title "LARGEST FILES (Top 15)" -Content @("Individual files consuming the most space:") -BorderColor Yellow -TitleColor Cyan
        
        Write-Host "┌─────┬─────────────────────────────────────────────────────────┬─────────────────┬──────────┐" -ForegroundColor Cyan
        Write-Host "│ No. │ File Path                                               │ Size            │ Type     │" -ForegroundColor White
        Write-Host "├─────┼─────────────────────────────────────────────────────────┼─────────────────┼──────────┤" -ForegroundColor Cyan
        
        $topFiles = $Global:AnalysisResults.LargestFiles | Select-Object -First 15
        for ($i = 0; $i -lt $topFiles.Count; $i++) {
            $file = $topFiles[$i]
            $displayPath = if ($file.Path.Length -gt 55) { $file.Path.Substring(0, 52) + "..." } else { $file.Path }
            $fileType = if ($file.Extension -eq "(no extension)") { "(none)" } else { $file.Extension.TrimStart(".") }
            
            # Color by file type
            $typeColor = switch -Regex ($file.Extension) {
                "\.exe|\.dll|\.sys" { "Magenta" }
                "\.mp4|\.avi|\.mkv|\.mov" { "Yellow" }
                "\.jpg|\.png|\.gif|\.bmp" { "Green" }
                "\.zip|\.rar|\.7z" { "Cyan" }
                "\.iso|\.img" { "Red" }
                default { "Gray" }
            }
            
            Write-Host ("│ {0,3} │ " -f ($i + 1)) -NoNewline -ForegroundColor Gray
            Write-Host ("{0,-55}" -f $displayPath) -NoNewline -ForegroundColor Green
            Write-Host (" │ {0,15} │ " -f $file.SizeFormatted) -NoNewline -ForegroundColor Yellow
            Write-Host ("{0,-8}" -f $fileType) -NoNewline -ForegroundColor $typeColor
            Write-Host " │" -ForegroundColor Cyan
        }
        
        Write-Host "└─────┴─────────────────────────────────────────────────────────┴─────────────────┴──────────┘" -ForegroundColor Cyan
    }
    
    # Display file extension statistics
    if ($Global:AnalysisResults.FileExtensions.Count -gt 0) {
        Write-Host "`n" -NoNewline
        Show-InfoBox -Title "FILE TYPE ANALYSIS (Top 15)" -Content @("Space usage by file type:") -BorderColor Magenta -TitleColor Yellow
        
        $extensionStats = $Global:AnalysisResults.FileExtensions.GetEnumerator() | 
            ForEach-Object { 
                [PSCustomObject]@{
                    Extension = $_.Key
                    Size = $_.Value.Size
                    SizeFormatted = Format-FileSize $_.Value.Size
                    Count = $_.Value.Count
                    PercentOfDrive = if ($usedSpace -gt 0) { [Math]::Round(($_.Value.Size / $usedSpace) * 100, 1) } else { 0 }
                }
            } | Sort-Object -Property Size -Descending | Select-Object -First 15
        
        Write-Host "┌─────────────────┬─────────────────┬──────────┬─────────────────────────────────┐" -ForegroundColor Cyan
        Write-Host "│ Extension       │ Total Size      │ % Drive  │ File Count                      │" -ForegroundColor White
        Write-Host "├─────────────────┼─────────────────┼──────────┼─────────────────────────────────┤" -ForegroundColor Cyan
        
        foreach ($ext in $extensionStats) {
            $displayExt = if ($ext.Extension -eq "(no extension)") { $ext.Extension } else { $ext.Extension }
            
            # Create a bar for visualizing file count
            $maxCount = ($extensionStats | Measure-Object -Property Count -Maximum).Maximum
            $barWidth = if ($maxCount -gt 0) { [Math]::Min(25, [Math]::Max(1, [Math]::Round(($ext.Count / $maxCount) * 25))) } else { 1 }
            $bar = "".PadRight($barWidth, "█")
            
            $typeColor = switch -Regex ($ext.Extension) {
                "\.exe|\.dll|\.sys" { "Magenta" }
                "\.mp4|\.avi|\.mkv|\.mov" { "Yellow" }
                "\.jpg|\.png|\.gif|\.bmp" { "Green" }
                "\.zip|\.rar|\.7z" { "Cyan" }
                "\.iso|\.img" { "Red" }
                default { "Gray" }
            }
            
            Write-Host ("│ {0,-15} │ {1,15} │ {2,7:F1}% │ {3,6} " -f 
                $displayExt, $ext.SizeFormatted, $ext.PercentOfDrive, $ext.Count) -NoNewline -ForegroundColor $typeColor
            Write-Host $bar.PadRight(25, " ") -NoNewline -ForegroundColor $typeColor
            Write-Host "│" -ForegroundColor Cyan
        }
        
        Write-Host "└─────────────────┴─────────────────┴──────────┴─────────────────────────────────┘" -ForegroundColor Cyan
    }
    
    return @{
        DriveInfo = $driveInfo
        TotalScannedSize = $totalScannedSize
        ScanDuration = $duration
    }
}

function Show-MainMenu {
    Clear-Host
    
    $banner = @"
 ██████╗ ██████╗ ██╗██╗   ██╗███████╗██╗  ██╗      ██████╗  █████╗ ██╗   ██╗
 ██╔══██╗██╔══██╗██║██║   ██║██╔════╝╚██╗██╔╝      ██╔══██╗██╔══██╗╚██╗ ██╔╝
 ██║  ██║██████╔╝██║██║   ██║█████╗   ╚███╔╝       ██████╔╝███████║ ╚████╔╝ 
 ██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝   ██╔██╗       ██╔══██╗██╔══██║  ╚██╔╝  
 ██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██╔╝ ██╗      ██║  ██║██║  ██║   ██║   
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝      ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
                              v1.1 FIXED - WinDirStat Style
"@

    Write-Host $banner -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    # Check admin privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host "⚠️  WARNING: Not running as administrator - some files may be inaccessible" -ForegroundColor Yellow
        Write-Host ""
    }
    
    # Get and display available drives
    $drives = Get-AvailableDrives
    $driveLetters = $drives | Select-Object -ExpandProperty Name
    
    Write-Host "`nSelect a drive to analyze:" -ForegroundColor Green
    Write-Host "Available drives: " -NoNewline -ForegroundColor White
    Write-Host ($driveLetters -join ", ") -ForegroundColor Cyan
    Write-Host "Enter 'Q' to quit" -ForegroundColor Gray
    Write-Host ""
    
    $selectedDrive = Read-Host "Drive letter"
    
    if ($selectedDrive -eq "Q" -or $selectedDrive -eq "q") {
        Write-Host "Goodbye!" -ForegroundColor Cyan
        return
    }
    
    if ($selectedDrive -and $driveLetters -contains $selectedDrive.ToUpper()) {
        Analyze-DriveSpace -DriveLetter $selectedDrive.ToUpper()
        
        Write-Host "`n`nPress any key to return to menu or 'Q' to quit..." -ForegroundColor Yellow
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Q') {
            Write-Host "Goodbye!" -ForegroundColor Cyan
            return
        } else {
            Show-MainMenu
        }
    } else {
        Write-Host "Invalid drive selection. Please try again." -ForegroundColor Red
        Start-Sleep -Seconds 2
        Show-MainMenu
    }
}

# Main execution
Show-MainMenu
