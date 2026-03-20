<#
.SYNOPSIS
    DriveX-Ray - Clean Visual Disk Space Analyzer with Simple Interface
.DESCRIPTION
    A comprehensive disk space analyzer with beautiful visuals and clean user experience.
.NOTES
    Author: Ulises Paiz
    Version: 3.0 - Performance overhaul, dynamic layout, .NET fast scan, post-scan menu
#>

# NOTE: No #requires -RunAsAdministrator so the graceful fallback below can work.

# Set console properties for optimal display
$Host.UI.RawUI.WindowTitle = "DriveX-Ray v3.0 - Performance Edition"
try {
    if ($Host.UI.RawUI.WindowSize.Width -lt 130) {
        $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(130, 45)
    }
} catch {
    # Silently continue — terminal will use whatever width it has
}

# Derive usable width from actual console (minimum 80 to prevent negative PadRight)
$Global:ConsoleWidth = [Math]::Max(80, [Math]::Min(($Host.UI.RawUI.WindowSize.Width - 5), 125))

# Detect emoji support (PS 7+ on modern terminals)
$Global:UseEmoji = ($PSVersionTable.PSVersion.Major -ge 7)
function Get-Symbol {
    param ([string]$Emoji, [string]$Fallback)
    if ($Global:UseEmoji) { $Emoji } else { $Fallback }
}

# Global tracking (cleaned up on exit) — $script: can break depending on launch method
$Global:AnalysisResults = @{
    LargestFiles    = [System.Collections.ArrayList]::new()
    LargestFolders  = [System.Collections.ArrayList]::new()
    FileExtensions  = @{}
    TotalScanned    = 0
    FilesScanned    = 0
    FoldersScanned  = 0
    SkippedFolders  = 0
    MaxDepthReached = 0
}

#region ── Visual helpers ──────────────────────────────────────────────────────

function Show-AnimatedBanner {
    param ([switch]$SkipAnimation)

    $banner = @"

 ██████╗ ██████╗ ██╗██╗   ██╗███████╗██╗  ██╗      ██████╗  █████╗ ██╗   ██╗
 ██╔══██╗██╔══██╗██║██║   ██║██╔════╝╚██╗██╔╝      ██╔══██╗██╔══██╗╚██╗ ██╔╝
 ██║  ██║██████╔╝██║██║   ██║█████╗   ╚███╔╝       ██████╔╝███████║ ╚████╔╝
 ██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝   ██╔██╗       ██╔══██╗██╔══██║  ╚██╔╝
 ██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██╔╝ ██╗      ██║  ██║██║  ██║   ██║
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝      ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝
                        v3.0 PERFORMANCE EDITION
"@

    $rainbowColors = @("Red", "Yellow", "Green", "Cyan", "Blue", "Magenta")
    $lines = $banner -split "`n"

    foreach ($line in $lines) {
        $color = $rainbowColors[(Get-Random -Maximum $rainbowColors.Count)]
        Write-Host $line -ForegroundColor $color
        if (-not $SkipAnimation) { Start-Sleep -Milliseconds 20 }
    }

    Write-Host ("+" + "".PadRight([Math]::Max(1, [Math]::Min($Global:ConsoleWidth, 125)), "-") + "+") -ForegroundColor Cyan
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
    $contentMaxLen = 0
    foreach ($line in $Content) {
        if ($line.Length -gt $contentMaxLen) { $contentMaxLen = $line.Length }
    }
    $width = [Math]::Max(20, [Math]::Min($Global:ConsoleWidth, [Math]::Max($titleLength + 10, $contentMaxLen + 6)))

    # Top border with title
    $halfPad = [Math]::Max(0, [Math]::Floor(($width - $Title.Length - 4) / 2))
    $rightPadTop = [Math]::Max(0, $width - $halfPad - $Title.Length - 2)
    Write-Host ("+" + "".PadRight($halfPad, "-") + " $Title " + "".PadRight($rightPadTop, "-") + "+") -ForegroundColor $BorderColor

    # Content
    foreach ($line in $Content) {
        $innerWidth = [Math]::Max(4, $width - 4)
        $displayLine = if ($line.Length -gt $innerWidth -and $innerWidth -gt 3) {
            $line.Substring(0, $innerWidth - 3) + "..."
        } elseif ($line.Length -gt $innerWidth) {
            $line.Substring(0, $innerWidth)
        } else { $line }
        $pad = [Math]::Max(0, $innerWidth - $displayLine.Length)

        Write-Host "| " -NoNewline -ForegroundColor $BorderColor
        if ($Center) {
            $leftPad = [Math]::Floor($pad / 2)
            $rightPad = $pad - $leftPad
            Write-Host ("".PadRight($leftPad) + $displayLine + "".PadRight($rightPad)) -NoNewline -ForegroundColor $ContentColor
        } else {
            Write-Host ($displayLine + "".PadRight($pad)) -NoNewline -ForegroundColor $ContentColor
        }
        Write-Host " |" -ForegroundColor $BorderColor
    }

    # Bottom border
    Write-Host ("+" + "".PadRight([Math]::Max(0, $width - 2), "-") + "+") -ForegroundColor $BorderColor
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

    if ($Label) { Write-Host "$Label " -NoNewline -ForegroundColor White }

    Write-Host "[" -NoNewline -ForegroundColor White
    if ($fillWidth -gt 0)  { Write-Host ("".PadRight($fillWidth, "#")) -NoNewline -ForegroundColor $FillColor }
    if ($emptyWidth -gt 0) { Write-Host ("".PadRight($emptyWidth, ".")) -NoNewline -ForegroundColor $EmptyColor }
    Write-Host "]" -NoNewline -ForegroundColor White

    if ($ShowPercent) { Write-Host " $PercentComplete%" -NoNewline -ForegroundColor Cyan }
}

