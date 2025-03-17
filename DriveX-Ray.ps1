#requires -RunAsAdministrator
<#
.SYNOPSIS
    DriveX-Ray - Advanced PowerShell Disk Space Analyzer with Enhanced GUI
.DESCRIPTION
    A comprehensive disk space analyzer that discovers large files and folders,
    identifies space usage patterns, and helps reclaim wasted disk space,
    all with an improved, user-friendly console interface.
.NOTES
    Author: Ulises Paiz
    Version: 1.0
#>

# Set console properties for better display
$Host.UI.RawUI.WindowTitle = "DriveX-Ray v1.0"
if ($Host.UI.RawUI.WindowSize.Width -lt 120) {
    try {
        $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(120, 40)
    } catch {
        Write-Host "Window size could not be adjusted automatically. For best experience, please maximize your terminal window." -ForegroundColor Yellow
    }
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
    
    # Calculate width based on the longest line in content plus padding
    $titleLength = $Title.Length
    $contentLength = ($Content | Measure-Object -Maximum -Property Length).Maximum
    $width = [Math]::Max($titleLength, $contentLength) + 6
    
    # Create top border with title
    Write-Host "┌─" -NoNewline -ForegroundColor $BorderColor
    Write-Host "".PadRight(($width - $Title.Length) / 2 - 2, "─") -NoNewline -ForegroundColor $BorderColor
    Write-Host " $Title " -NoNewline -ForegroundColor $TitleColor
    Write-Host "".PadRight(($width - $Title.Length) / 2 - 2, "─") -NoNewline -ForegroundColor $BorderColor
    Write-Host "─┐" -ForegroundColor $BorderColor
    
    # Create content lines
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
    
    # Create bottom border
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
    
    # Create the filled portion
    Write-Host "[" -NoNewline -ForegroundColor White
    if ($fillWidth -gt 0) {
        Write-Host "".PadRight($fillWidth, "■") -NoNewline -ForegroundColor $FillColor
    }
    
    # Create the empty portion
    if ($emptyWidth -gt 0) {
        Write-Host "".PadRight($emptyWidth, "□") -NoNewline -ForegroundColor $EmptyColor
    }
    
    # Close the progress bar
    Write-Host "]" -NoNewline -ForegroundColor White
    
    # Show percentage if requested
    if ($ShowPercent) {
        Write-Host " $PercentComplete%" -NoNewline -ForegroundColor Cyan
    }
}

function Format-FileSize {
    param (
        [uint64]$Size
    )

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
    
    $drivesContent = @(
        "The following drives are available for analysis:"
    )
    
    foreach ($drive in $drives) {
        $total = $drive.Used + $drive.Free
        $usedPercent = [Math]::Round(($drive.Used / $total) * 100, 1)
        $drivesContent += "$($drive.Name): - $(Format-FileSize $drive.Used) used (${usedPercent}%) of $(Format-FileSize $total)"
    }
    
    Show-InfoBox -Title "AVAILABLE DRIVES" -Content $drivesContent -BorderColor Yellow -TitleColor Green -ContentColor White
    
    return $drives
}

