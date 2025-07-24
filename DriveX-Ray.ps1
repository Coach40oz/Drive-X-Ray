#requires -RunAsAdministrator
<#
.SYNOPSIS
    DriveX-Ray - Enhanced Visual Disk Space Analyzer with Adaptive Deep Scanning
.DESCRIPTION
    A comprehensive disk space analyzer with beautiful visuals and intelligent depth scanning.
.NOTES
    Author: Enhanced Visual Version  
    Version: 2.0 - Visuals + adaptive deep scanning
#>

# Set console properties for optimal display
$Host.UI.RawUI.WindowTitle = "DriveX-Ray v2.0 - Enhanced Visual Edition"
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
    CurrentDepth = 0
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
                        v2.0 ENHANCED VISUAL + ADAPTIVE DEEP SCAN                                   
"@

    $rainbowColors = @("Red", "Yellow", "Green", "Cyan", "Blue", "Magenta")
    $lines = $banner -split "`n"
    
    foreach ($line in $lines) {
        $color = $rainbowColors[(Get-Random -Maximum $rainbowColors.Count)]
        Write-Host $line -ForegroundColor $color
        Start-Sleep -Milliseconds 50
    }
    
    # Animated separator
    Write-Host "┌" -NoNewline -ForegroundColor Cyan
    for ($i = 0; $i -lt 125; $i++) {
        Start-Sleep -Milliseconds 3
        Write-Host "─" -NoNewline -ForegroundColor Cyan
    }
    Write-Host "┐" -ForegroundColor Cyan
}