function Show-ScanProgress {
    param (
        [string]$Message = "Scanning",
        [int]$Counter
    )
    $filesScanned = $Global:AnalysisResults.FilesScanned
    $foldersScanned = $Global:AnalysisResults.FoldersScanned
    Write-Progress -Activity "DriveX-Ray Scan" -Status "Files: $filesScanned  Folders: $foldersScanned" -PercentComplete -1
}

function Format-FileSize {
    param ([uint64]$Size)
    if     ($Size -ge 1TB) { return "{0:N2} TB" -f ($Size / 1TB) }
    elseif ($Size -ge 1GB) { return "{0:N2} GB" -f ($Size / 1GB) }
    elseif ($Size -ge 1MB) { return "{0:N2} MB" -f ($Size / 1MB) }
    elseif ($Size -ge 1KB) { return "{0:N2} KB" -f ($Size / 1KB) }
    else                   { return "$Size Bytes" }
}

#endregion

#region ── Core scan engine ────────────────────────────────────────────────────

function Get-DirectorySize {
    param (
        [string]$Path,
        [int]$CurrentDepth = 0,
        [int]$MaxDepth = 8,
        [ref]$ProgressCounter
    )

    [uint64]$directorySize = 0

    # Skip known problematic system folders
    $criticalExclusions = @('$Recycle.Bin', 'System Volume Information', 'Recovery',
                            'Config.Msi', 'hiberfil.sys', 'pagefile.sys', 'swapfile.sys')
    $folderName = Split-Path $Path -Leaf
    if ($criticalExclusions -contains $folderName) { return [uint64]0 }

    if ($CurrentDepth -gt $Global:AnalysisResults.MaxDepthReached) {
        $Global:AnalysisResults.MaxDepthReached = $CurrentDepth
    }

    # ── Try fast .NET enumeration first, fall back to Get-ChildItem ──
    $useNetApi = $true
    $entries = $null
    try {
        $entries = [System.IO.Directory]::EnumerateFileSystemEntries($Path)
    } catch [System.UnauthorizedAccessException] {
        $Global:AnalysisResults.SkippedFolders++
        return [uint64]0
    } catch {
        $useNetApi = $false
    }

    if ($useNetApi -and $null -ne $entries) {
        $Global:AnalysisResults.FoldersScanned++

        foreach ($entry in $entries) {
            $ProgressCounter.Value++
            if ($ProgressCounter.Value % 500 -eq 0) {
                Show-ScanProgress -Message "Scanning" -Counter $ProgressCounter.Value
            }

            # Get attributes — skip entry entirely if we can't read it
            try {
                $attr = [System.IO.File]::GetAttributes($entry)
            } catch {
                continue
            }

            if ($attr -band [System.IO.FileAttributes]::Directory) {
                # ── Directory ──
                if ($CurrentDepth -lt $MaxDepth) {
                    $subdirSize = Get-DirectorySize -Path $entry -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -ProgressCounter $ProgressCounter
                    $directorySize += $subdirSize

                    if ($subdirSize -gt 5MB) {
                        $dirName = [System.IO.Path]::GetFileName($entry)
                        [void]$Global:AnalysisResults.LargestFolders.Add([PSCustomObject]@{
                            Path           = $entry
                            Name           = $dirName
                            Size           = [uint64]$subdirSize
                            SizeFormatted  = $null  # computed at display time
                            SizePercentage = 0
                            Depth          = $CurrentDepth
                        })
                    }
                }
            } else {
                # ── File ──
                [uint64]$fileSize = 0
                $fileName = $null
                $extension = "(no extension)"
                try {
                    $fi = [System.IO.FileInfo]::new($entry)
                    $fileSize  = $fi.Length
                    $fileName  = $fi.Name
                    $extension = if ($fi.Extension) { $fi.Extension.ToLower() } else { "(no extension)" }
                } catch {
                    # Fallback: get size from path string
                    try {
                        $fileSize  = (Get-Item -LiteralPath $entry -Force -ErrorAction Stop).Length
                        $fileName  = Split-Path $entry -Leaf
                        $ext = [System.IO.Path]::GetExtension($entry)
                        $extension = if ($ext) { $ext.ToLower() } else { "(no extension)" }
                    } catch { continue }
                }

                $directorySize += $fileSize
                $Global:AnalysisResults.FilesScanned++

                if (-not $Global:AnalysisResults.FileExtensions.ContainsKey($extension)) {
                    $Global:AnalysisResults.FileExtensions[$extension] = @{ Size = [uint64]0; Count = 0 }
                }
                $Global:AnalysisResults.FileExtensions[$extension].Size  += $fileSize
                $Global:AnalysisResults.FileExtensions[$extension].Count++

                if ($fileSize -gt 1MB) {
                    # Get timestamps safely — don't let metadata failure skip the file
                    $created  = $null
                    $modified = $null
                    try { $created  = $fi.CreationTime }  catch {}
                    try { $modified = $fi.LastWriteTime } catch {}

                    [void]$Global:AnalysisResults.LargestFiles.Add([PSCustomObject]@{
                        Path          = $entry
                        Name          = $fileName
                        Extension     = $extension
                        Size          = [uint64]$fileSize
                        SizeFormatted = $null  # computed at display time
                        Created       = $created
                        Modified      = $modified
                    })
                }
            }
        }

        return $directorySize
    }

    # ── Fallback: Get-ChildItem (slower but always works) ──
    try {
        $items = Get-ChildItem -Path $Path -Force -ErrorAction Stop
        $Global:AnalysisResults.FoldersScanned++
    } catch {
        $Global:AnalysisResults.SkippedFolders++
        return [uint64]0
    }

    if (-not $items) { return [uint64]0 }

    foreach ($item in $items) {
        $ProgressCounter.Value++
        if ($ProgressCounter.Value % 500 -eq 0) {
            Show-ScanProgress -Message "Scanning" -Counter $ProgressCounter.Value
        }

        try {
            if (-not $item.PSIsContainer) {
                [uint64]$fileSize = $item.Length
                $directorySize += $fileSize
                $Global:AnalysisResults.FilesScanned++

                $extension = if ($item.Extension) { $item.Extension.ToLower() } else { "(no extension)" }
                if (-not $Global:AnalysisResults.FileExtensions.ContainsKey($extension)) {
                    $Global:AnalysisResults.FileExtensions[$extension] = @{ Size = [uint64]0; Count = 0 }
                }
                $Global:AnalysisResults.FileExtensions[$extension].Size  += $fileSize
                $Global:AnalysisResults.FileExtensions[$extension].Count++

                if ($fileSize -gt 1MB) {
                    $created  = try { $item.CreationTime }  catch { $null }
                    $modified = try { $item.LastWriteTime } catch { $null }

                    [void]$Global:AnalysisResults.LargestFiles.Add([PSCustomObject]@{
                        Path          = $item.FullName
                        Name          = $item.Name
                        Extension     = $extension
                        Size          = [uint64]$fileSize
                        SizeFormatted = $null
                        Created       = $created
                        Modified      = $modified
                    })
                }
            } else {
                if ($CurrentDepth -lt $MaxDepth) {
                    $subdirSize = Get-DirectorySize -Path $item.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -ProgressCounter $ProgressCounter
                    $directorySize += $subdirSize

                    if ($subdirSize -gt 5MB) {
                        [void]$Global:AnalysisResults.LargestFolders.Add([PSCustomObject]@{
                            Path           = $item.FullName
                            Name           = $item.Name
                            Size           = [uint64]$subdirSize
                            SizeFormatted  = $null
                            SizePercentage = 0
                            Depth          = $CurrentDepth
                        })
                    }
                }
            }
        } catch {
            continue
        }
    }

    return $directorySize
}