function Analyze-DriveSpace {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DriveLetter,
        
        [int]$MaxDepth = 3,
        
        [int]$TopFileCount = 20,
        
        [int]$TopFolderCount = 20,
        
        [array]$ExcludeFolders = @('$Recycle.Bin', 'System Volume Information', 'Windows', 'Program Files', 'Program Files (x86)')
    )
    
    # Format drive letter correctly
    if (-not $DriveLetter.EndsWith(":")) {
        $DriveLetter = "$($DriveLetter):"
    }
    
    $analysisStartContent = @(
        "Starting analysis of drive $DriveLetter",
        "This may take several minutes depending on drive size and activity",
        "Exclude folders: $($ExcludeFolders -join ', ')",
        "",
        "Please wait while we scan the drive..."
    )
    
    Show-InfoBox -Title "ANALYSIS STARTED" -Content $analysisStartContent -BorderColor Cyan -TitleColor Yellow
    
    $startTime = Get-Date
    
    # Get drive info
    $driveInfo = Get-PSDrive -Name $DriveLetter[0] -PSProvider FileSystem
    $totalSize = $driveInfo.Used + $driveInfo.Free
    $usedSpace = $driveInfo.Used
    $freeSpace = $driveInfo.Free
    $usedPercent = [Math]::Round(($usedSpace / $totalSize) * 100, 1)
    
    # Show drive stats
    $driveStatsContent = @(
        "Drive: $DriveLetter",
        "Total Size: $(Format-FileSize $totalSize)",
        "Used Space: $(Format-FileSize $usedSpace) ($usedPercent%)",
        "Free Space: $(Format-FileSize $freeSpace)",
        "",
        "Disk Space Usage:"
    )
    
    Show-InfoBox -Title "DRIVE STATISTICS" -Content $driveStatsContent -BorderColor Green -TitleColor Yellow
    
    # Display a visual representation of used/free space
    Write-Host " Used: " -NoNewline -ForegroundColor White
    Show-ProgressBar -PercentComplete $usedPercent -Width 50 -FillColor Cyan -EmptyColor DarkGray -ShowPercent
    Write-Host " Free: $(Format-FileSize $freeSpace)" -ForegroundColor Gray
    Write-Host ""
    
    # Initialize arrays to track largest files and folders
    $largestFiles = @()
    $largestFolders = @()
    $fileExtensionSizes = @{}
    
    # Function to analyze a directory and its subdirectories
    function Analyze-Directory {
        param (
            [string]$Path,
            [int]$CurrentDepth = 0,
            [int]$MaxDepth
        )
        
        if ($CurrentDepth -gt $MaxDepth) {
            return 0
        }
        
        $directorySize = 0
        $items = $null
        
        # Try to get items in the directory
        try {
            $items = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue
        } catch {
            # Skip directories we can't access
            return 0
        }
        
        # Process each item in the directory
        foreach ($item in $items) {
            # Skip excluded folders
            if ($item.PSIsContainer -and ($ExcludeFolders -contains $item.Name)) {
                continue
            }
            
            # If it's a file, add its size
            if (-not $item.PSIsContainer) {
                $directorySize += $item.Length
                
                # Track file extension statistics
                $extension = if ($item.Extension) { $item.Extension.ToLower() } else { "(no extension)" }
                if (-not $fileExtensionSizes.ContainsKey($extension)) {
                    $fileExtensionSizes[$extension] = @{
                        Size = 0
                        Count = 0
                    }
                }
                $fileExtensionSizes[$extension].Size += $item.Length
                $fileExtensionSizes[$extension].Count++
                
                # Track largest files
                $fileObject = [PSCustomObject]@{
                    Path = $item.FullName
                    Name = $item.Name
                    Extension = $extension
                    Size = $item.Length
                    SizeFormatted = Format-FileSize $item.Length
                    Created = $item.CreationTime
                    Modified = $item.LastWriteTime
                }
                
                # Add to largest files if array isn't full, or if larger than smallest entry
                if ($largestFiles.Count -lt $TopFileCount) {
                    $largestFiles += $fileObject
                    # Sort by size descending if we've just hit capacity
                    if ($largestFiles.Count -eq $TopFileCount) {
                        $script:largestFiles = $largestFiles | Sort-Object -Property Size -Descending
                    }
                } else {
                    # Check if current file is larger than the smallest in the array
                    if ($item.Length -gt $largestFiles[-1].Size) {
                        # Replace smallest file and resort
                        $largestFiles[-1] = $fileObject
                        $script:largestFiles = $largestFiles | Sort-Object -Property Size -Descending
                    }
                }
            }
            # If it's a directory, recursively analyze it
            else {
                $path = $item.FullName
                try {
                    $subdirSize = Analyze-Directory -Path $path -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
                    $directorySize += $subdirSize
                    
                    # Only track directories at depth level 1 or below (immediate children of the drive)
                    if ($CurrentDepth -le 1) {
                        $folderObject = [PSCustomObject]@{
                            Path = $item.FullName
                            Name = $item.Name
                            Size = $subdirSize
                            SizeFormatted = Format-FileSize $subdirSize
                            SizePercentage = if ($usedSpace -gt 0) { [Math]::Round(($subdirSize / $usedSpace) * 100, 1) } else { 0 }
                        }
                        
                        # Add to largest folders if array isn't full, or if larger than smallest entry
                        if ($largestFolders.Count -lt $TopFolderCount) {
                            $largestFolders += $folderObject
                            if ($largestFolders.Count -eq $TopFolderCount) {
                                $script:largestFolders = $largestFolders | Sort-Object -Property Size -Descending
                            }
                        } else {
                            if ($subdirSize -gt $largestFolders[-1].Size) {
                                $largestFolders[-1] = $folderObject
                                $script:largestFolders = $largestFolders | Sort-Object -Property Size -Descending
                            }
                        }
                    }
                } catch {
                    # Skip directories we can't access
                }
            }
            
            # Update progress indicator (simple spinning cursor)
            $cursorChars = '|', '/', '-', '\'
            $progressChar = $cursorChars[$script:progressCounter % $cursorChars.Length]
            $script:progressCounter++
            
            Write-Host "`r Scanning: $progressChar $Path" -NoNewline
        }
        
        return $directorySize
    }
    
    # Initialize progress counter
    $script:progressCounter = 0
    $script:largestFiles = $largestFiles
    $script:largestFolders = $largestFolders
    
    # Start the analysis
    $totalScannedSize = Analyze-Directory -Path "$DriveLetter\" -MaxDepth $MaxDepth
    
    # Clear the scanning line
    Write-Host "`r".PadRight(120, " ") -NoNewline
    Write-Host "`r"
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Format duration string
    $durationStr = ""
    if ($duration.Hours -gt 0) {
        $durationStr += "$($duration.Hours) hours, "
    }
    if ($duration.Minutes -gt 0) {
        $durationStr += "$($duration.Minutes) minutes, "
    }
    $durationStr += "$($duration.Seconds) seconds"
    
    $analysisCompleteContent = @(
        "Analysis of drive $DriveLetter complete",
        "Time taken: $durationStr",
        "Total scanned size: $(Format-FileSize $totalScannedSize)",
        "Analyzed file count: $($fileExtensionSizes.Values | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum)",
        "",
        "Note: Some files may have been skipped due to access restrictions."
    )
    
    Show-InfoBox -Title "ANALYSIS COMPLETE" -Content $analysisCompleteContent -BorderColor Green -TitleColor Yellow
    
    # Display the largest folders
    if ($largestFolders.Count -gt 0) {
        $largestFoldersContent = @(
            "The following folders consume the most space on drive ${DriveLetter}:"
        )
        
        Show-InfoBox -Title "LARGEST FOLDERS" -Content $largestFoldersContent -BorderColor Yellow -TitleColor Cyan
        
        # Create a table for displaying folders
        Write-Host "┌" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(5, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(60, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(10, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┐" -ForegroundColor Cyan
        
        # Header row
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " Rank" -NoNewline -ForegroundColor White
        Write-Host "".PadRight(1, " ") -NoNewline
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " Folder Path".PadRight(60, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " Size".PadRight(15, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " % of Drive".PadRight(10, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -ForegroundColor Cyan
        
        Write-Host "├" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(5, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(60, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(10, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┤" -ForegroundColor Cyan
        
        for ($i = 0; $i -lt $largestFolders.Count; $i++) {
            $folder = $largestFolders[$i]
            
            # Truncate path if too long
            $displayPath = if ($folder.Path.Length -gt 58) { 
                "$($folder.Path.Substring(0, 55))..." 
            } else { 
                $folder.Path 
            }
            
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $($i + 1)".PadRight(5, " ") -NoNewline -ForegroundColor Gray
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $displayPath".PadRight(60, " ") -NoNewline -ForegroundColor Green
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $($folder.SizeFormatted)".PadRight(15, " ") -NoNewline -ForegroundColor Yellow
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $($folder.SizePercentage)%".PadRight(10, " ") -NoNewline -ForegroundColor Magenta
            Write-Host "│" -ForegroundColor Cyan
        }
        
        Write-Host "└" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(5, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(60, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(10, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┘" -ForegroundColor Cyan
        
        Write-Host ""
    }
    
    # Display the largest files
    if ($largestFiles.Count -gt 0) {
        $largestFilesContent = @(
            "The following files are the largest on drive ${DriveLetter}:"
        )
        
        Show-InfoBox -Title "LARGEST FILES" -Content $largestFilesContent -BorderColor Yellow -TitleColor Cyan
        
        # Create a table for displaying files
        Write-Host "┌" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(5, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(50, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(10, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(20, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┐" -ForegroundColor Cyan
        
        # Header row
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " Rank" -NoNewline -ForegroundColor White
        Write-Host "".PadRight(1, " ") -NoNewline
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " File Path".PadRight(50, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " Type".PadRight(10, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " Size".PadRight(15, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " Modified".PadRight(20, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -ForegroundColor Cyan
        
        Write-Host "├" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(5, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(50, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(10, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(20, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┤" -ForegroundColor Cyan
        
        for ($i = 0; $i -lt $largestFiles.Count; $i++) {
            $file = $largestFiles[$i]
            
            # Truncate path if too long
            $displayPath = if ($file.Path.Length -gt 48) { 
                "$($file.Path.Substring(0, 45))..." 
            } else { 
                $file.Path 
            }
            
            # Determine file type color based on extension
            $typeColor = switch -Regex ($file.Extension) {
                "\.exe|\.dll|\.sys" { "Magenta" }
                "\.mp4|\.avi|\.mkv|\.mov" { "Yellow" }
                "\.jpg|\.png|\.gif|\.bmp" { "Green" }
                "\.zip|\.rar|\.7z" { "Cyan" }
                "\.iso|\.img" { "Red" }
                "\.doc|\.docx|\.xls|\.xlsx|\.ppt|\.pptx|\.pdf" { "Blue" }
                default { "Gray" }
            }
            
            $fileType = if ($file.Extension -eq "(no extension)") { 
                "(none)" 
            } else { 
                $file.Extension.TrimStart(".") 
            }
            
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $($i + 1)".PadRight(5, " ") -NoNewline -ForegroundColor Gray
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $displayPath".PadRight(50, " ") -NoNewline -ForegroundColor Green
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $fileType".PadRight(10, " ") -NoNewline -ForegroundColor $typeColor
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $($file.SizeFormatted)".PadRight(15, " ") -NoNewline -ForegroundColor Yellow
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $($file.Modified.ToString('yyyy-MM-dd HH:mm'))".PadRight(20, " ") -NoNewline -ForegroundColor DarkCyan
            Write-Host "│" -ForegroundColor Cyan
        }
        
        Write-Host "└" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(5, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(50, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(10, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(20, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┘" -ForegroundColor Cyan
        
        Write-Host ""
    }
    
    # Display file extension statistics
    if ($fileExtensionSizes.Count -gt 0) {
        $extensionStatsContent = @(
            "File types consuming the most space on drive ${DriveLetter}:"
        )
        
        Show-InfoBox -Title "FILE TYPE ANALYSIS" -Content $extensionStatsContent -BorderColor Magenta -TitleColor Yellow
        
        # Convert to array and sort by size
        $extensionStats = $fileExtensionSizes.GetEnumerator() | 
            ForEach-Object { 
                [PSCustomObject]@{
                    Extension = $_.Key
                    Size = $_.Value.Size
                    SizeFormatted = Format-FileSize $_.Value.Size
                    Count = $_.Value.Count
                    PercentOfDrive = if ($usedSpace -gt 0) { [Math]::Round(($_.Value.Size / $usedSpace) * 100, 1) } else { 0 }
                }
            } | Sort-Object -Property Size -Descending | Select-Object -First 15
        
        # Create a table for displaying extension stats
        Write-Host "┌" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(10, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┬" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(35, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┐" -ForegroundColor Cyan
        
        # Header row
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " Extension".PadRight(15, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " Total Size".PadRight(15, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " % of Drive".PadRight(10, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -NoNewline -ForegroundColor Cyan
        Write-Host " File Count".PadRight(35, " ") -NoNewline -ForegroundColor White
        Write-Host "│" -ForegroundColor Cyan
        
        Write-Host "├" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(10, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┼" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(35, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┤" -ForegroundColor Cyan
        
        foreach ($ext in $extensionStats) {
            # Determine file type color based on extension
            $typeColor = switch -Regex ($ext.Extension) {
                "\.exe|\.dll|\.sys" { "Magenta" }
                "\.mp4|\.avi|\.mkv|\.mov" { "Yellow" }
                "\.jpg|\.png|\.gif|\.bmp" { "Green" }
                "\.zip|\.rar|\.7z" { "Cyan" }
                "\.iso|\.img" { "Red" }
                "\.doc|\.docx|\.xls|\.xlsx|\.ppt|\.pptx|\.pdf" { "Blue" }
                default { "Gray" }
            }
            
            $displayExt = if ($ext.Extension -eq "(no extension)") { 
                $ext.Extension 
            } else { 
                $ext.Extension 
            }
            
            # Create a bar for visualizing file count
            $barWidth = [Math]::Min(30, [Math]::Max(1, [Math]::Round(($ext.Count / ($extensionStats | Measure-Object -Property Count -Maximum).Maximum) * 30)))
            $bar = "".PadRight($barWidth, "■")
            
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $displayExt".PadRight(15, " ") -NoNewline -ForegroundColor $typeColor
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $($ext.SizeFormatted)".PadRight(15, " ") -NoNewline -ForegroundColor Yellow
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $($ext.PercentOfDrive)%".PadRight(10, " ") -NoNewline -ForegroundColor Magenta
            Write-Host "│" -NoNewline -ForegroundColor Cyan
            Write-Host " $($ext.Count) " -NoNewline -ForegroundColor White
            Write-Host "$bar".PadRight(30, " ") -NoNewline -ForegroundColor $typeColor
            Write-Host "│" -ForegroundColor Cyan
        }
        
        Write-Host "└" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(15, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(10, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┴" -NoNewline -ForegroundColor Cyan
        Write-Host "".PadRight(35, "─") -NoNewline -ForegroundColor Cyan
        Write-Host "┘" -ForegroundColor Cyan
        
        Write-Host ""
    }
    
    # Return analysis data
    return @{
        DriveInfo = $driveInfo
        LargestFiles = $largestFiles
        LargestFolders = $largestFolders
        FileExtensionSizes = $fileExtensionSizes
        TotalScannedSize = $totalScannedSize
        ScanDuration = $duration
    }
}

function Show-AnimatedBanner {
    $banner = @"
                                                                                
 ██████╗ ██████╗ ██╗██╗   ██╗███████╗██╗  ██╗      ██████╗  █████╗ ██╗   ██╗
 ██╔══██╗██╔══██╗██║██║   ██║██╔════╝╚██╗██╔╝      ██╔══██╗██╔══██╗╚██╗ ██╔╝
 ██║  ██║██████╔╝██║██║   ██║█████╗   ╚███╔╝       ██████╔╝███████║ ╚████╔╝ 
 ██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝   ██╔██╗       ██╔══██╗██╔══██║  ╚██╔╝  
 ██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██╔╝ ██╗      ██║  ██║██║  ██║   ██║   
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝      ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
                                v1.0                                   
        Advanced PowerShell Disk Space Analyzer by Ulises Paiz
"@

    $rainbowColors = @(
        "Red", "Yellow", "Green", "Cyan", "Blue", "Magenta"
    )
    
    $lines = $banner -split "`n"
    
    foreach ($line in $lines) {
        $color = $rainbowColors[(Get-Random -Maximum $rainbowColors.Count)]
        Write-Host $line -ForegroundColor $color
        Start-Sleep -Milliseconds 50
    }
    
    # Create a fancy separator
    Write-Host "┌" -NoNewline -ForegroundColor Cyan
    for ($i = 0; $i -lt 118; $i++) {
        Start-Sleep -Milliseconds 5
        Write-Host "─" -NoNewline -ForegroundColor Cyan
    }
    Write-Host "┐" -ForegroundColor Cyan
}

function Show-Menu {
    Clear-Host
    Show-AnimatedBanner
    
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        $adminWarning = @(
            "This script is not running with administrator privileges.",
            "Some files and folders may not be accessible for analysis.",
            "Consider restarting the script as administrator for full functionality."
        )
        
        Show-InfoBox -Title "WARNING" -Content $adminWarning -BorderColor Red -TitleColor Yellow
        
        $continue = Read-Host "Continue anyway? (Y/N)"
        if ($continue -ne "Y" -and $continue -ne "y") {
            exit
        }
    }
    
    $scanOptions = @{
        MaxDepth = 3
        TopFileCount = 20
        TopFolderCount = 20
        ExcludeFolders = @('$Recycle.Bin', 'System Volume Information', 'Windows', 'Program Files', 'Program Files (x86)')
    }
    
    $menuActive = $true
    $lastScanResults = $null
    
    while ($menuActive) {
        Clear-Host
        Show-AnimatedBanner
        
        # Get available drives
        $drives = Get-AvailableDrives
        
        # Create a visually appealing settings display
        $settingsContent = @(
            "1. Max Directory Depth : $($scanOptions.MaxDepth) levels",
            "2. Top Files to Show   : $($scanOptions.TopFileCount)",
            "3. Top Folders to Show : $($scanOptions.TopFolderCount)",
            "4. Excluded Folders    : $($scanOptions.ExcludeFolders -join ', ')"
        )
        
        Show-InfoBox -Title "CURRENT SETTINGS" -Content $settingsContent -BorderColor Cyan -TitleColor Yellow
        
        # Actions menu
        $actionsContent = @(
            "S. Scan a Drive",
            "D. Change Max Directory Depth",
            "F. Change Number of Top Files",
            "O. Change Number of Top Folders",
            "E. Edit Excluded Folders",
            "A. About DiskSweep",
            "Q. Quit DiskSweep"
        )
        
        Show-InfoBox -Title "ACTIONS" -Content $actionsContent -BorderColor Cyan -TitleColor Green
        
        # Get user choice with highlighted prompt
        Write-Host "┌" -NoNewline -ForegroundColor Yellow
        Write-Host "".PadRight(118, "─") -NoNewline -ForegroundColor Yellow
        Write-Host "┐" -ForegroundColor Yellow
        
        Write-Host "│" -NoNewline -ForegroundColor Yellow
        Write-Host " Enter your choice: " -NoNewline -ForegroundColor White -BackgroundColor DarkBlue
        $choice = Read-Host
        Write-Host "".PadRight(102 - $choice.Length, " ") -NoNewline
        Write-Host "│" -ForegroundColor Yellow
        
        Write-Host "└" -NoNewline -ForegroundColor Yellow
        Write-Host "".PadRight(118, "─") -NoNewline -ForegroundColor Yellow
        Write-Host "┘" -ForegroundColor Yellow
        
        switch -Regex ($choice) {
            "1|[Dd]" {
                Clear-Host
                $depthTitle = "DIRECTORY DEPTH CONFIGURATION"
                $depthContent = @(
                    "Set the maximum directory depth to scan.",
                    "Higher values will scan deeper into the directory tree,",
                    "but will take longer to complete.",
                    "",
                    "Current value: $($scanOptions.MaxDepth)",
                    "Recommended range: 1-5 (3 is typically a good balance)",
                    ""
                )
                
                Show-InfoBox -Title $depthTitle -Content $depthContent -BorderColor Blue -TitleColor Cyan
                
                $depth = Read-Host "Enter max directory depth (1-10)"
                if ([int]::TryParse($depth, [ref]$null) -and [int]$depth -ge 1 -and [int]$depth -le 10) {
                    $scanOptions.MaxDepth = [int]$depth
                    
                    $depthUpdatedContent = @(
                        "Max directory depth updated to $($scanOptions.MaxDepth)"
                    )
                    
                    Show-InfoBox -Title "SETTING UPDATED" -Content $depthUpdatedContent -BorderColor Green -TitleColor White
                    Start-Sleep -Seconds 1
                } else {
                    $errorContent = @(
                        "Invalid input. Value must be between 1 and 10.",
                        "Keeping current value: $($scanOptions.MaxDepth)"
                    )
                    
                    Show-InfoBox -Title "INPUT ERROR" -Content $errorContent -BorderColor Red -TitleColor Yellow
                    Start-Sleep -Seconds 2
                }
            }
            "2|[Ff]" {
                Clear-Host
                $filesTitle = "TOP FILES CONFIGURATION"
                $filesContent = @(
                    "Set the number of largest files to display in results.",
                    "",
                    "Current value: $($scanOptions.TopFileCount)",
                    "Recommended range: 10-50",
                    ""
                )
                
                Show-InfoBox -Title $filesTitle -Content $filesContent -BorderColor Blue -TitleColor Cyan
                
                $fileCount = Read-Host "Enter number of top files to show (5-100)"
                if ([int]::TryParse($fileCount, [ref]$null) -and [int]$fileCount -ge 5 -and [int]$fileCount -le 100) {
                    $scanOptions.TopFileCount = [int]$fileCount
                    
                    $filesUpdatedContent = @(
                        "Top files count updated to $($scanOptions.TopFileCount)"
                    )
                    
                    Show-InfoBox -Title "SETTING UPDATED" -Content $filesUpdatedContent -BorderColor Green -TitleColor White
                    Start-Sleep -Seconds 1
                } else {
                    $errorContent = @(
                        "Invalid input. Value must be between 5 and 100.",
                        "Keeping current value: $($scanOptions.TopFileCount)"
                    )
                    
                    Show-InfoBox -Title "INPUT ERROR" -Content $errorContent -BorderColor Red -TitleColor Yellow
                    Start-Sleep -Seconds 2
                }
            }
            "3|[Oo]" {
                Clear-Host
                $foldersTitle = "TOP FOLDERS CONFIGURATION"
                $foldersContent = @(
                    "Set the number of largest folders to display in results.",
                    "",
                    "Current value: $($scanOptions.TopFolderCount)",
                    "Recommended range: 10-50",
                    ""
                )
                
                Show-InfoBox -Title $foldersTitle -Content $foldersContent -BorderColor Blue -TitleColor Cyan
                
                $folderCount = Read-Host "Enter number of top folders to show (5-100)"
                if ([int]::TryParse($folderCount, [ref]$null) -and [int]$folderCount -ge 5 -and [int]$folderCount -le 100) {
                    $scanOptions.TopFolderCount = [int]$folderCount
                    
                    $foldersUpdatedContent = @(
                        "Top folders count updated to $($scanOptions.TopFolderCount)"
                    )
                    
                    Show-InfoBox -Title "SETTING UPDATED" -Content $foldersUpdatedContent -BorderColor Green -TitleColor White
                    Start-Sleep -Seconds 1
                } else {
                    $errorContent = @(
                        "Invalid input. Value must be between 5 and 100.",
                        "Keeping current value: $($scanOptions.TopFolderCount)"
                    )
                    
                    Show-InfoBox -Title "INPUT ERROR" -Content $errorContent -BorderColor Red -TitleColor Yellow
                    Start-Sleep -Seconds 2
                }
            }
            "4|[Ee]" {
                Clear-Host
                $excludeTitle = "EXCLUDE FOLDERS CONFIGURATION"
                $excludeContent = @(
                    "Configure folders to exclude from analysis.",
                    "Excluding system folders can speed up analysis and focus on user data.",
                    "",
                    "Current excluded folders:",
                    "$($scanOptions.ExcludeFolders -join ', ')",
                    "",
                    "Options:",
                    "1. Reset to defaults",
                    "2. Add a folder to exclude",
                    "3. Remove a folder from exclusion list",
                    "4. Return to main menu",
                    ""
                )
                
                Show-InfoBox -Title $excludeTitle -Content $excludeContent -BorderColor Blue -TitleColor Cyan
                
                $excludeAction = Read-Host "Enter option (1-4)"
                
                switch ($excludeAction) {
                    "1" {
                        $scanOptions.ExcludeFolders = @('$Recycle.Bin', 'System Volume Information', 'Windows', 'Program Files', 'Program Files (x86)')
                        
                        $resetContent = @(
                            "Exclude folders reset to defaults:",
                            "$($scanOptions.ExcludeFolders -join ', ')"
                        )
                        
                        Show-InfoBox -Title "EXCLUSIONS RESET" -Content $resetContent -BorderColor Green -TitleColor White
                        Start-Sleep -Seconds 2
                    }
                    "2" {
                        $newFolder = Read-Host "Enter folder name to exclude"
                        if ($newFolder -and -not ($scanOptions.ExcludeFolders -contains $newFolder)) {
                            $scanOptions.ExcludeFolders += $newFolder
                            
                            $addedContent = @(
                                "Added '$newFolder' to exclusion list.",
                                "",
                                "Updated exclude list:",
                                "$($scanOptions.ExcludeFolders -join ', ')"
                            )
                            
                            Show-InfoBox -Title "FOLDER ADDED" -Content $addedContent -BorderColor Green -TitleColor White
                        } else {
                            $errorContent = @(
                                "Folder name invalid or already in exclusion list."
                            )
                            
                            Show-InfoBox -Title "INPUT ERROR" -Content $errorContent -BorderColor Red -TitleColor Yellow
                        }
                        Start-Sleep -Seconds 2
                    }
                    "3" {
                        Clear-Host
                        $removeTitle = "REMOVE EXCLUDED FOLDER"
                        $removeContent = @(
                            "Select a folder to remove from exclusion list:",
                            ""
                        )
                        
                        for ($i = 0; $i -lt $scanOptions.ExcludeFolders.Count; $i++) {
                            $removeContent += "$($i + 1). $($scanOptions.ExcludeFolders[$i])"
                        }
                        
                        Show-InfoBox -Title $removeTitle -Content $removeContent -BorderColor Yellow -TitleColor Cyan
                        
                        $removeIndex = Read-Host "Enter number of folder to remove (1-$($scanOptions.ExcludeFolders.Count))"
                        
                        if ([int]::TryParse($removeIndex, [ref]$null) -and [int]$removeIndex -ge 1 -and [int]$removeIndex -le $scanOptions.ExcludeFolders.Count) {
                            $removedFolder = $scanOptions.ExcludeFolders[[int]$removeIndex - 1]
                            $scanOptions.ExcludeFolders = $scanOptions.ExcludeFolders | Where-Object { $_ -ne $removedFolder }
                            
                            $removedContent = @(
                                "Removed '$removedFolder' from exclusion list.",
                                "",
                                "Updated exclude list:",
                                "$($scanOptions.ExcludeFolders -join ', ')"
                            )
                            
                            Show-InfoBox -Title "FOLDER REMOVED" -Content $removedContent -BorderColor Green -TitleColor White
                        } else {
                            $errorContent = @(
                                "Invalid selection."
                            )
                            
                            Show-InfoBox -Title "INPUT ERROR" -Content $errorContent -BorderColor Red -TitleColor Yellow
                        }
                        Start-Sleep -Seconds 2
                    }
                    "4" {
                        # Just return to menu
                    }
                    default {
                        $errorContent = @(
                            "Invalid option. Please enter a number from 1 to 4."
                        )
                        
                        Show-InfoBox -Title "INPUT ERROR" -Content $errorContent -BorderColor Red -TitleColor Yellow
                        Start-Sleep -Seconds 2
                    }
                }
            }
            "[Ss]" {
                Clear-Host
                
                $driveLetters = $drives | Select-Object -ExpandProperty Name
                
                $scanTitle = "SELECT DRIVE TO SCAN"
                $scanContent = @(
                    "Enter the drive letter to analyze (without colon):",
                    "",
                    "Available drives: $($driveLetters -join ', ')",
                    ""
                )
                
                Show-InfoBox -Title $scanTitle -Content $scanContent -BorderColor Magenta -TitleColor Yellow
                
                $selectedDrive = Read-Host "Drive letter"
                
                if ($selectedDrive -and $driveLetters -contains $selectedDrive.ToUpper()) {
                    $lastScanResults = Analyze-DriveSpace -DriveLetter $selectedDrive.ToUpper() -MaxDepth $scanOptions.MaxDepth -TopFileCount $scanOptions.TopFileCount -TopFolderCount $scanOptions.TopFolderCount -ExcludeFolders $scanOptions.ExcludeFolders
                    
                    $continueContent = @(
                        "Analysis complete.",
                        "",
                        "Press any key to return to the main menu..."
                    )
                    
                    Show-InfoBox -Title "DISK ANALYSIS COMPLETE" -Content $continueContent -BorderColor Green -TitleColor Yellow -Center
                    
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                } else {
                    $errorContent = @(
                        "Invalid drive selection.",
                        "Please select from: $($driveLetters -join ', ')"
                    )
                    
                    Show-InfoBox -Title "INPUT ERROR" -Content $errorContent -BorderColor Red -TitleColor Yellow
                    Start-Sleep -Seconds 2
                }
            }
            "[Aa]" {
                Clear-Host
                $aboutContent = @(
                    "DriveX-Ray v1.0",
                    "Advanced PowerShell Disk Space Analyzer",
                    "",
                    "Author: Ulises Paiz",
                    "License: GNU GPL v3",
                    "",
                    "Features:",
                    "- Analyze disk space usage on any drive",
                    "- Identify the largest files and folders",
                    "- View space usage by file type",
                    "- Interactive, user-friendly console interface",
                    "- Customizable scan depth and results",
                    "",
                    "DriveX-Ray helps you understand what's using space",
                    "on your drives, so you can make informed decisions",
                    "about what to keep, move, or delete.",
                    "",
                    "Press any key to return to the main menu..."
                )
                
                Show-InfoBox -Title "ABOUT DRIVE X-RAY" -Content $aboutContent -BorderColor Cyan -TitleColor Magenta -Center
                
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "[Qq]" {
                $menuActive = $false
            }
            default {
                $invalidContent = @(
                    "Invalid selection: $choice",
                    "Please choose a valid option from the menu."
                )
                
                Show-InfoBox -Title "INVALID CHOICE" -Content $invalidContent -BorderColor Red -TitleColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Main script execution
$banner = @"
                                                                                
 ██████╗ ██████╗ ██╗██╗   ██╗███████╗██╗  ██╗      ██████╗  █████╗ ██╗   ██╗
 ██╔══██╗██╔══██╗██║██║   ██║██╔════╝╚██╗██╔╝      ██╔══██╗██╔══██╗╚██╗ ██╔╝
 ██║  ██║██████╔╝██║██║   ██║█████╗   ╚███╔╝       ██████╔╝███████║ ╚████╔╝ 
 ██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝   ██╔██╗       ██╔══██╗██╔══██║  ╚██╔╝  
 ██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██╔╝ ██╗      ██║  ██║██║  ██║   ██║   
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝      ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
                                v1.0                                   
        Advanced PowerShell Disk Space Analyzer by Ulises Paiz
"@

Clear-Host
Write-Host $banner -ForegroundColor Cyan

# Check if running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "`n[WARNING] This script is not running with administrator privileges." -ForegroundColor Red
    Write-Host "Some files and folders may not be accessible for analysis." -ForegroundColor Yellow
    Write-Host "Consider restarting the script as administrator for full functionality.`n" -ForegroundColor Yellow
    
    $continue = Read-Host "Continue anyway? (Y/N)"
    if ($continue -ne "Y" -and $continue -ne "y") {
        exit
    }
}

# Show menu and start scanning
Show-Menu

# Farewell message with animation
$farewellContent = @(
    "",
    "Thank you for using DriveX-Ray!",
    "",
    "Press any key to exit..."
)

Show-InfoBox -Title "GOODBYE" -Content $farewellContent -BorderColor Cyan -TitleColor Magenta -Center

# Wait for a key press before exiting
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