function Show-EnhancedInfoBox {
    param (
        [string]$Title,
        [string[]]$Content,
        [string]$BorderColor = "Cyan",
        [string]$TitleColor = "Yellow",
        [string]$ContentColor = "White",
        [switch]$Center,
        [switch]$Animated
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
    
    # Content with animation if requested
    foreach ($line in $Content) {
        Write-Host "│ " -NoNewline -ForegroundColor $BorderColor
        
        if ($Center) {
            $padding = [Math]::Max(0, ($width - $line.Length - 4) / 2)
            Write-Host "".PadRight($padding, " ") -NoNewline
            
            if ($Animated) {
                foreach ($char in $line.ToCharArray()) {
                    Write-Host $char -NoNewline -ForegroundColor $ContentColor
                    Start-Sleep -Milliseconds 20
                }
            } else {
                Write-Host $line -NoNewline -ForegroundColor $ContentColor
            }
            
            Write-Host "".PadRight($width - $line.Length - 4 - $padding, " ") -NoNewline
        } else {
            if ($Animated) {
                foreach ($char in $line.ToCharArray()) {
                    Write-Host $char -NoNewline -ForegroundColor $ContentColor
                    Start-Sleep -Milliseconds 15
                }
            } else {
                Write-Host $line -NoNewline -ForegroundColor $ContentColor
            }
            Write-Host "".PadRight($width - $line.Length - 4, " ") -NoNewline
        }
        
        Write-Host " │" -ForegroundColor $BorderColor
    }
    
    # Bottom border
    Write-Host "└" -NoNewline -ForegroundColor $BorderColor
    Write-Host "".PadRight($width, "─") -NoNewline -ForegroundColor $BorderColor
    Write-Host "┘" -ForegroundColor $BorderColor
}

function Show-EnhancedProgressBar {
    param (
        [int]$PercentComplete,
        [int]$Width = 60,
        [string]$FillColor = "Green",
        [string]$EmptyColor = "DarkGray",
        [string]$Label = "",
        [switch]$ShowPercent,
        [switch]$Animated
    )
    
    $fillWidth = [Math]::Round(($PercentComplete / 100) * $Width)
    $emptyWidth = $Width - $fillWidth
    
    if ($Label) {
        Write-Host "$Label " -NoNewline -ForegroundColor White
    }
    
    Write-Host "[" -NoNewline -ForegroundColor White
    
    # Animated fill
    if ($Animated -and $fillWidth -gt 0) {
        for ($i = 0; $i -lt $fillWidth; $i++) {
            Write-Host "█" -NoNewline -ForegroundColor $FillColor
            Start-Sleep -Milliseconds 10
        }
    } elseif ($fillWidth -gt 0) {
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
    
    $drivesContent = @("The following drives are available for enhanced analysis:")
    foreach ($drive in $drives) {
        $total = $drive.Used + $drive.Free
        $usedPercent = [Math]::Round(($drive.Used / $total) * 100, 1)
        $drivesContent += "$($drive.Name): - $(Format-FileSize $drive.Used) used (${usedPercent}%) of $(Format-FileSize $total)"
    }
    
    Show-EnhancedInfoBox -Title "AVAILABLE DRIVES" -Content $drivesContent -BorderColor Yellow -TitleColor Green -ContentColor White -Animated
    return $drives
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

function Get-AdaptiveDirectorySize {
    param (
        [string]$Path,
        [int]$CurrentDepth = 0,
        [int]$MaxDepth = 8,
        [ref]$ProgressCounter,
        [uint64]$SizeThreshold = 10MB
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
            
            # Enhanced progress display
            if ($ProgressCounter.Value % 250 -eq 0) {
                $cursorChars = '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'
                $progressChar = $cursorChars[($ProgressCounter.Value / 250) % $cursorChars.Length]
                $shortPath = if ($Path.Length -gt 70) { "..." + $Path.Substring($Path.Length - 67) } else { $Path }
                $depthInfo = "Depth: $CurrentDepth/$MaxDepth"
                Write-Host "`r🔍 $progressChar Scanning: $shortPath | $depthInfo | Files: $($Global:AnalysisResults.FilesScanned)" -NoNewline -ForegroundColor Cyan
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
                        AccessTime = $item.LastAccessTime
                    }
                    Add-ToResults -Item $fileObject -Type "File"
                }
            } else {
                # Directory processing with adaptive depth
                $shouldScanDeeper = $true
                
                # Adaptive scanning: if we're deep and folder seems small, don't go deeper
                if ($CurrentDepth -ge 4) {
                    try {
                        $quickSample = Get-ChildItem -Path $item.FullName -File -ErrorAction SilentlyContinue | 
                                     Select-Object -First 10 | 
                                     Measure-Object -Property Length -Sum
                        
                        if ($quickSample.Sum -lt $SizeThreshold) {
                            $shouldScanDeeper = $false
                        }
                    } catch {
                        $shouldScanDeeper = $false
                    }
                }
                
                if ($CurrentDepth -lt $MaxDepth -and $shouldScanDeeper) {
                    $subdirSize = Get-AdaptiveDirectorySize -Path $item.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -ProgressCounter $ProgressCounter -SizeThreshold $SizeThreshold
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
                            ItemCount = 0
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

function Show-EnhancedTreemap {
    param (
        [array]$FolderData,
        [uint64]$TotalSize,
        [string]$Title = "DISK SPACE TREEMAP VISUALIZATION"
    )
    
    if (-not $FolderData -or $FolderData.Count -eq 0) {
        Show-EnhancedInfoBox -Title "TREEMAP UNAVAILABLE" -Content @("No significant folder data available for visualization.") -BorderColor Red -TitleColor Yellow
        return
    }
    
    Write-Host ""
    Show-EnhancedInfoBox -Title $Title -Content @("Visual representation of space usage across your drive") -BorderColor Magenta -TitleColor Cyan -Center
    
    # Enhanced treemap with better visuals
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
        
        # Create visual block
        $blocks = "█", "▉", "▊", "▋", "▌", "▍", "▎", "▏"
        $fullBlocks = [Math]::Floor($barWidth)
        $partialBlock = $barWidth - $fullBlocks
        
        $bar = "".PadRight($fullBlocks, "█")
        if ($partialBlock -gt 0) {
            $blockIndex = [Math]::Floor($partialBlock * ($blocks.Count - 1))
            $bar += $blocks[$blockIndex]
        }
        
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

function Show-EnhancedResultTable {
    param (
        [array]$Data,
        [string]$Title,
        [string]$Type,
        [int]$Count = 20
    )
    
    if (-not $Data -or $Data.Count -eq 0) {
        Show-EnhancedInfoBox -Title "$Title - NO DATA" -Content @("No $Type data available to display.") -BorderColor Red -TitleColor Yellow
        return
    }
    
    Write-Host ""
    Show-EnhancedInfoBox -Title $Title -Content @("Top $Count $Type consuming the most space") -BorderColor Yellow -TitleColor Cyan
    
    if ($Type -eq "files") {
        # Files table
        Write-Host "┌─────┬──────────────────────────────────────────────────────────────┬─────────────────┬──────────────┬────────────────┐" -ForegroundColor Cyan
        Write-Host "│ No. │ File Path                                                    │ Size            │ Type         │ Last Modified  │" -ForegroundColor White
        Write-Host "├─────┼──────────────────────────────────────────────────────────────┼─────────────────┼──────────────┼────────────────┤" -ForegroundColor Cyan
        
        $topItems = $Data | Select-Object -First $Count
        for ($i = 0; $i -lt $topItems.Count; $i++) {
            $item = $topItems[$i]
            $displayPath = if ($item.Path.Length -gt 60) { $item.Path.Substring(0, 57) + "..." } else { $item.Path }
            $fileType = if ($item.Extension -eq "(no extension)") { "(none)" } else { $item.Extension.TrimStart(".").ToUpper() }
            
            # Enhanced file type colors
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
        # Folders table
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
        [string]$DriveLetter,
        [string]$ScanMode = "Adaptive"
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
        Show-EnhancedInfoBox -Title "ERROR" -Content @("Cannot access drive $DriveLetter", "Please verify the drive exists and is accessible.") -BorderColor Red -TitleColor Yellow
        return
    }
    
    # Display drive statistics with enhanced visuals
    $driveStatsContent = @(
        "Drive: $DriveLetter",
        "Total Size: $(Format-FileSize $totalSize)",
        "Used Space: $(Format-FileSize $usedSpace) ($usedPercent%)",
        "Free Space: $(Format-FileSize $freeSpace)",
        "",
        "Scan Mode: $ScanMode (Adaptive depth up to 8 levels)",
        "",
        "Disk Space Usage Visualization:"
    )
    
    Show-EnhancedInfoBox -Title "DRIVE STATISTICS" -Content $driveStatsContent -BorderColor Green -TitleColor Yellow -Animated
    
    Write-Host " Used: " -NoNewline -ForegroundColor White
    Show-EnhancedProgressBar -PercentComplete $usedPercent -Width 70 -FillColor Cyan -EmptyColor DarkGray -ShowPercent -Animated
    Write-Host "  Free: $(Format-FileSize $freeSpace)" -ForegroundColor Gray
    Write-Host ""
    
    # Enhanced scanning notification
    $scanningContent = @(
        "🚀 Initiating ENHANCED deep scan of drive $DriveLetter",
        "📊 Using adaptive depth scanning (smarter & faster)",
        "🔍 Analyzing file sizes, types, and folder structures",
        "⚡ Progress will be displayed in real-time below",
        "",
        "Please wait while we intelligently scan your drive..."
    )
    
    Show-EnhancedInfoBox -Title "ENHANCED SCANNING INITIATED" -Content $scanningContent -BorderColor Cyan -TitleColor Yellow -Animated
    
    $startTime = Get-Date
    $progressCounter = [ref]0
    
    # Determine scan depth based on drive size
    $maxDepth = if ($totalSize -gt 500GB) { 6 } 
               elseif ($totalSize -gt 100GB) { 7 } 
               else { 8 }
    
    # Start adaptive scanning
    Write-Host "🔄 Starting adaptive scan (max depth: $maxDepth levels)..." -ForegroundColor Cyan
    $totalScannedSize = Get-AdaptiveDirectorySize -Path "$DriveLetter\" -MaxDepth $maxDepth -ProgressCounter $progressCounter
    
    # Clear progress line
    Write-Host "`r" + " " * 150 + "`r" -NoNewline
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Calculate folder percentages
    foreach ($folder in $Global:AnalysisResults.LargestFolders) {
        $folder.SizePercentage = if ($usedSpace -gt 0) { [Math]::Round(($folder.Size / $usedSpace) * 100, 3) } else { 0 }
    }
    
    # Display completion statistics
    $completionContent = @(
        "✅ Enhanced scan completed successfully!",
        "⏱️  Duration: $($duration.Minutes)m $($duration.Seconds)s",
        "📁 Folders scanned: $($Global:AnalysisResults.FoldersScanned)",
        "📄 Files analyzed: $($Global:AnalysisResults.FilesScanned)",
        "🚫 Folders skipped: $($Global:AnalysisResults.SkippedFolders)",
        "📊 Data processed: $(Format-FileSize $totalScannedSize)",
        "🎯 Maximum depth reached: $($Global:AnalysisResults.MaxDepthReached) levels"
    )
    
    Show-EnhancedInfoBox -Title "SCAN COMPLETE" -Content $completionContent -BorderColor Green -TitleColor Yellow -Center -Animated
    
    # Display enhanced results
    Show-EnhancedTreemap -FolderData $Global:AnalysisResults.LargestFolders -TotalSize $usedSpace
    Show-EnhancedResultTable -Data $Global:AnalysisResults.LargestFolders -Title "LARGEST FOLDERS" -Type "folders" -Count 25
    Show-EnhancedResultTable -Data $Global:AnalysisResults.LargestFiles -Title "LARGEST FILES" -Type "files" -Count 25
    
    # Enhanced file type analysis
    if ($Global:AnalysisResults.FileExtensions.Count -gt 0) {
        Write-Host ""
        Show-EnhancedInfoBox -Title "FILE TYPE ANALYSIS" -Content @("Comprehensive breakdown of space usage by file type") -BorderColor Magenta -TitleColor Yellow
        
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
            
            # Enhanced visual bar
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
    
    return @{
        DriveInfo = $driveInfo
        TotalScannedSize = $totalScannedSize
        ScanDuration = $duration
        MaxDepthReached = $Global:AnalysisResults.MaxDepthReached
    }
}

function Show-MainMenu {
    Clear-Host
    Show-AnimatedBanner
    
    # Enhanced admin check
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        $adminContent = @("✅ Running with Administrator privileges", "🔓 Full system access enabled for comprehensive scanning")
        Show-EnhancedInfoBox -Title "ADMIN STATUS" -Content $adminContent -BorderColor Green -TitleColor White -Center
    } else {
        $adminContent = @("⚠️  Running without Administrator privileges", "🔒 Some system files may be inaccessible", "💡 Restart as Administrator for complete analysis")
        Show-EnhancedInfoBox -Title "ADMIN WARNING" -Content $adminContent -BorderColor Red -TitleColor Yellow
        
        $continue = Read-Host "`nContinue with limited access? (Y/N)"
        if ($continue -ne "Y" -and $continue -ne "y") {
            return
        }
    }
    
    # Enhanced drive selection
    $drives = Get-AvailableDrives
    $driveLetters = $drives | Select-Object -ExpandProperty Name
    
    $menuContent = @(
        "🎯 SCAN MODES AVAILABLE:",
        "",
        "🔹 ADAPTIVE SCAN (Recommended)",
        "   • Intelligent depth adjustment",
        "   • Optimized for speed and accuracy",
        "   • Focuses on significant data",
        "",
        "Available drives: $($driveLetters -join ', ')",
        "Enter 'Q' to quit"
    )
    
    Show-EnhancedInfoBox -Title "ENHANCED DRIVE ANALYZER" -Content $menuContent -BorderColor Cyan -TitleColor Green
    
    Write-Host "`n┌" -NoNewline -ForegroundColor Yellow
    Write-Host "".PadRight(60, "─") -NoNewline -ForegroundColor Yellow
    Write-Host "┐" -ForegroundColor Yellow
    Write-Host "│" -NoNewline -ForegroundColor Yellow
    Write-Host " Enter drive letter to analyze: " -NoNewline -ForegroundColor White -BackgroundColor DarkBlue
    $selectedDrive = Read-Host
    Write-Host "│" -ForegroundColor Yellow
    Write-Host "└" -NoNewline -ForegroundColor Yellow
    Write-Host "".PadRight(60, "─") -NoNewline -ForegroundColor Yellow
    Write-Host "┘" -ForegroundColor Yellow
    
    if ($selectedDrive -eq "Q" -or $selectedDrive -eq "q") {
        $goodbyeContent = @("", "Thank you for using DriveX-Ray Enhanced!", "", "🚀 Your drive analysis journey ends here")
        Show-EnhancedInfoBox -Title "GOODBYE" -Content $goodbyeContent -BorderColor Cyan -TitleColor Magenta -Center -Animated
        Start-Sleep -Seconds 2
        return
    }
    
    if ($selectedDrive -and $driveLetters -contains $selectedDrive.ToUpper()) {
        $result = Analyze-DriveSpace -DriveLetter $selectedDrive.ToUpper() -ScanMode "Adaptive"
        
        $continueContent = @(
            "",
            "🎉 Analysis complete! Results displayed above.",
            "",
            "Press any key to return to menu or 'Q' to quit..."
        )
        
        Show-EnhancedInfoBox -Title "ANALYSIS COMPLETE" -Content $continueContent -BorderColor Green -TitleColor Yellow -Center
        
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Q') {
            $goodbyeContent = @("", "Thanks for using DriveX-Ray Enhanced! 🚀", "")
            Show-EnhancedInfoBox -Title "GOODBYE" -Content $goodbyeContent -BorderColor Cyan -TitleColor Magenta -Center -Animated
            return
        } else {
            Show-MainMenu
        }
    } else {
        $errorContent = @("❌ Invalid drive selection: '$selectedDrive'", "Please select from: $($driveLetters -join ', ')")
        Show-EnhancedInfoBox -Title "INPUT ERROR" -Content $errorContent -BorderColor Red -TitleColor Yellow
        Start-Sleep -Seconds 2
        Show-MainMenu
    }
}

# Enhanced main execution
Show-MainMenu