#endregion

#region ── Display results ─────────────────────────────────────────────────────

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

    $boxWidth = [Math]::Max(50, [Math]::Min($Global:ConsoleWidth, 123))
    $maxBarWidth = [Math]::Max(10, $boxWidth - 43)  # room for name + size + percent + borders

    Write-Host ("+" + "".PadRight($boxWidth, "-") + "+") -ForegroundColor Cyan

    $topFolders = $FolderData | Sort-Object -Property Size -Descending | Select-Object -First 25

    foreach ($folder in $topFolders) {
        $percentage = if ($TotalSize -gt 0) { ($folder.Size / $TotalSize) * 100 } else { 0 }
        $barWidth = [Math]::Max(1, [Math]::Round(($percentage / 100) * $maxBarWidth))

        $barColor = if     ($percentage -gt 25) { "Red" }
                    elseif ($percentage -gt 15) { "Magenta" }
                    elseif ($percentage -gt 10) { "Yellow" }
                    elseif ($percentage -gt 5)  { "Green" }
                    elseif ($percentage -gt 2)  { "Cyan" }
                    elseif ($percentage -gt 1)  { "Blue" }
                    else                        { "Gray" }

        $bar = "".PadRight($barWidth, "#")
        $folderName = if ($folder.Name.Length -gt 35) { $folder.Name.Substring(0, 32) + "..." } else { $folder.Name }

        Write-Host "| " -NoNewline -ForegroundColor Cyan
        Write-Host ("{0,-35}" -f $folderName) -NoNewline -ForegroundColor White
        Write-Host " " -NoNewline
        Write-Host $bar.PadRight([Math]::Max($barWidth, $maxBarWidth), " ") -NoNewline -ForegroundColor $barColor
        Write-Host (" {0,10} ({1,6:F2}%)" -f $folder.SizeFormatted, $percentage) -NoNewline -ForegroundColor Gray
        Write-Host " |" -ForegroundColor Cyan
    }

    Write-Host ("+" + "".PadRight($boxWidth, "-") + "+") -ForegroundColor Cyan
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

    # Final sort before display
    $Data = $Data | Sort-Object -Property Size -Descending

    Write-Host ""
    Show-InfoBox -Title $Title -Content @("Top $Count $Type consuming the most space") -BorderColor Yellow -TitleColor Cyan

    if ($Type -eq "files") {
        Write-Host "+-----+--------------------------------------------------------------+-----------------+--------------+----------------+" -ForegroundColor Cyan
        Write-Host "| No. | File Path                                                    | Size            | Type         | Last Modified  |" -ForegroundColor White
        Write-Host "+-----+--------------------------------------------------------------+-----------------+--------------+----------------+" -ForegroundColor Cyan

        $topItems = $Data | Select-Object -First $Count
        for ($i = 0; $i -lt $topItems.Count; $i++) {
            $item = $topItems[$i]
            $displayPath = if ($item.Path.Length -gt 60) { $item.Path.Substring(0, 57) + "..." } else { $item.Path }
            $fileType = if ($item.Extension -eq "(no extension)") { "(none)" } else { $item.Extension.TrimStart(".").ToUpper() }

            $typeColor = switch -Regex ($item.Extension) {
                '\.exe|\.msi|\.dll|\.sys'                  { "Magenta" }
                '\.mp4|\.avi|\.mkv|\.mov|\.wmv|\.flv'      { "Yellow" }
                '\.jpg|\.jpeg|\.png|\.gif|\.bmp|\.tiff|\.svg' { "Green" }
                '\.zip|\.rar|\.7z|\.gz|\.bz2|\.tar'        { "Cyan" }
                '\.iso|\.img|\.vhd|\.vmdk|\.ova'           { "Red" }
                '\.pdf|\.doc|\.docx|\.xls|\.xlsx|\.ppt|\.pptx' { "Blue" }
                '\.mp3|\.wav|\.flac|\.aac|\.ogg'           { "DarkMagenta" }
                '\.txt|\.log|\.csv|\.xml|\.json'           { "Gray" }
                default { "White" }
            }

            Write-Host ("| {0,3} | " -f ($i + 1)) -NoNewline -ForegroundColor Gray
            Write-Host ("{0,-60}" -f $displayPath) -NoNewline -ForegroundColor Green
            Write-Host (" | {0,15} | " -f $item.SizeFormatted) -NoNewline -ForegroundColor Yellow
            Write-Host ("{0,-12}" -f $fileType) -NoNewline -ForegroundColor $typeColor
            $modDate = if ($item.Modified -and $item.Modified -ne [datetime]::MinValue) { $item.Modified.ToString('yyyy-MM-dd') } else { "N/A" }
            Write-Host (" | {0,-14} |" -f $modDate) -ForegroundColor DarkCyan
        }

        Write-Host "+-----+--------------------------------------------------------------+-----------------+--------------+----------------+" -ForegroundColor Cyan

    } else {
        Write-Host "+-----+--------------------------------------------------------------+-----------------+----------+-------+" -ForegroundColor Cyan
        Write-Host "| No. | Folder Path                                                  | Size            | % Drive  | Depth |" -ForegroundColor White
        Write-Host "+-----+--------------------------------------------------------------+-----------------+----------+-------+" -ForegroundColor Cyan

        $topItems = $Data | Select-Object -First $Count
        for ($i = 0; $i -lt $topItems.Count; $i++) {
            $item = $topItems[$i]
            $displayPath = if ($item.Path.Length -gt 60) { $item.Path.Substring(0, 57) + "..." } else { $item.Path }

            $rowColor = if     ($item.SizePercentage -gt 15) { "Red" }
                       elseif ($item.SizePercentage -gt 8)  { "Yellow" }
                       elseif ($item.SizePercentage -gt 3)  { "Green" }
                       else                                  { "Cyan" }

            Write-Host ("| {0,3} | " -f ($i + 1)) -NoNewline -ForegroundColor Gray
            Write-Host ("{0,-60}" -f $displayPath) -NoNewline -ForegroundColor $rowColor
            Write-Host (" | {0,15} | " -f $item.SizeFormatted) -NoNewline -ForegroundColor Yellow
            Write-Host ("{0,7:F2}% | " -f $item.SizePercentage) -NoNewline -ForegroundColor Magenta
            Write-Host ("{0,5}" -f $item.Depth) -NoNewline -ForegroundColor White
            Write-Host " |" -ForegroundColor Cyan
        }

        Write-Host "+-----+--------------------------------------------------------------+-----------------+----------+-------+" -ForegroundColor Cyan
    }
}

