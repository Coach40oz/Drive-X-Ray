#requires -RunAsAdministrator
<#
.SYNOPSIS
    DriveX-Ray - Clean Visual Disk Space Analyzer with Simple Interface
.DESCRIPTION
    A comprehensive disk space analyzer with beautiful visuals and clean user experience.
.NOTES
    Author: Clean UX Version  
    Version: 2.1 - Fixed UX issues, clean scanning, proper exit
#>

# Set console properties for optimal display
$Host.UI.RawUI.WindowTitle = "DriveX-Ray v2.1 - Clean UX Edition"
if ($Host.UI.RawUI.WindowSize.Width -lt 130) {
    try {
        $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(130, 45)
    } catch {
        Write-Host "Window size adjustment failed. Please maximize your terminal for best experience." -ForegroundColor Yellow
    }
}

# Global tracking variables
$Global:AnalysisResults = @{
    LargestFiles = [System.Collections.ArrayList]::new()
    LargestFolders = [System.Collections.ArrayList]::new()
    FileExtensions = @{}
    TotalScanned = 0
    FilesScanned = 0
    FoldersScanned = 0
    SkippedFolders = 0
    MaxDepthReached = 0
}

# Enhanced visual functions
function Show-AnimatedBanner {
    $banner = @"
                                                                                    
 ██████╗ ██████╗ ██╗██╗   ██╗███████╗██╗  ██╗      ██████╗  █████╗ ██╗   ██╗
 ██╔══██╗██╔══██╗██║██║   ██║██╔════╝╚██╗██╔╝      ██╔══██╗██╔══██╗╚██╗ ██╔╝
 ██║  ██║██████╔╝██║██║   ██║█████╗   ╚███╔╝       ██████╔╝███████║ ╚████╔╝ 
 ██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝   ██╔██╗       ██╔══██╗██╔══██║  ╚██╔╝  
 ██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██╔╝ ██╗      ██║  ██║██║  ██║   ██║   
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝      ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
                        v2.1 CLEAN UX + ADAPTIVE DEEP SCAN                                   
"@

    $rainbowColors = @("Red", "Yellow", "Green", "Cyan", "Blue", "Magenta")
    $lines = $banner -split "`n"
    
    foreach ($line in $lines) {
        $color = $rainbowColors[(Get-Random -Maximum $rainbowColors.Count)]
        Write-Host $line -ForegroundColor $color
        Start-Sleep -Milliseconds 30
    }
    
    # Animated separator
    Write-Host "┌" -NoNewline -ForegroundColor Cyan
    for ($i = 0; $i -lt 125; $i++) {
        Start-Sleep -Milliseconds 2
        Write-Host "─" -NoNewline -ForegroundColor Cyan
    }
    Write-Host "┐" -ForegroundColor Cyan
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
    $width = [Math]::Max($titleLength + 10, $contentLength + 6)
    
    # Top border with title
    Write-Host "┌─" -NoNewline -ForegroundColor $BorderColor
    Write-Host "".PadRight(($width - $Title.Length) / 2 - 2, "─") -NoNewline -ForegroundColor $BorderColor
    Write-Host " $Title " -NoNewline -ForegroundColor $TitleColor
    Write-Host "".PadRight(($width - $Title.Length) / 2 - 2, "─") -NoNewline -ForegroundColor $BorderColor
    Write-Host "─┐" -ForegroundColor $BorderColor
    
    # Content
    foreach ($line in $Content) {
        Write-Host "│ " -NoNewline -ForegroundColor $BorderColor
        
        if ($Center) {
            $padding = [Math]::Max(0, ($width - $line.Length - 4) / 2)
            Write-Host "".PadRight($padding, " ") -NoNewline
            Write-Host $line -NoNewline -ForegroundColor $ContentColor
            Write-Host "".PadRight($width - $line.Length - 4 - $padding, " ") -NoNewline
        } else {
            Write-Host $line -NoNewline -ForegroundColor $ContentColor
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
        [int]$Width = 60,
        [string]$FillColor = "Green",
        [string]$EmptyColor = "DarkGray",
        [string]$Label = "",
        [switch]$ShowPercent
    )
    
    $fillWidth = [Math]::Round(($PercentComplete / 100) * $Width)
    $emptyWidth = $Width - $fillWidth
    
    if ($Label) {
        Write-Host "$Label " -NoNewline -ForegroundColor White
    }
    
    Write-Host "[" -NoNewline -ForegroundColor White
    
    if ($fillWidth -gt 0) {
        Write-Host "".PadRight($fillWidth, "█") -NoNewline -ForegroundColor $FillColor
    }
    
    if ($emptyWidth -gt 0) {
        Write-Host "".PadRight($emptyWidth, "░") -NoNewline -ForegroundColor $EmptyColor
    }
    
    Write-Host "]" -NoNewline -ForegroundColor White
    
    if ($ShowPercent) {
        Write-Host " $PercentComplete%" -NoNewline -ForegroundColor Cyan
    }
}

function Show-PacmanProgress {
    param (
        [string]$Message = "Scanning your machine, please wait",
        [ref]$Counter
    )
    
    $pacmanFrames = @(
        "ᗧ •••••",
        "ᗤ •••••", 
        "ᗧ •••••",
        "ᗤ •••••"
    )
    
    $frameIndex = ($Counter.Value / 100) % $pacmanFrames.Length
    $frame = $pacmanFrames[$frameIndex]
    
    Write-Host "`r$Message $frame" -NoNewline -ForegroundColor Yellow
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

function Add-ToResults {
    param (
        [PSCustomObject]$Item,
        [string]$Type,
        [int]$MaxCount = 100
    )
    
    $collection = if ($Type -eq "File") { $Global:AnalysisResults.LargestFiles } else { $Global:AnalysisResults.LargestFolders }
    
    if ($collection.Count -lt $MaxCount) {
        [void]$collection.Add($Item)
    } elseif ($Item.Size -gt $collection[-1].Size) {
        $collection[-1] = $Item
    } else {
        return
    }
    
    if ($collection.Count -gt 1) {
        $sorted = $collection | Sort-Object -Property Size -Descending
        $collection.Clear()
        foreach ($sortedItem in $sorted) {
            [void]$collection.Add($sortedItem)
        }
    }
}

function Get-DirectorySize {
    param (
        [string]$Path,
        [int]$CurrentDepth = 0,
        [int]$MaxDepth = 8,
        [ref]$ProgressCounter
    )
    
    $directorySize = 0
    
    # Smart exclusions - only truly problematic folders
    $criticalExclusions = @('$Recycle.Bin', 'System Volume Information', 'Recovery', 'Config.Msi', 'hiberfil.sys', 'pagefile.sys', 'swapfile.sys')
    $folderName = Split-Path $Path -Leaf
    if ($criticalExclusions -contains $folderName) {
        return 0
    }
    
    # Update max depth reached
    if ($CurrentDepth -gt $Global:AnalysisResults.MaxDepthReached) {
        $Global:AnalysisResults.MaxDepthReached = $CurrentDepth
    }
    
    try {
        $items = Get-ChildItem -Path $Path -Force -ErrorAction Stop
        $Global:AnalysisResults.FoldersScanned++
    } catch {
        $Global:AnalysisResults.SkippedFolders++
        return 0
    }
    
    if (-not $items) { return 0 }
    
    foreach ($item in $items) {
        try {
            $ProgressCounter.Value++
            
            # Simple pacman progress - no verbose file paths
            if ($ProgressCounter.Value % 500 -eq 0) {
                Show-PacmanProgress -Message "Scanning your machine, please wait" -Counter $ProgressCounter
            }
            
            if (-not $item.PSIsContainer) {
                # File processing
                $fileSize = $item.Length
                $directorySize += $fileSize
                $Global:AnalysisResults.FilesScanned++
                
                # File extension tracking
                $extension = if ($item.Extension) { $item.Extension.ToLower() } else { "(no extension)" }
                if (-not $Global:AnalysisResults.FileExtensions.ContainsKey($extension)) {
                    $Global:AnalysisResults.FileExtensions[$extension] = @{
                        Size = [uint64]0
                        Count = 0
                    }
                }
                $Global:AnalysisResults.FileExtensions[$extension].Size += $fileSize
                $Global:AnalysisResults.FileExtensions[$extension].Count++
                
                # Track large files
                if ($fileSize -gt 1MB) {  # Only track files > 1MB
                    $fileObject = [PSCustomObject]@{
                        Path = $item.FullName
                        Name = $item.Name
                        Extension = $extension
                        Size = [uint64]$fileSize
                        SizeFormatted = Format-FileSize $fileSize
                        Created = $item.CreationTime
                        Modified = $item.LastWriteTime
                    }
                    Add-ToResults -Item $fileObject -Type "File"
                }
            } else {
                # Directory processing
                if ($CurrentDepth -lt $MaxDepth) {
                    $subdirSize = Get-DirectorySize -Path $item.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -ProgressCounter $ProgressCounter
                    $directorySize += $subdirSize
                    
                    # Track significant folders
                    if ($subdirSize -gt 5MB) {  # Only track folders > 5MB
                        $folderObject = [PSCustomObject]@{
                            Path = $item.FullName
                            Name = $item.Name
                            Size = [uint64]$subdirSize
                            SizeFormatted = Format-FileSize $subdirSize
                            SizePercentage = 0
                            Depth = $CurrentDepth
                        }
                        Add-ToResults -Item $folderObject -Type "Folder" -MaxCount 50
                    }
                }
            }
        } catch {
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
        Write-Host "No folder data available for treemap visualization." -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Show-InfoBox -Title "DISK SPACE TREEMAP VISUALIZATION" -Content @("Visual representation of space usage across your drive") -BorderColor Magenta -TitleColor Cyan -Center
    
    Write-Host "┌" -NoNewline -ForegroundColor Cyan
    Write-Host "".PadRight(123, "─") -NoNewline -ForegroundColor Cyan
    Write-Host "┐" -ForegroundColor Cyan
    
    $maxBarWidth = 80
    $topFolders = $FolderData | Sort-Object -Property Size -Descending | Select-Object -First 25
    
    foreach ($folder in $topFolders) {
        $percentage = if ($TotalSize -gt 0) { ($folder.Size / $TotalSize) * 100 } else { 0 }
        $barWidth = [Math]::Max(1, [Math]::Round(($percentage / 100) * $maxBarWidth))
        
        # Enhanced color scheme
        $barColor = if ($percentage -gt 25) { "Red" }
                    elseif ($percentage -gt 15) { "Magenta" }
                    elseif ($percentage -gt 10) { "Yellow" }
                    elseif ($percentage -gt 5) { "Green" }
                    elseif ($percentage -gt 2) { "Cyan" }
                    elseif ($percentage -gt 1) { "Blue" }
                    else { "Gray" }
        
        $bar = "".PadRight($barWidth, "█")
        $folderName = if ($folder.Name.Length -gt 35) { $folder.Name.Substring(0, 32) + "..." } else { $folder.Name }
        
        Write-Host "│ " -NoNewline -ForegroundColor Cyan
        Write-Host ("{0,-35}" -f $folderName) -NoNewline -ForegroundColor White
        Write-Host " " -NoNewline
        Write-Host $bar.PadRight($maxBarWidth, " ") -NoNewline -ForegroundColor $barColor
        Write-Host (" {0,10} ({1,6:F2}%)" -f $folder.SizeFormatted, $percentage) -NoNewline -ForegroundColor Gray
        Write-Host " │" -ForegroundColor Cyan
    }
    
    Write-Host "└" -NoNewline -ForegroundColor Cyan
    Write-Host "".PadRight(123, "─") -NoNewline -ForegroundColor Cyan
    Write-Host "┘" -ForegroundColor Cyan
}

function Show-ResultTable {
    param (
        [array]$Data,
        [string]$Title,
        [string]$Type,
        [int]$Count = 20
    )
    
    if (-not $Data -or $Data.Count -eq 0) {
        Show-InfoBox -Title "$Title - NO DATA" -Content @("No $Type data available to display.") -BorderColor Red -TitleColor Yellow
        return
    }
    
    Write-Host ""
    Show-InfoBox -Title $Title -Content @("Top $Count $Type consuming the most space") -BorderColor Yellow -TitleColor Cyan
    
    if ($Type -eq "files") {
        Write-Host "┌─────┬──────────────────────────────────────────────────────────────┬─────────────────┬──────────────┬────────────────┐" -ForegroundColor Cyan
        Write-Host "│ No. │ File Path                                                    │ Size            │ Type         │ Last Modified  │" -ForegroundColor White
        Write-Host "├─────┼──────────────────────────────────────────────────────────────┼─────────────────┼──────────────┼────────────────┤" -ForegroundColor Cyan
        
        $topItems = $Data | Select-Object -First $Count
        for ($i = 0; $i -lt $topItems.Count; $i++) {
            $item = $topItems[$i]
            $displayPath = if ($item.Path.Length -gt 60) { $item.Path.Substring(0, 57) + "..." } else { $item.Path }
            $fileType = if ($item.Extension -eq "(no extension)") { "(none)" } else { $item.Extension.TrimStart(".").ToUpper() }
            
            $typeColor = switch -Regex ($item.Extension) {
                "\.exe|\.msi|\.dll|\.sys" { "Magenta" }
                "\.mp4|\.avi|\.mkv|\.mov|\.wmv|\.flv" { "Yellow" }
                "\.jpg|\.jpeg|\.png|\.gif|\.bmp|\.tiff|\.svg" { "Green" }
                "\.zip|\.rar|\.7z|\.gz|\.bz2|\.tar" { "Cyan" }
                "\.iso|\.img|\.vhd|\.vmdk|\.ova" { "Red" }
                "\.pdf|\.doc|\.docx|\.xls|\.xlsx|\.ppt|\.pptx" { "Blue" }
                "\.mp3|\.wav|\.flac|\.aac|\.ogg" { "DarkMagenta" }
                "\.txt|\.log|\.csv|\.xml|\.json" { "Gray" }
                default { "White" }
            }
            
            Write-Host ("│ {0,3} │ " -f ($i + 1)) -NoNewline -ForegroundColor Gray
            Write-Host ("{0,-60}" -f $displayPath) -NoNewline -ForegroundColor Green
            Write-Host (" │ {0,15} │ " -f $item.SizeFormatted) -NoNewline -ForegroundColor Yellow
            Write-Host ("{0,-12}" -f $fileType) -NoNewline -ForegroundColor $typeColor
            Write-Host (" │ {0,-14} │" -f $item.Modified.ToString('yyyy-MM-dd')) -ForegroundColor DarkCyan
        }
        
        Write-Host "└─────┴──────────────────────────────────────────────────────────────┴─────────────────┴──────────────┴────────────────┘" -ForegroundColor Cyan
        
    } else {
        Write-Host "┌─────┬──────────────────────────────────────────────────────────────┬─────────────────┬──────────┬───────┐" -ForegroundColor Cyan
        Write-Host "│ No. │ Folder Path                                                  │ Size            │ % Drive  │ Depth │" -ForegroundColor White
        Write-Host "├─────┼──────────────────────────────────────────────────────────────┼─────────────────┼──────────┼───────┤" -ForegroundColor Cyan
        
        $topItems = $Data | Select-Object -First $Count
        for ($i = 0; $i -lt $topItems.Count; $i++) {
            $item = $topItems[$i]
            $displayPath = if ($item.Path.Length -gt 60) { $item.Path.Substring(0, 57) + "..." } else { $item.Path }
            
            $rowColor = if ($item.SizePercentage -gt 15) { "Red" }
                       elseif ($item.SizePercentage -gt 8) { "Yellow" }
                       elseif ($item.SizePercentage -gt 3) { "Green" }
                       else { "Cyan" }
            
            Write-Host ("│ {0,3} │ " -f ($i + 1)) -NoNewline -ForegroundColor Gray
            Write-Host ("{0,-60}" -f $displayPath) -NoNewline -ForegroundColor $rowColor
            Write-Host (" │ {0,15} │ " -f $item.SizeFormatted) -NoNewline -ForegroundColor Yellow
            Write-Host ("{0,7:F2}% │ " -f $item.SizePercentage) -NoNewline -ForegroundColor Magenta
            Write-Host ("{0,5}" -f $item.Depth) -NoNewline -ForegroundColor White
            Write-Host " │" -ForegroundColor Cyan
        }
        
        Write-Host "└─────┴──────────────────────────────────────────────────────────────┴─────────────────┴──────────┴───────┘" -ForegroundColor Cyan
    }
}

function Analyze-DriveSpace {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DriveLetter
    )
    
    if (-not $DriveLetter.EndsWith(":")) {
        $DriveLetter = "$($DriveLetter):"
    }
    
    # Reset analysis data
    $Global:AnalysisResults.LargestFiles.Clear()
    $Global:AnalysisResults.LargestFolders.Clear()
    $Global:AnalysisResults.FileExtensions.Clear()
    $Global:AnalysisResults.TotalScanned = 0
    $Global:AnalysisResults.FilesScanned = 0
    $Global:AnalysisResults.FoldersScanned = 0
    $Global:AnalysisResults.SkippedFolders = 0
    $Global:AnalysisResults.MaxDepthReached = 0
    
    Clear-Host
    Show-AnimatedBanner
    
    # Get drive information
    try {
        $driveInfo = Get-PSDrive -Name $DriveLetter[0] -PSProvider FileSystem
        $totalSize = $driveInfo.Used + $driveInfo.Free
        $usedSpace = $driveInfo.Used
        $freeSpace = $driveInfo.Free
        $usedPercent = if ($totalSize -gt 0) { [Math]::Round(($usedSpace / $totalSize) * 100, 1) } else { 0 }
    } catch {
        Show-InfoBox -Title "ERROR" -Content @("Cannot access drive $DriveLetter", "Please verify the drive exists and is accessible.") -BorderColor Red -TitleColor Yellow
        return
    }
    
    # Display drive statistics
    $driveStatsContent = @(
        "Drive: $DriveLetter",
        "Total Size: $(Format-FileSize $totalSize)",
        "Used Space: $(Format-FileSize $usedSpace) ($usedPercent%)",
        "Free Space: $(Format-FileSize $freeSpace)",
        "",
        "Disk Space Usage Visualization:"
    )
    
    Show-InfoBox -Title "DRIVE STATISTICS" -Content $driveStatsContent -BorderColor Green -TitleColor Yellow
    
    Write-Host " Used: " -NoNewline -ForegroundColor White
    Show-ProgressBar -PercentComplete $usedPercent -Width 70 -FillColor Cyan -EmptyColor DarkGray -ShowPercent
    Write-Host "  Free: $(Format-FileSize $freeSpace)" -ForegroundColor Gray
    Write-Host ""
    
    $startTime = Get-Date
    $progressCounter = [ref]0
    
    # Determine scan depth based on drive size
    $maxDepth = if ($totalSize -gt 500GB) { 6 } 
               elseif ($totalSize -gt 100GB) { 7 } 
               else { 8 }
    
    # Start scanning with simple progress
    Write-Host "🔄 Starting deep scan (max depth: $maxDepth levels)..." -ForegroundColor Cyan
    Write-Host ""
    $totalScannedSize = Get-DirectorySize -Path "$DriveLetter\" -MaxDepth $maxDepth -ProgressCounter $progressCounter
    
    # Clear progress line
    Write-Host "`r" + " " * 100 + "`r" -NoNewline
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Calculate folder percentages
    foreach ($folder in $Global:AnalysisResults.LargestFolders) {
        $folder.SizePercentage = if ($usedSpace -gt 0) { [Math]::Round(($folder.Size / $usedSpace) * 100, 3) } else { 0 }
    }
    
    # Display completion statistics
    Write-Host "✅ Scan completed successfully!" -ForegroundColor Green
    Write-Host "⏱️  Duration: $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor Gray
    Write-Host "📁 Folders: $($Global:AnalysisResults.FoldersScanned) | 📄 Files: $($Global:AnalysisResults.FilesScanned) | 🚫 Skipped: $($Global:AnalysisResults.SkippedFolders)" -ForegroundColor Gray
    Write-Host "📊 Data processed: $(Format-FileSize $totalScannedSize) | 🎯 Max depth: $($Global:AnalysisResults.MaxDepthReached)" -ForegroundColor Cyan
    
    # Display results
    Show-TreemapVisualization -FolderData $Global:AnalysisResults.LargestFolders -TotalSize $usedSpace
    Show-ResultTable -Data $Global:AnalysisResults.LargestFolders -Title "LARGEST FOLDERS" -Type "folders" -Count 25
    Show-ResultTable -Data $Global:AnalysisResults.LargestFiles -Title "LARGEST FILES" -Type "files" -Count 25
    
    # File type analysis
    if ($Global:AnalysisResults.FileExtensions.Count -gt 0) {
        Write-Host ""
        Show-InfoBox -Title "FILE TYPE ANALYSIS" -Content @("Breakdown of space usage by file type") -BorderColor Magenta -TitleColor Yellow
        
        $extensionStats = $Global:AnalysisResults.FileExtensions.GetEnumerator() | 
            ForEach-Object { 
                [PSCustomObject]@{
                    Extension = $_.Key
                    Size = $_.Value.Size
                    SizeFormatted = Format-FileSize $_.Value.Size
                    Count = $_.Value.Count
                    PercentOfDrive = if ($usedSpace -gt 0) { [Math]::Round(($_.Value.Size / $usedSpace) * 100, 3) } else { 0 }
                }
            } | Sort-Object -Property Size -Descending | Select-Object -First 20
        
        Write-Host "┌─────────────────┬─────────────────┬──────────┬───────────┬─────────────────────────────────────┐" -ForegroundColor Cyan
        Write-Host "│ Extension       │ Total Size      │ % Drive  │ File Count│ Visual Distribution                 │" -ForegroundColor White
        Write-Host "├─────────────────┼─────────────────┼──────────┼───────────┼─────────────────────────────────────┤" -ForegroundColor Cyan
        
        foreach ($ext in $extensionStats) {
            $displayExt = if ($ext.Extension -eq "(no extension)") { $ext.Extension } else { $ext.Extension }
            
            $maxCount = ($extensionStats | Measure-Object -Property Count -Maximum).Maximum
            $barWidth = if ($maxCount -gt 0) { [Math]::Min(30, [Math]::Max(1, [Math]::Round(($ext.Count / $maxCount) * 30))) } else { 1 }
            $bar = "".PadRight($barWidth, "█")
            
            $typeColor = switch -Regex ($ext.Extension) {
                "\.exe|\.msi|\.dll|\.sys" { "Magenta" }
                "\.mp4|\.avi|\.mkv|\.mov|\.wmv" { "Yellow" }
                "\.jpg|\.jpeg|\.png|\.gif|\.bmp|\.tiff" { "Green" }
                "\.zip|\.rar|\.7z|\.gz|\.bz2" { "Cyan" }
                "\.iso|\.img|\.vhd|\.vmdk" { "Red" }
                "\.pdf|\.doc|\.docx|\.xls|\.xlsx" { "Blue" }
                "\.mp3|\.wav|\.flac|\.aac" { "DarkMagenta" }
                default { "Gray" }
            }
            
            Write-Host ("│ {0,-15} │ {1,15} │ {2,7:F2}% │ {3,9} │ " -f 
                $displayExt, $ext.SizeFormatted, $ext.PercentOfDrive, $ext.Count) -NoNewline -ForegroundColor $typeColor
            Write-Host $bar.PadRight(35, " ") -NoNewline -ForegroundColor $typeColor
            Write-Host "│" -ForegroundColor Cyan
        }
        
        Write-Host "└─────────────────┴─────────────────┴──────────┴───────────┴─────────────────────────────────────┘" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Host "🎉 Analysis complete! Results displayed above." -ForegroundColor Green
    Write-Host "💡 To quit the program, type: " -NoNewline -ForegroundColor Yellow
    Write-Host "exit" -ForegroundColor White -BackgroundColor DarkRed
    Write-Host ""
    
    return @{
        DriveInfo = $driveInfo
        TotalScannedSize = $totalScannedSize
        ScanDuration = $duration
        MaxDepthReached = $Global:AnalysisResults.MaxDepthReached
    }
}

function Start-DriveAnalyzer {
    Clear-Host
    Show-AnimatedBanner
    
    # Enhanced admin check
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        $adminContent = @("✅ Running with Administrator privileges", "🔓 Full system access enabled")
        Show-InfoBox -Title "ADMIN STATUS" -Content $adminContent -BorderColor Green -TitleColor White -Center
    } else {
        $adminContent = @("⚠️  Running without Administrator privileges", "🔒 Some system files may be inaccessible")
        Show-InfoBox -Title "ADMIN WARNING" -Content $adminContent -BorderColor Red -TitleColor Yellow
        
        Write-Host ""
        $continue = Read-Host "Continue with limited access? (Y/N)"
        if ($continue -ne "Y" -and $continue -ne "y") {
            return
        }
    }
    
    # Get available drives
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and $_.Free -ne $null }
        
        $drivesContent = @("The following drives are available for analysis:")
        foreach ($drive in $drives) {
            $total = $drive.Used + $drive.Free
            $usedPercent = [Math]::Round(($drive.Used / $total) * 100, 1)
            $drivesContent += "$($drive.Name): $(Format-FileSize $drive.Used) used (${usedPercent}%) of $(Format-FileSize $total)"
        }
        
        Show-InfoBox -Title "AVAILABLE DRIVES" -Content $drivesContent -BorderColor Yellow -TitleColor Green
        
        $driveLetters = $drives | Select-Object -ExpandProperty Name
        
        Write-Host ""
        Write-Host "💽 Available drives: " -NoNewline -ForegroundColor Green
        Write-Host ($driveLetters -join ", ") -ForegroundColor Cyan
        Write-Host ""
        
        # Simple drive selection
        $selectedDrive = Read-Host "Enter drive letter to analyze"
        
        if ($selectedDrive -and $driveLetters -contains $selectedDrive.ToUpper()) {
            # Scan the drive - no loop, just scan once
            Analyze-DriveSpace -DriveLetter $selectedDrive.ToUpper()
            
            # Wait for exit command
            do {
                $exitCommand = Read-Host
            } while ($exitCommand -ne "exit")
            
            Write-Host "👋 Thank you for using DriveX-Ray!" -ForegroundColor Cyan
            
        } else {
            Write-Host "❌ Invalid drive selection. Please restart the program." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-Host "❌ Error accessing drives: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
}

# Main execution - call once, no recursion
Start-DriveAnalyzer