function Export-ResultsCsv {
    param ([string]$DriveLetter)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseName = "DriveXRay_${DriveLetter}_${timestamp}"

    $desktopPath = [Environment]::GetFolderPath("Desktop")
    if (-not (Test-Path $desktopPath)) { $desktopPath = $PWD.Path }

    $filesPath  = Join-Path $desktopPath "${baseName}_Files.csv"
    $foldersPath = Join-Path $desktopPath "${baseName}_Folders.csv"

    $Global:AnalysisResults.LargestFiles  | Sort-Object Size -Descending | Export-Csv -Path $filesPath  -NoTypeInformation
    $Global:AnalysisResults.LargestFolders | Sort-Object Size -Descending | Export-Csv -Path $foldersPath -NoTypeInformation

    Write-Host ""
    $ok = Get-Symbol "✅" "[OK]"
    Write-Host "  $ok Exported to:" -ForegroundColor Green
    Write-Host "      $filesPath" -ForegroundColor Cyan
    Write-Host "      $foldersPath" -ForegroundColor Cyan
}

#endregion

#region ── Main analysis ───────────────────────────────────────────────────────

function Invoke-DriveAnalysis {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DriveLetter
    )

    if (-not $DriveLetter.EndsWith(":")) { $DriveLetter = "$($DriveLetter):" }

    # Reset analysis data
    $Global:AnalysisResults.LargestFiles.Clear()
    $Global:AnalysisResults.LargestFolders.Clear()
    $Global:AnalysisResults.FileExtensions.Clear()
    $Global:AnalysisResults.FilesScanned    = 0
    $Global:AnalysisResults.FoldersScanned  = 0
    $Global:AnalysisResults.SkippedFolders  = 0
    $Global:AnalysisResults.MaxDepthReached = 0

    Clear-Host
    Show-AnimatedBanner -SkipAnimation

    # Get drive information
    try {
        $driveInfo  = Get-PSDrive -Name $DriveLetter[0] -PSProvider FileSystem
        [uint64]$totalSize = $driveInfo.Used + $driveInfo.Free
        [uint64]$usedSpace = $driveInfo.Used
        [uint64]$freeSpace = $driveInfo.Free
        $usedPercent = if ($totalSize -gt 0) { [Math]::Round(($usedSpace / $totalSize) * 100, 1) } else { 0 }
    } catch {
        Show-InfoBox -Title "ERROR" -Content @("Cannot access drive $DriveLetter", "Please verify the drive exists and is accessible.") -BorderColor Red -TitleColor Yellow
        return $null
    }

    # Display drive statistics
    Show-InfoBox -Title "DRIVE STATISTICS" -Content @(
        "Drive: $DriveLetter",
        "Total Size: $(Format-FileSize $totalSize)",
        "Used Space: $(Format-FileSize $usedSpace) ($usedPercent%)",
        "Free Space: $(Format-FileSize $freeSpace)"
    ) -BorderColor Green -TitleColor Yellow

    Write-Host " Used: " -NoNewline -ForegroundColor White
    Show-ProgressBar -PercentComplete $usedPercent -Width 70 -FillColor Cyan -EmptyColor DarkGray -ShowPercent
    Write-Host "  Free: $(Format-FileSize $freeSpace)" -ForegroundColor Gray
    Write-Host ""

    $startTime = Get-Date
    $progressCounter = [ref]0

    # Adaptive scan depth
    $maxDepth = if     ($totalSize -gt 500GB) { 6 }
               elseif ($totalSize -gt 100GB) { 7 }
               else                          { 8 }

    $scan = Get-Symbol "🔄" "[..]"
    Write-Host "  $scan Scanning files, please wait..." -ForegroundColor Cyan

    $totalScannedSize = Get-DirectorySize -Path "$DriveLetter\" -MaxDepth $maxDepth -ProgressCounter $progressCounter

    Write-Progress -Activity "DriveX-Ray Scan" -Completed
    Write-Host ""

    $endTime  = Get-Date
    $duration = $endTime - $startTime

    # Final sort, trim, and compute display fields (only once, after scan completes)
    $sortedFiles   = @($Global:AnalysisResults.LargestFiles   | Sort-Object -Property Size -Descending | Select-Object -First 100)
    $sortedFolders = @($Global:AnalysisResults.LargestFolders | Sort-Object -Property Size -Descending | Select-Object -First 50)

    $Global:AnalysisResults.LargestFiles.Clear()
    foreach ($f in $sortedFiles) {
        $f.SizeFormatted = Format-FileSize $f.Size
        if ($null -eq $f.Modified) { $f.Modified = [datetime]::MinValue }
        if ($null -eq $f.Created)  { $f.Created  = [datetime]::MinValue }
        [void]$Global:AnalysisResults.LargestFiles.Add($f)
    }

    $Global:AnalysisResults.LargestFolders.Clear()
    foreach ($f in $sortedFolders) {
        $f.SizeFormatted  = Format-FileSize $f.Size
        $f.SizePercentage = if ($usedSpace -gt 0) { [Math]::Round(($f.Size / $usedSpace) * 100, 3) } else { 0 }
        [void]$Global:AnalysisResults.LargestFolders.Add($f)
    }

    # Completion stats
    $ok    = Get-Symbol "✅" "[OK]"
    $clock = Get-Symbol "⏱️"  "[T]"
    $files = Get-Symbol "📄" "[F]"
    $dirs  = Get-Symbol "📁" "[D]"
    $skip  = Get-Symbol "🚫" "[S]"
    $chart = Get-Symbol "📊" "[i]"

    Write-Host "  $ok Scan completed successfully!" -ForegroundColor Green
    Write-Host "  $clock Duration: $($duration.Minutes)m $($duration.Seconds)s" -ForegroundColor Gray
    Write-Host "  $dirs Folders: $($Global:AnalysisResults.FoldersScanned) | $files Files: $($Global:AnalysisResults.FilesScanned) | $skip Skipped: $($Global:AnalysisResults.SkippedFolders)" -ForegroundColor Gray
    Write-Host "  $chart Data processed: $(Format-FileSize $totalScannedSize) | Max depth: $($Global:AnalysisResults.MaxDepthReached)" -ForegroundColor Cyan

    # Display results
    Show-TreemapVisualization -FolderData $Global:AnalysisResults.LargestFolders -TotalSize $usedSpace
    Show-ResultTable -Data $Global:AnalysisResults.LargestFolders -Title "LARGEST FOLDERS" -Type "folders" -Count 25
    Show-ResultTable -Data $Global:AnalysisResults.LargestFiles   -Title "LARGEST FILES"   -Type "files"   -Count 25

    # File type analysis
    if ($Global:AnalysisResults.FileExtensions.Count -gt 0) {
        Write-Host ""
        Show-InfoBox -Title "FILE TYPE ANALYSIS" -Content @("Breakdown of space usage by file type") -BorderColor Magenta -TitleColor Yellow

        $extensionStats = $Global:AnalysisResults.FileExtensions.GetEnumerator() |
            ForEach-Object {
                [PSCustomObject]@{
                    Extension      = $_.Key
                    Size           = $_.Value.Size
                    SizeFormatted  = Format-FileSize $_.Value.Size
                    Count          = $_.Value.Count
                    PercentOfDrive = if ($usedSpace -gt 0) { [Math]::Round(($_.Value.Size / $usedSpace) * 100, 3) } else { 0 }
                }
            } | Sort-Object -Property Size -Descending | Select-Object -First 20

        Write-Host "+-----------------+-----------------+----------+-----------+-------------------------------------+" -ForegroundColor Cyan
        Write-Host "| Extension       | Total Size      | % Drive  | File Count| Visual Distribution                 |" -ForegroundColor White
        Write-Host "+-----------------+-----------------+----------+-----------+-------------------------------------+" -ForegroundColor Cyan

        $maxCount = ($extensionStats | Measure-Object -Property Count -Maximum).Maximum

        foreach ($ext in $extensionStats) {
            $barWidth = if ($maxCount -gt 0) { [Math]::Min(30, [Math]::Max(1, [Math]::Round(($ext.Count / $maxCount) * 30))) } else { 1 }
            $bar = "".PadRight($barWidth, "#")

            $typeColor = switch -Regex ($ext.Extension) {
                '\.exe|\.msi|\.dll|\.sys'            { "Magenta" }
                '\.mp4|\.avi|\.mkv|\.mov|\.wmv'      { "Yellow" }
                '\.jpg|\.jpeg|\.png|\.gif|\.bmp|\.tiff' { "Green" }
                '\.zip|\.rar|\.7z|\.gz|\.bz2'        { "Cyan" }
                '\.iso|\.img|\.vhd|\.vmdk'           { "Red" }
                '\.pdf|\.doc|\.docx|\.xls|\.xlsx'    { "Blue" }
                '\.mp3|\.wav|\.flac|\.aac'           { "DarkMagenta" }
                default { "Gray" }
            }

            Write-Host ("| {0,-15} | {1,15} | {2,7:F2}% | {3,9} | " -f
                $ext.Extension, $ext.SizeFormatted, $ext.PercentOfDrive, $ext.Count) -NoNewline -ForegroundColor $typeColor
            Write-Host $bar.PadRight(35, " ") -NoNewline -ForegroundColor $typeColor
            Write-Host "|" -ForegroundColor Cyan
        }

        Write-Host "+-----------------+-----------------+----------+-----------+-------------------------------------+" -ForegroundColor Cyan
    }

    return @{
        DriveInfo        = $driveInfo
        DriveLetter      = $DriveLetter
        TotalScannedSize = $totalScannedSize
        ScanDuration     = $duration
    }
}

#endregion

#region ── Entry point ─────────────────────────────────────────────────────────

function Start-DriveAnalyzer {
    Clear-Host
    Show-AnimatedBanner

    # Graceful admin check (no #requires so this actually runs)
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        Show-InfoBox -Title "ADMIN STATUS" -Content @(
            "$(Get-Symbol '✅' '[OK]') Running with Administrator privileges",
            "$(Get-Symbol '🔓' '[+]')  Full system access enabled"
        ) -BorderColor Green -TitleColor White -Center
    } else {
        Show-InfoBox -Title "ADMIN WARNING" -Content @(
            "$(Get-Symbol '⚠️' '[!]')  Running without Administrator privileges",
            "$(Get-Symbol '🔒' '[-]') Some system files may be inaccessible"
        ) -BorderColor Red -TitleColor Yellow

        Write-Host ""
        $continue = Read-Host "  Continue with limited access? (Y/N)"
        if ($continue -notin @('Y', 'y', 'Yes', 'yes')) { return }
    }

    # Get available drives
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Used -and $null -ne $_.Free }

        $drivesContent = @("The following drives are available for analysis:")
        foreach ($drive in $drives) {
            [uint64]$total = $drive.Used + $drive.Free
            $usedPercent = [Math]::Round(($drive.Used / $total) * 100, 1)
            $drivesContent += "$($drive.Name): $(Format-FileSize $drive.Used) used (${usedPercent}%) of $(Format-FileSize $total)"
        }

        Show-InfoBox -Title "AVAILABLE DRIVES" -Content $drivesContent -BorderColor Yellow -TitleColor Green

        $driveLetters = $drives | Select-Object -ExpandProperty Name

        $disk = Get-Symbol "💽" "[>]"
        Write-Host ""
        Write-Host "  $disk Available drives: " -NoNewline -ForegroundColor Green
        Write-Host ($driveLetters -join ", ") -ForegroundColor Cyan
        Write-Host ""

        $selectedDrive = Read-Host "  Enter drive letter to analyze"

        if (-not $selectedDrive -or $driveLetters -notcontains $selectedDrive.ToUpper()) {
            Write-Host "  $(Get-Symbol '❌' '[X]') Invalid drive selection. Please restart the program." -ForegroundColor Red
            Start-Sleep -Seconds 2
            return
        }

        $lastResult = Invoke-DriveAnalysis -DriveLetter $selectedDrive.ToUpper()

        # ── Post-scan menu ──
        $running = $true
        while ($running) {
            Write-Host ""
            Write-Host "  +---------- DriveX-Ray Menu ----------+" -ForegroundColor Cyan
            Write-Host "  |  [R] Rescan current drive            |" -ForegroundColor White
            Write-Host "  |  [D] Scan a different drive           |" -ForegroundColor White
            Write-Host "  |  [E] Export results to CSV            |" -ForegroundColor White
            Write-Host "  |  [Q] Quit                             |" -ForegroundColor White
            Write-Host "  +--------------------------------------+" -ForegroundColor Cyan
            Write-Host ""

            $choice = Read-Host "  Choice"

            switch ($choice.ToUpper()) {
                'R' {
                    if ($lastResult -and $lastResult.DriveLetter) {
                        $lastResult = Invoke-DriveAnalysis -DriveLetter $lastResult.DriveLetter
                    } else {
                        Write-Host "  No previous scan to repeat." -ForegroundColor Yellow
                    }
                }
                'D' {
                    Write-Host ""
                    Write-Host "  $disk Available drives: " -NoNewline -ForegroundColor Green
                    Write-Host ($driveLetters -join ", ") -ForegroundColor Cyan
                    $newDrive = Read-Host "  Enter drive letter"
                    if ($newDrive -and $driveLetters -contains $newDrive.ToUpper()) {
                        $lastResult = Invoke-DriveAnalysis -DriveLetter $newDrive.ToUpper()
                    } else {
                        Write-Host "  $(Get-Symbol '❌' '[X]') Invalid drive." -ForegroundColor Red
                    }
                }
                'E' {
                    if ($lastResult -and $lastResult.DriveLetter) {
                        Export-ResultsCsv -DriveLetter $lastResult.DriveLetter[0]
                    } else {
                        Write-Host "  No results to export. Run a scan first." -ForegroundColor Yellow
                    }
                }
                'Q' {
                    $running = $false
                    Write-Host ""
                    Write-Host "  $(Get-Symbol '👋' '[~]') Thank you for using DriveX-Ray!" -ForegroundColor Cyan
                    Write-Host ""
                }
                default {
                    Write-Host "  Invalid choice. Use R, D, E, or Q." -ForegroundColor Yellow
                }
            }
        }

    } catch {
        Write-Host "  $(Get-Symbol '❌' '[X]') Error accessing drives: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
}

# Single entry point — no recursion
Start-DriveAnalyzer

# Clean up global variables so we don't pollute the session
Remove-Variable -Name AnalysisResults, ConsoleWidth, UseEmoji -Scope Global -ErrorAction SilentlyContinue

#endregion
