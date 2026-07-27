<#
.SYNOPSIS
    DriveX-Ray - Visual disk space analyzer for the PowerShell console.
.DESCRIPTION
    Scans a drive and reports the largest folders, largest files and space usage
    by file type, with a treemap-style visualization. Uses the .NET enumeration
    APIs for speed and degrades gracefully without Administrator rights.
.PARAMETER Drive
    Drive letter to analyze (e.g. C, C:, C:\). When omitted the script prompts.
.PARAMETER MaxDepth
    How many folder levels appear in the folder table and treemap; 1 means
    top-level folders only. The scan always walks the whole tree so reported
    sizes stay accurate - this limits the listing, not the measurement.
    Default 8.
.PARAMETER Top
    Number of rows shown in the folder and file tables. Default 25.
.PARAMETER ExportPath
    Directory for CSV exports. Defaults to the Desktop, then the current folder.
.PARAMETER NonInteractive
    Scan, print the report, and exit without the post-scan menu. Requires -Drive.
.EXAMPLE
    .\DriveX-Ray.ps1
    Interactive mode: pick a drive from the list and browse the results.
.EXAMPLE
    .\DriveX-Ray.ps1 -Drive C -Top 40 -MaxDepth 3
    Scan C:, list the 40 largest folders no deeper than 3 levels, and the 40
    largest files.
.NOTES
    Author : Ulises Paiz
    Version: 3.1
    Requires: PowerShell 5.1 or later on Windows.
#>

[CmdletBinding()]
param (
    [string]$Drive,
    [ValidateRange(1, 32)]
    [int]$MaxDepth = 8,
    [ValidateRange(1, 500)]
    [int]$Top = 25,
    [string]$ExportPath,
    [switch]$NonInteractive
)

# No #requires -RunAsAdministrator: the script checks for elevation itself so it
# can run with reduced access instead of refusing to start.

# Terminating errors make the try/catch blocks below meaningful. The original
# value is restored on exit so the `irm ... | iex` flow does not permanently
# change the caller's session preference.
$script:PreviousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'

#region -- Configuration -------------------------------------------------------

# Hard ceiling on recursion so a pathological tree (or a reparse cycle that got
# past the ReparsePoint check) can never blow the PowerShell call stack.
$script:TraversalLimit = 64

# Only files/folders above these sizes are candidates for the "largest" tables.
# Both thresholds rise automatically on huge drives - see Limit-CandidateList.
$script:FileThreshold   = [uint64]1MB
$script:FolderThreshold = [uint64]5MB

# Candidate lists are trimmed once they reach TrimAt, down to KeepCount. The
# report never shows more than a few hundred rows, so this bounds memory and
# the cost of the final sort without affecting the output.
$script:FileTrimAt    = 20000
$script:FileKeep      = 5000
$script:FolderTrimAt  = 10000
$script:FolderKeep    = 2000

#endregion

#region -- Console setup -------------------------------------------------------

try { $Host.UI.RawUI.WindowTitle = "DriveX-Ray v3.1" } catch { }

# Widen the window if the host allows it; many hosts (ISE, redirected output,
# VS Code terminal) throw or silently ignore this.
try {
    if ($Host.UI.RawUI.WindowSize.Width -lt 130) {
        $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(130, 45)
    }
} catch { }

$script:ConsoleWidth = 120
try {
    $detected = $Host.UI.RawUI.WindowSize.Width
    if ($detected -gt 0) {
        $script:ConsoleWidth = [Math]::Max(80, [Math]::Min($detected - 2, 160))
    }
} catch { }

# Emoji need both a modern host and a UTF-8 output encoding; PowerShell 5.1
# consoles are almost always code page 437/850 and render them as garbage.
$script:UseUnicode = $false
try {
    $script:UseUnicode = ($PSVersionTable.PSVersion.Major -ge 7) -and
                         ([Console]::OutputEncoding.CodePage -eq 65001)
} catch { }

# This file is deliberately pure ASCII. A .ps1 containing raw UTF-8 with no BOM
# is decoded using the ANSI code page by Windows PowerShell 5.1, which turns
# every emoji and box-drawing character into mojibake - and adding a BOM is not
# an option because it breaks the `irm ... | iex` install one-liner (the U+FEFF
# survives decoding and fuses onto the first token). Building the characters
# from code points at runtime sidesteps both problems.
$script:Sym = @{}
foreach ($glyph in @(
    @{ Name = 'Ok';     Points = @(0x2705);         Ascii = '[OK]' }
    @{ Name = 'Fail';   Points = @(0x274C);         Ascii = '[X] ' }
    @{ Name = 'Warn';   Points = @(0x26A0, 0xFE0F); Ascii = '[!] ' }
    @{ Name = 'Unlock'; Points = @(0x1F513);        Ascii = '[+] ' }
    @{ Name = 'Lock';   Points = @(0x1F512);        Ascii = '[-] ' }
    @{ Name = 'Scan';   Points = @(0x1F504);        Ascii = '[..]' }
    @{ Name = 'Clock';  Points = @(0x23F1, 0xFE0F); Ascii = '[T] ' }
    @{ Name = 'File';   Points = @(0x1F4C4);        Ascii = '[F] ' }
    @{ Name = 'Folder'; Points = @(0x1F4C1);        Ascii = '[D] ' }
    @{ Name = 'Block';  Points = @(0x1F6AB);        Ascii = '[S] ' }
    @{ Name = 'Link';   Points = @(0x1F517);        Ascii = '[L] ' }
    @{ Name = 'Chart';  Points = @(0x1F4CA);        Ascii = '[i] ' }
    @{ Name = 'Disk';   Points = @(0x1F4BD);        Ascii = '[>] ' }
    @{ Name = 'Wave';   Points = @(0x1F44B);        Ascii = '[~] ' }
)) {
    if ($script:UseUnicode) {
        $script:Sym[$glyph.Name] = -join @($glyph.Points | ForEach-Object { [char]::ConvertFromUtf32($_) })
    } else {
        $script:Sym[$glyph.Name] = $glyph.Ascii
    }
}

#endregion

#region -- Scan state ----------------------------------------------------------

$script:Results = @{
    LargestFiles    = [System.Collections.ArrayList]::new()
    LargestFolders  = [System.Collections.ArrayList]::new()
    FileExtensions  = @{}
    FilesScanned    = 0
    FoldersScanned  = 0
    SkippedFolders  = 0
    SkippedLinks    = 0
    MaxDepthReached = 0
}

$script:EntryCounter  = 0
$script:ProgressWatch = $null

# .NET Core can be told to swallow access errors mid-enumeration. On .NET
# Framework (PowerShell 5.1) there is no such option, so the enumerator loop
# below has to guard MoveNext() itself.
$script:EnumOptions = $null
if ($PSVersionTable.PSVersion.Major -ge 6) {
    try {
        $script:EnumOptions = [System.IO.EnumerationOptions]::new()
        $script:EnumOptions.IgnoreInaccessible    = $true
        $script:EnumOptions.RecurseSubdirectories = $false
        # Default is Hidden|System; we want those included, like -Force.
        $script:EnumOptions.AttributesToSkip      = [System.IO.FileAttributes]0
    } catch {
        $script:EnumOptions = $null
    }
}

#endregion

#region -- Visual helpers ------------------------------------------------------

# Console cell width, not UTF-16 length. Emoji occupy two columns but report a
# .Length of 1 (U+2705) or 2 (surrogate pairs), so padding by .Length skews
# every box that contains one.
function Get-DisplayWidth {
    param ([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return 0 }

    $width = 0
    $enum = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($enum.MoveNext()) {
        $element = [string]$enum.Current

        # Variation Selector-16 forces emoji presentation => two columns.
        if ($element.IndexOf([char]0xFE0F) -ge 0) { $width += 2; continue }

        $cp = [char]::ConvertToUtf32($element, 0)
        $isWide = ($cp -ge 0x1100    -and $cp -le 0x115F) -or   # Hangul Jamo
                  ($cp -ge 0x2600    -and $cp -le 0x27BF) -or   # symbols, dingbats
                  ($cp -ge 0x2E80    -and $cp -le 0xA4CF) -or   # CJK
                  ($cp -ge 0xAC00    -and $cp -le 0xD7A3) -or   # Hangul syllables
                  ($cp -ge 0xF900    -and $cp -le 0xFAFF) -or   # CJK compatibility
                  ($cp -ge 0xFF00    -and $cp -le 0xFF60) -or   # fullwidth forms
                  ($cp -ge 0x1F300   -and $cp -le 0x1FAFF)      # emoji planes
        if ($isWide) { $width += 2 } else { $width += 1 }
    }
    return $width
}

# The banner is stored as an ASCII stencil so the source file stays pure ASCII
# (see the note above $script:Sym). Placeholders are swapped for box-drawing
# characters on UTF-8 hosts and for plain slashes everywhere else.
$script:BannerStencil = @"
 ######7 ######7 ##7##7   ##7#######7##7  ##7      ######7  #####7 ##7   ##7
 ##4==##7##4==##7##|##|   ##|##4====JL##7##4J      ##4==##7##4==##7L##7 ##4J
 ##|  ##|######4J##|##|   ##|#####7   L###4J       ######4J#######| L####4J
 ##|  ##|##4==##7##|L##7 ##4J##4==J   ##4##7       ##4==##7##4==##|  L##4J
 ######4J##|  ##|##| L####4J #######7##4J ##7      ##|  ##|##|  ##|   ##|
 L=====J L=J  L=JL=J  L===J  L======JL=J  L=J      L=J  L=JL=J  L=J   L=J
"@

function Expand-BannerStencil {
    if ($script:UseUnicode) {
        # block, top-right, top-left, horizontal, vertical, bottom-right, bottom-left
        $map = @{ '#' = 0x2588; '7' = 0x2557; '4' = 0x2554; '=' = 0x2550
                  '|' = 0x2551; 'J' = 0x255D; 'L' = 0x255A }
        $sb = [System.Text.StringBuilder]::new()
        foreach ($ch in $script:BannerStencil.ToCharArray()) {
            if ($map.ContainsKey([string]$ch)) {
                [void]$sb.Append([char]$map[[string]$ch])
            } else {
                [void]$sb.Append($ch)
            }
        }
        return $sb.ToString()
    }

    return $script:BannerStencil.Replace('7', '\').Replace('4', '/').
                                 Replace('J', '/').Replace('L', '\')
}

function Show-AnimatedBanner {
    param ([switch]$SkipAnimation)

    $rainbowColors = @("Red", "Yellow", "Green", "Cyan", "Blue", "Magenta")

    Write-Host ""
    foreach ($line in ((Expand-BannerStencil) -split "`r?`n")) {
        $color = $rainbowColors[(Get-Random -Maximum $rainbowColors.Count)]
        Write-Host $line -ForegroundColor $color
        if (-not $SkipAnimation) { Start-Sleep -Milliseconds 20 }
    }
    Write-Host "                              v3.1" -ForegroundColor DarkGray

    Write-Host ("+" + "".PadRight($script:ConsoleWidth - 2, "-") + "+") -ForegroundColor Cyan
}

function Show-InfoBox {
    param (
        [string]$Title,
        [string[]]$Content,
        [string]$BorderColor = "Cyan",
        [string]$TitleColor  = "Yellow",
        [string]$ContentColor = "White",
        [switch]$Center
    )

    $titleWidth = Get-DisplayWidth $Title
    $contentMax = 0
    foreach ($line in $Content) {
        $w = Get-DisplayWidth $line
        if ($w -gt $contentMax) { $contentMax = $w }
    }

    # Total box width including both border characters.
    $width = [Math]::Max(24, [Math]::Min($script:ConsoleWidth, [Math]::Max($titleWidth + 10, $contentMax + 4)))
    $inner = $width - 4   # printable columns between "| " and " |"

    # Top border: "+" + dashes + " Title " + dashes + "+" must total $width.
    $titleCells = $titleWidth + 2
    $dashTotal  = [Math]::Max(2, $width - 2 - $titleCells)
    $leftDash   = [Math]::Floor($dashTotal / 2)
    $rightDash  = $dashTotal - $leftDash

    Write-Host ("+" + "".PadRight($leftDash, "-")) -NoNewline -ForegroundColor $BorderColor
    Write-Host " $Title " -NoNewline -ForegroundColor $TitleColor
    Write-Host ("".PadRight($rightDash, "-") + "+") -ForegroundColor $BorderColor

    foreach ($line in $Content) {
        $display = $line
        if ((Get-DisplayWidth $display) -gt $inner) {
            # Trim by text elements so a surrogate pair is never split in half.
            $sb = [System.Text.StringBuilder]::new()
            $used = 0
            $enum = [System.Globalization.StringInfo]::GetTextElementEnumerator($display)
            while ($enum.MoveNext()) {
                $el = [string]$enum.Current
                $w  = Get-DisplayWidth $el
                if ($used + $w -gt $inner - 3) { break }
                [void]$sb.Append($el)
                $used += $w
            }
            $display = $sb.ToString() + "..."
        }

        $pad = [Math]::Max(0, $inner - (Get-DisplayWidth $display))

        Write-Host "| " -NoNewline -ForegroundColor $BorderColor
        if ($Center) {
            $leftPad = [Math]::Floor($pad / 2)
            Write-Host ("".PadRight($leftPad) + $display + "".PadRight($pad - $leftPad)) -NoNewline -ForegroundColor $ContentColor
        } else {
            Write-Host ($display + "".PadRight($pad)) -NoNewline -ForegroundColor $ContentColor
        }
        Write-Host " |" -ForegroundColor $BorderColor
    }

    Write-Host ("+" + "".PadRight($width - 2, "-") + "+") -ForegroundColor $BorderColor
}

function Show-ProgressBar {
    param (
        [double]$PercentComplete,
        [int]$Width = 60,
        [string]$FillColor = "Green",
        [string]$EmptyColor = "DarkGray",
        [string]$Label = "",
        [switch]$ShowPercent
    )

    $clamped   = [Math]::Max(0, [Math]::Min(100, $PercentComplete))
    $fillWidth = [int][Math]::Round(($clamped / 100) * $Width)
    $emptyWidth = $Width - $fillWidth

    if ($Label) { Write-Host "$Label " -NoNewline -ForegroundColor White }

    Write-Host "[" -NoNewline -ForegroundColor White
    if ($fillWidth -gt 0)  { Write-Host ("".PadRight($fillWidth, "#"))  -NoNewline -ForegroundColor $FillColor }
    if ($emptyWidth -gt 0) { Write-Host ("".PadRight($emptyWidth, ".")) -NoNewline -ForegroundColor $EmptyColor }
    Write-Host "]" -NoNewline -ForegroundColor White

    if ($ShowPercent) { Write-Host (" {0:F1}%" -f $clamped) -NoNewline -ForegroundColor Cyan }
}

function Format-FileSize {
    param ([double]$Size)

    $sign = ""
    if ($Size -lt 0) { $sign = "-"; $Size = [Math]::Abs($Size) }

    if     ($Size -ge 1TB) { return "$sign{0:N2} TB" -f ($Size / 1TB) }
    elseif ($Size -ge 1GB) { return "$sign{0:N2} GB" -f ($Size / 1GB) }
    elseif ($Size -ge 1MB) { return "$sign{0:N2} MB" -f ($Size / 1MB) }
    elseif ($Size -ge 1KB) { return "$sign{0:N2} KB" -f ($Size / 1KB) }
    else                   { return "$sign{0:N0} Bytes" -f $Size }
}

# Builds "+----+------+" style rules so tables can size themselves to the
# console instead of using hard-coded 60-column paths.
function Format-TableRule {
    param ([int[]]$Widths)
    $segments = foreach ($w in $Widths) { "".PadRight($w + 2, "-") }
    return "+" + ($segments -join "+") + "+"
}

function Format-Cell {
    param ([string]$Text, [int]$Width, [switch]$Right)

    if ($null -eq $Text) { $Text = "" }
    if ($Text.Length -gt $Width) {
        if ($Width -gt 3) { $Text = $Text.Substring(0, $Width - 3) + "..." }
        else              { $Text = $Text.Substring(0, $Width) }
    }
    if ($Right) { return $Text.PadLeft($Width) }
    return $Text.PadRight($Width)
}

# Keeps the middle of a path out of the way: C:\Users\...\AppData\Local\Temp
function Format-Path {
    param ([string]$Path, [int]$Width)

    if ($null -eq $Path) { return "".PadRight($Width) }
    if ($Path.Length -le $Width) { return $Path.PadRight($Width) }
    if ($Width -lt 12) { return $Path.Substring(0, $Width) }

    $tail = [int][Math]::Floor(($Width - 3) * 0.65)
    $head = $Width - 3 - $tail
    return ($Path.Substring(0, $head) + "..." + $Path.Substring($Path.Length - $tail))
}

function Get-TypeColor {
    param ([string]$Extension)

    switch -Regex ($Extension) {
        '^\.(exe|msi|dll|sys|cab|msu)$'                  { return "Magenta" }
        '^\.(mp4|avi|mkv|mov|wmv|flv|webm|m4v)$'         { return "Yellow" }
        '^\.(jpg|jpeg|png|gif|bmp|tiff|svg|heic|webp)$'  { return "Green" }
        '^\.(zip|rar|7z|gz|bz2|tar|xz|zst)$'             { return "Cyan" }
        '^\.(iso|img|vhd|vhdx|vmdk|ova|qcow2)$'          { return "Red" }
        '^\.(pdf|doc|docx|xls|xlsx|ppt|pptx|odt)$'       { return "Blue" }
        '^\.(mp3|wav|flac|aac|ogg|m4a|wma)$'             { return "DarkMagenta" }
        '^\.(txt|log|csv|xml|json|yml|yaml|md)$'         { return "Gray" }
        default                                          { return "White" }
    }
}

#endregion

#region -- Core scan engine ----------------------------------------------------

function Show-ScanProgress {
    param ([string]$CurrentPath)

    Write-Progress -Activity "DriveX-Ray scan" `
                   -Status ("Files: {0:N0}   Folders: {1:N0}   Skipped: {2:N0}" -f
                            $script:Results.FilesScanned,
                            $script:Results.FoldersScanned,
                            $script:Results.SkippedFolders) `
                   -CurrentOperation $CurrentPath `
                   -PercentComplete -1
}

# Drops the candidate lists back to a manageable size and raises the threshold
# to whatever the new smallest entry is, so the list cannot immediately refill.
function Limit-CandidateList {
    param (
        [ValidateSet('Files', 'Folders')]
        [string]$Kind
    )

    if ($Kind -eq 'Files') {
        $list = $script:Results.LargestFiles
        $keep = $script:FileKeep
    } else {
        $list = $script:Results.LargestFolders
        $keep = $script:FolderKeep
    }

    $survivors = @($list | Sort-Object -Property Size -Descending | Select-Object -First $keep)
    $list.Clear()
    foreach ($s in $survivors) { [void]$list.Add($s) }

    if ($survivors.Count -gt 0) {
        $newThreshold = [uint64]$survivors[$survivors.Count - 1].Size
        if ($Kind -eq 'Files') { $script:FileThreshold   = $newThreshold }
        else                   { $script:FolderThreshold = $newThreshold }
    }
}

function Get-DirectorySize {
    param (
        [string]$Path,
        [int]$CurrentDepth = 0,
        [int]$RecordDepth  = 8
    )

    [uint64]$directorySize = 0

    if ($CurrentDepth -gt $script:TraversalLimit) { return [uint64]0 }
    if ($CurrentDepth -gt $script:Results.MaxDepthReached) {
        $script:Results.MaxDepthReached = $CurrentDepth
    }

    try {
        $dirInfo = [System.IO.DirectoryInfo]::new($Path)
        if ($null -ne $script:EnumOptions) {
            $enumerable = $dirInfo.EnumerateFileSystemInfos('*', $script:EnumOptions)
        } else {
            $enumerable = $dirInfo.EnumerateFileSystemInfos()
        }
        $enumerator = $enumerable.GetEnumerator()
    } catch {
        $script:Results.SkippedFolders++
        return [uint64]0
    }

    $script:Results.FoldersScanned++

    try {
        while ($true) {
            # EnumerateFileSystemInfos is lazy: access errors surface here, not
            # at the call above. On .NET Framework an unreadable subfolder would
            # otherwise throw straight past every recursion frame and abort the
            # entire scan.
            try {
                if (-not $enumerator.MoveNext()) { break }
            } catch [System.UnauthorizedAccessException] {
                $script:Results.SkippedFolders++
                break
            } catch {
                $script:Results.SkippedFolders++
                break
            }

            $entry = $enumerator.Current

            $script:EntryCounter++
            if (($script:EntryCounter -band 1023) -eq 0 -and
                $script:ProgressWatch.ElapsedMilliseconds -ge 200) {
                Show-ScanProgress -CurrentPath $Path
                $script:ProgressWatch.Restart()
            }

            # Attributes and Length come from the directory enumeration itself,
            # so reading them costs no extra I/O.
            try { $attributes = $entry.Attributes } catch { continue }

            # Junctions and symlinks point at data counted elsewhere on the
            # drive (C:\Users\All Users -> C:\ProgramData). Following them
            # double-counts and can loop.
            if ($attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $script:Results.SkippedLinks++
                continue
            }

            if ($attributes -band [System.IO.FileAttributes]::Directory) {
                # Always recurse so parent sizes stay correct; RecordDepth only
                # controls how deep folders are *listed*.
                $subdirSize = Get-DirectorySize -Path $entry.FullName `
                                                -CurrentDepth ($CurrentDepth + 1) `
                                                -RecordDepth $RecordDepth
                $directorySize += $subdirSize

                if ($CurrentDepth -lt $RecordDepth -and $subdirSize -ge $script:FolderThreshold) {
                    [void]$script:Results.LargestFolders.Add([PSCustomObject]@{
                        Path           = $entry.FullName
                        Name           = $entry.Name
                        Size           = [uint64]$subdirSize
                        SizeFormatted  = $null
                        SizePercentage = 0.0
                        Depth          = $CurrentDepth
                    })

                    if ($script:Results.LargestFolders.Count -ge $script:FolderTrimAt) {
                        Limit-CandidateList -Kind Folders
                    }
                }
            } else {
                try { [uint64]$fileSize = $entry.Length } catch { continue }

                $directorySize += $fileSize
                $script:Results.FilesScanned++

                $extension = "(no extension)"
                if ($entry.Extension) { $extension = $entry.Extension.ToLowerInvariant() }

                $bucket = $script:Results.FileExtensions[$extension]
                if ($null -eq $bucket) {
                    $bucket = @{ Size = [uint64]0; Count = 0 }
                    $script:Results.FileExtensions[$extension] = $bucket
                }
                # Explicit cast: uint64 + int64 promotes to double in PowerShell.
                $bucket.Size = [uint64]($bucket.Size + $fileSize)
                $bucket.Count++

                if ($fileSize -ge $script:FileThreshold) {
                    $created  = [datetime]::MinValue
                    $modified = [datetime]::MinValue
                    try { $created  = $entry.CreationTime }  catch { }
                    try { $modified = $entry.LastWriteTime } catch { }

                    [void]$script:Results.LargestFiles.Add([PSCustomObject]@{
                        Path          = $entry.FullName
                        Name          = $entry.Name
                        Extension     = $extension
                        Size          = [uint64]$fileSize
                        SizeFormatted = $null
                        Created       = $created
                        Modified      = $modified
                    })

                    if ($script:Results.LargestFiles.Count -ge $script:FileTrimAt) {
                        Limit-CandidateList -Kind Files
                    }
                }
            }
        }
    } finally {
        if ($enumerator -is [System.IDisposable]) { $enumerator.Dispose() }
    }

    return $directorySize
}

#endregion

#region -- Display results -----------------------------------------------------

# Only depth-0 folders (direct children of the drive root) are shown, because
# those partition the drive. Mixing depths would list C:\Users, C:\Users\Bob and
# C:\Users\Bob\AppData as three separate bars whose percentages sum past 100%.
function Show-TreemapVisualization {
    param (
        [array]$FolderData,
        [uint64]$UsedSpace,
        [uint64]$ScannedSize
    )

    $roots = @($FolderData | Where-Object { $_.Depth -eq 0 } | Sort-Object -Property Size -Descending)

    if ($roots.Count -eq 0) {
        Write-Host ""
        Write-Host "  No top-level folder data available for the treemap." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Show-InfoBox -Title "DISK SPACE TREEMAP" `
                 -Content @("Top-level folders as a share of used space ($(Format-FileSize $UsedSpace))") `
                 -BorderColor Magenta -TitleColor Cyan -Center

    # Row layout: "| " + name + " " + bar + size + " (nnn.nn%)" + " |"
    $nameWidth  = 32
    $sizeWidth  = 11
    $statsWidth = $sizeWidth + 10                        # size + " (100.00%)"
    $boxWidth   = $script:ConsoleWidth
    $barWidth   = [Math]::Max(10, $boxWidth - $nameWidth - $statsWidth - 5)

    # Anything the top-level folders do not account for: loose files in the root
    # plus everything the scan could not read (system files, in-use handles).
    [uint64]$rootFolderTotal = 0
    foreach ($r in $roots) { $rootFolderTotal += [uint64]$r.Size }

    $rows = [System.Collections.ArrayList]::new()
    foreach ($r in $roots) {
        [void]$rows.Add([PSCustomObject]@{ Name = $r.Name; Size = [double]$r.Size; Kind = 'Folder' })
    }

    $looseFiles = [double]$ScannedSize - [double]$rootFolderTotal
    if ($looseFiles -gt 1MB) {
        [void]$rows.Add([PSCustomObject]@{ Name = "(files in drive root)"; Size = $looseFiles; Kind = 'Other' })
    }

    $unaccounted = [double]$UsedSpace - [double]$ScannedSize
    if ($unaccounted -gt 1MB) {
        [void]$rows.Add([PSCustomObject]@{ Name = "(not scanned / no access)"; Size = $unaccounted; Kind = 'Other' })
    }

    $sorted = @($rows | Sort-Object -Property Size -Descending)

    Write-Host ("+" + "".PadRight($boxWidth - 2, "-") + "+") -ForegroundColor Cyan

    foreach ($row in $sorted) {
        $percentage = 0.0
        if ($UsedSpace -gt 0) { $percentage = ($row.Size / [double]$UsedSpace) * 100 }

        $fill = [int][Math]::Round(($percentage / 100) * $barWidth)
        if ($fill -lt 1 -and $row.Size -gt 0) { $fill = 1 }
        if ($fill -gt $barWidth) { $fill = $barWidth }

        if ($row.Kind -eq 'Other') {
            $barColor = "DarkGray"
        } else {
            $barColor = if     ($percentage -gt 25) { "Red" }
                        elseif ($percentage -gt 15) { "Magenta" }
                        elseif ($percentage -gt 10) { "Yellow" }
                        elseif ($percentage -gt 5)  { "Green" }
                        elseif ($percentage -gt 2)  { "Cyan" }
                        elseif ($percentage -gt 1)  { "Blue" }
                        else                        { "Gray" }
        }

        Write-Host "| " -NoNewline -ForegroundColor Cyan
        Write-Host (Format-Cell $row.Name $nameWidth) -NoNewline -ForegroundColor White
        Write-Host " " -NoNewline
        Write-Host ("".PadRight($fill, "#").PadRight($barWidth)) -NoNewline -ForegroundColor $barColor
        Write-Host ("{0} ({1,6:F2}%)" -f (Format-Cell (Format-FileSize $row.Size) $sizeWidth -Right), $percentage) -NoNewline -ForegroundColor Gray
        Write-Host " |" -ForegroundColor Cyan
    }

    Write-Host ("+" + "".PadRight($boxWidth - 2, "-") + "+") -ForegroundColor Cyan
}

function Show-FileTable {
    param ([array]$Data, [int]$Count)

    if (-not $Data -or $Data.Count -eq 0) {
        Show-InfoBox -Title "LARGEST FILES - NO DATA" `
                     -Content @("No files above $(Format-FileSize $script:FileThreshold) were found.") `
                     -BorderColor Red -TitleColor Yellow
        return
    }

    Write-Host ""
    Show-InfoBox -Title "LARGEST FILES" -Content @("Top $Count files by size") -BorderColor Yellow -TitleColor Cyan

    $noW    = 4
    $sizeW  = 12
    $typeW  = 10
    $dateW  = 10
    $pathW  = [Math]::Max(24, $script:ConsoleWidth - ($noW + $sizeW + $typeW + $dateW) - 16)
    $rule   = Format-TableRule @($noW, $pathW, $sizeW, $typeW, $dateW)

    Write-Host $rule -ForegroundColor Cyan
    Write-Host ("| {0} | {1} | {2} | {3} | {4} |" -f
        (Format-Cell "No." $noW), (Format-Cell "File Path" $pathW),
        (Format-Cell "Size" $sizeW -Right), (Format-Cell "Type" $typeW),
        (Format-Cell "Modified" $dateW)) -ForegroundColor White
    Write-Host $rule -ForegroundColor Cyan

    $rows = @($Data | Select-Object -First $Count)
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $item = $rows[$i]

        $fileType = "(none)"
        if ($item.Extension -ne "(no extension)") { $fileType = $item.Extension.TrimStart(".").ToUpperInvariant() }

        $modDate = "N/A"
        if ($item.Modified -and $item.Modified -ne [datetime]::MinValue) {
            $modDate = $item.Modified.ToString('yyyy-MM-dd')
        }

        Write-Host ("| {0} | " -f (Format-Cell ([string]($i + 1)) $noW -Right)) -NoNewline -ForegroundColor Gray
        Write-Host (Format-Path $item.Path $pathW) -NoNewline -ForegroundColor Green
        Write-Host (" | {0} | " -f (Format-Cell $item.SizeFormatted $sizeW -Right)) -NoNewline -ForegroundColor Yellow
        Write-Host (Format-Cell $fileType $typeW) -NoNewline -ForegroundColor (Get-TypeColor $item.Extension)
        Write-Host (" | {0} |" -f (Format-Cell $modDate $dateW)) -ForegroundColor DarkCyan
    }

    Write-Host $rule -ForegroundColor Cyan
}

function Show-FolderTable {
    param ([array]$Data, [int]$Count)

    if (-not $Data -or $Data.Count -eq 0) {
        Show-InfoBox -Title "LARGEST FOLDERS - NO DATA" `
                     -Content @("No folders above $(Format-FileSize $script:FolderThreshold) were found.") `
                     -BorderColor Red -TitleColor Yellow
        return
    }

    Write-Host ""
    Show-InfoBox -Title "LARGEST FOLDERS" `
                 -Content @("Top $Count folders by size (sizes include everything nested inside)") `
                 -BorderColor Yellow -TitleColor Cyan

    $noW    = 4
    $sizeW  = 12
    $pctW   = 8
    $depthW = 5
    $pathW  = [Math]::Max(24, $script:ConsoleWidth - ($noW + $sizeW + $pctW + $depthW) - 16)
    $rule   = Format-TableRule @($noW, $pathW, $sizeW, $pctW, $depthW)

    Write-Host $rule -ForegroundColor Cyan
    Write-Host ("| {0} | {1} | {2} | {3} | {4} |" -f
        (Format-Cell "No." $noW), (Format-Cell "Folder Path" $pathW),
        (Format-Cell "Size" $sizeW -Right), (Format-Cell "% Used" $pctW -Right),
        (Format-Cell "Depth" $depthW -Right)) -ForegroundColor White
    Write-Host $rule -ForegroundColor Cyan

    $rows = @($Data | Select-Object -First $Count)
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $item = $rows[$i]

        $rowColor = if     ($item.SizePercentage -gt 15) { "Red" }
                    elseif ($item.SizePercentage -gt 8)  { "Yellow" }
                    elseif ($item.SizePercentage -gt 3)  { "Green" }
                    else                                 { "Cyan" }

        Write-Host ("| {0} | " -f (Format-Cell ([string]($i + 1)) $noW -Right)) -NoNewline -ForegroundColor Gray
        Write-Host (Format-Path $item.Path $pathW) -NoNewline -ForegroundColor $rowColor
        Write-Host (" | {0} | " -f (Format-Cell $item.SizeFormatted $sizeW -Right)) -NoNewline -ForegroundColor Yellow
        Write-Host (Format-Cell ("{0:F2}%" -f $item.SizePercentage) $pctW -Right) -NoNewline -ForegroundColor Magenta
        Write-Host (" | {0} |" -f (Format-Cell ([string]$item.Depth) $depthW -Right)) -ForegroundColor Cyan
    }

    Write-Host $rule -ForegroundColor Cyan
}

function Show-ExtensionTable {
    param ([uint64]$UsedSpace, [int]$Count = 20)

    if ($script:Results.FileExtensions.Count -eq 0) { return }

    Write-Host ""
    Show-InfoBox -Title "FILE TYPE ANALYSIS" -Content @("Space usage by extension") -BorderColor Magenta -TitleColor Yellow

    $stats = @(
        $script:Results.FileExtensions.GetEnumerator() | ForEach-Object {
            $pct = 0.0
            if ($UsedSpace -gt 0) { $pct = ([double]$_.Value.Size / [double]$UsedSpace) * 100 }
            [PSCustomObject]@{
                Extension      = $_.Key
                Size           = [uint64]$_.Value.Size
                SizeFormatted  = Format-FileSize $_.Value.Size
                Count          = $_.Value.Count
                PercentOfDrive = $pct
            }
        } | Sort-Object -Property Size -Descending | Select-Object -First $Count
    )

    if ($stats.Count -eq 0) { return }

    $extW   = 14
    $sizeW  = 12
    $pctW   = 8
    $cntW   = 10
    $barW   = [Math]::Max(10, [Math]::Min(40, $script:ConsoleWidth - ($extW + $sizeW + $pctW + $cntW) - 16))
    $rule   = Format-TableRule @($extW, $sizeW, $pctW, $cntW, $barW)

    Write-Host $rule -ForegroundColor Cyan
    Write-Host ("| {0} | {1} | {2} | {3} | {4} |" -f
        (Format-Cell "Extension" $extW), (Format-Cell "Total Size" $sizeW -Right),
        (Format-Cell "% Used" $pctW -Right), (Format-Cell "Files" $cntW -Right),
        (Format-Cell "Share of Largest" $barW)) -ForegroundColor White
    Write-Host $rule -ForegroundColor Cyan

    # Scale bars by size, matching what the rest of the row reports.
    $maxSize = [double]($stats[0].Size)

    foreach ($ext in $stats) {
        $fill = 1
        if ($maxSize -gt 0) {
            $fill = [int][Math]::Round(([double]$ext.Size / $maxSize) * $barW)
            if ($fill -lt 1) { $fill = 1 }
        }
        $color = Get-TypeColor $ext.Extension

        Write-Host ("| {0} | {1} | {2} | {3} | " -f
            (Format-Cell $ext.Extension $extW),
            (Format-Cell $ext.SizeFormatted $sizeW -Right),
            (Format-Cell ("{0:F2}%" -f $ext.PercentOfDrive) $pctW -Right),
            (Format-Cell ("{0:N0}" -f $ext.Count) $cntW -Right)) -NoNewline -ForegroundColor $color
        Write-Host ("".PadRight($fill, "#").PadRight($barW)) -NoNewline -ForegroundColor $color
        Write-Host " |" -ForegroundColor Cyan
    }

    Write-Host $rule -ForegroundColor Cyan
}

function Export-ResultsCsv {
    param ([string]$DriveLetter, [string]$Destination)

    $folder = $Destination
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        Write-Host "  $($script:Sym.Warn) '$folder' does not exist - falling back to the default location." -ForegroundColor Yellow
        $folder = $null
    }
    if (-not $folder) {
        try { $folder = [Environment]::GetFolderPath("Desktop") } catch { $folder = $null }
    }
    if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { $folder = $PWD.Path }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseName  = "DriveXRay_${DriveLetter}_${timestamp}"

    $filesPath   = Join-Path $folder "${baseName}_Files.csv"
    $foldersPath = Join-Path $folder "${baseName}_Folders.csv"
    $typesPath   = Join-Path $folder "${baseName}_FileTypes.csv"

    try {
        $script:Results.LargestFiles |
            Select-Object Name, Path, Extension, Size, SizeFormatted, Created, Modified |
            Sort-Object Size -Descending |
            Export-Csv -Path $filesPath -NoTypeInformation -Encoding UTF8

        $script:Results.LargestFolders |
            Select-Object Name, Path, Size, SizeFormatted, SizePercentage, Depth |
            Sort-Object Size -Descending |
            Export-Csv -Path $foldersPath -NoTypeInformation -Encoding UTF8

        $script:Results.FileExtensions.GetEnumerator() |
            ForEach-Object {
                [PSCustomObject]@{
                    Extension     = $_.Key
                    Size          = [uint64]$_.Value.Size
                    SizeFormatted = Format-FileSize $_.Value.Size
                    Count         = $_.Value.Count
                }
            } | Sort-Object Size -Descending |
            Export-Csv -Path $typesPath -NoTypeInformation -Encoding UTF8

        Write-Host ""
        Write-Host "  $($script:Sym.Ok) Exported to:" -ForegroundColor Green
        foreach ($p in @($filesPath, $foldersPath, $typesPath)) {
            Write-Host "      $p" -ForegroundColor Cyan
        }
    } catch {
        Write-Host ""
        Write-Host "  $($script:Sym.Fail) Export failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "      Tried to write to: $folder" -ForegroundColor DarkGray
    }
}

#endregion

#region -- Main analysis -------------------------------------------------------

function Get-DriveInventory {
    $inventory = [System.Collections.ArrayList]::new()

    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($null -eq $d.Used -and $null -eq $d.Free) { continue }
        if ($d.Name.Length -ne 1) { continue }   # skip named PSDrives like 'Temp'

        [uint64]$used = 0
        [uint64]$free = 0
        if ($d.Used) { $used = [uint64]$d.Used }
        if ($d.Free) { $free = [uint64]$d.Free }
        [uint64]$total = $used + $free
        if ($total -eq 0) { continue }           # empty card readers, some network shares

        [void]$inventory.Add([PSCustomObject]@{
            Name        = $d.Name.ToUpperInvariant()
            Root        = $d.Root
            Used        = $used
            Free        = $free
            Total       = $total
            UsedPercent = [Math]::Round(($used / [double]$total) * 100, 1)
        })
    }

    return $inventory
}

function Resolve-DriveLetter {
    param ([string]$Text, [string[]]$Valid)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    # Accept "c", "C:", "c:\", " C:/ "
    $letter = $Text.Trim().TrimStart('"', "'").Substring(0, 1).ToUpperInvariant()
    if ($Valid -contains $letter) { return $letter }
    return $null
}

function Invoke-DriveAnalysis {
    param (
        [Parameter(Mandatory = $true)][string]$DriveLetter,
        [int]$RecordDepth = 8,
        [int]$RowCount = 25
    )

    $letter = $DriveLetter.Substring(0, 1).ToUpperInvariant()

    # Reset per-scan state, including the adaptive thresholds.
    $script:Results.LargestFiles.Clear()
    $script:Results.LargestFolders.Clear()
    $script:Results.FileExtensions.Clear()
    $script:Results.FilesScanned    = 0
    $script:Results.FoldersScanned  = 0
    $script:Results.SkippedFolders  = 0
    $script:Results.SkippedLinks    = 0
    $script:Results.MaxDepthReached = 0
    $script:EntryCounter            = 0
    $script:FileThreshold           = [uint64]1MB
    $script:FolderThreshold         = [uint64]5MB

    Clear-Host
    Show-AnimatedBanner -SkipAnimation

    $drive = Get-DriveInventory | Where-Object { $_.Name -eq $letter } | Select-Object -First 1
    if (-not $drive) {
        Show-InfoBox -Title "ERROR" `
                     -Content @("Cannot access drive ${letter}:", "Verify the drive exists and is ready.") `
                     -BorderColor Red -TitleColor Yellow
        return $null
    }

    Show-InfoBox -Title "DRIVE STATISTICS" -Content @(
        "Drive:      ${letter}:",
        "Total Size: $(Format-FileSize $drive.Total)",
        "Used Space: $(Format-FileSize $drive.Used) ($($drive.UsedPercent)%)",
        "Free Space: $(Format-FileSize $drive.Free)"
    ) -BorderColor Green -TitleColor Yellow

    Write-Host " Used: " -NoNewline -ForegroundColor White
    Show-ProgressBar -PercentComplete $drive.UsedPercent -Width 70 -FillColor Cyan -ShowPercent
    Write-Host "   Free: $(Format-FileSize $drive.Free)" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  $($script:Sym.Scan) Scanning ${letter}:\ - this can take a few minutes on a large drive..." -ForegroundColor Cyan
    Write-Host "     (press Ctrl+C to abort)" -ForegroundColor DarkGray

    $script:ProgressWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $scanWatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        [uint64]$totalScanned = Get-DirectorySize -Path "${letter}:\" -CurrentDepth 0 -RecordDepth $RecordDepth
    } finally {
        $scanWatch.Stop()
        Write-Progress -Activity "DriveX-Ray scan" -Completed
    }

    $duration = $scanWatch.Elapsed

    # Sort, trim and compute display fields once, after the scan.
    $sortedFiles   = @($script:Results.LargestFiles   | Sort-Object -Property Size -Descending | Select-Object -First ([Math]::Max(100, $RowCount)))
    $sortedFolders = @($script:Results.LargestFolders | Sort-Object -Property Size -Descending | Select-Object -First 500)

    foreach ($f in $sortedFiles) { $f.SizeFormatted = Format-FileSize $f.Size }
    foreach ($f in $sortedFolders) {
        $f.SizeFormatted = Format-FileSize $f.Size
        if ($drive.Used -gt 0) {
            $f.SizePercentage = [Math]::Round(([double]$f.Size / [double]$drive.Used) * 100, 3)
        }
    }

    $script:Results.LargestFiles.Clear()
    foreach ($f in $sortedFiles) { [void]$script:Results.LargestFiles.Add($f) }
    $script:Results.LargestFolders.Clear()
    foreach ($f in $sortedFolders) { [void]$script:Results.LargestFolders.Add($f) }

    Write-Host ""
    Write-Host "  $($script:Sym.Ok) Scan complete" -ForegroundColor Green
    Write-Host ("  $($script:Sym.Clock) Duration: {0:hh\:mm\:ss}" -f $duration) -ForegroundColor Gray
    Write-Host ("  $($script:Sym.Folder) Folders: {0:N0}  |  $($script:Sym.File) Files: {1:N0}  |  $($script:Sym.Block) Unreadable: {2:N0}  |  $($script:Sym.Link) Links skipped: {3:N0}" -f
        $script:Results.FoldersScanned, $script:Results.FilesScanned,
        $script:Results.SkippedFolders, $script:Results.SkippedLinks) -ForegroundColor Gray

    $coverage = 0.0
    if ($drive.Used -gt 0) { $coverage = ([double]$totalScanned / [double]$drive.Used) * 100 }
    Write-Host ("  $($script:Sym.Chart) Measured: {0} of {1} used ({2:F1}% coverage)  |  Deepest level: {3}" -f
        (Format-FileSize $totalScanned), (Format-FileSize $drive.Used),
        $coverage, $script:Results.MaxDepthReached) -ForegroundColor Cyan

    if ($coverage -lt 90) {
        Write-Host "  $($script:Sym.Warn) Coverage is low - run as Administrator to reach protected system folders." -ForegroundColor Yellow
    }

    Show-TreemapVisualization -FolderData $script:Results.LargestFolders -UsedSpace $drive.Used -ScannedSize $totalScanned
    Show-FolderTable -Data $script:Results.LargestFolders -Count $RowCount
    Show-FileTable   -Data $script:Results.LargestFiles   -Count $RowCount
    Show-ExtensionTable -UsedSpace $drive.Used

    return @{
        DriveLetter  = $letter
        Drive        = $drive
        ScannedSize  = $totalScanned
        ScanDuration = $duration
    }
}

#endregion

#region -- Entry point ---------------------------------------------------------

function Test-IsAdministrator {
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false   # non-Windows or restricted host
    }
}

function Show-DriveMenu {
    param ([array]$Drives)

    $content = @("Drives available for analysis:", "")
    foreach ($d in $Drives) {
        $content += ("  {0}:  {1,10} used of {2,10}  ({3,5:F1}%)   {4} free" -f
            $d.Name, (Format-FileSize $d.Used), (Format-FileSize $d.Total),
            $d.UsedPercent, (Format-FileSize $d.Free))
    }
    Show-InfoBox -Title "AVAILABLE DRIVES" -Content $content -BorderColor Yellow -TitleColor Green
}

function Invoke-DriveXRay {
    param (
        [string]$Drive,
        [int]$MaxDepth,
        [int]$Top,
        [string]$ExportPath,
        [switch]$NonInteractive
    )

    Clear-Host
    Show-AnimatedBanner

    if (Test-IsAdministrator) {
        Show-InfoBox -Title "ADMIN STATUS" -Content @(
            "$($script:Sym.Ok) Running with Administrator privileges",
            "$($script:Sym.Unlock) Full system access enabled"
        ) -BorderColor Green -TitleColor White -Center
    } else {
        Show-InfoBox -Title "ADMIN WARNING" -Content @(
            "$($script:Sym.Warn) Running without Administrator privileges",
            "$($script:Sym.Lock) Some system folders will be skipped"
        ) -BorderColor Red -TitleColor Yellow

        if (-not $NonInteractive) {
            Write-Host ""
            $continue = Read-Host "  Continue with limited access? (Y/N)"
            if ($continue -notmatch '^\s*y') { return }
        }
    }

    $drives = @(Get-DriveInventory)
    if ($drives.Count -eq 0) {
        Write-Host ""
        Write-Host "  $($script:Sym.Fail) No usable filesystem drives were found." -ForegroundColor Red
        return
    }
    $driveLetters = @($drives | Select-Object -ExpandProperty Name)

    # ---- Pick the first drive ----
    $letter = $null
    if ($Drive) {
        $letter = Resolve-DriveLetter -Text $Drive -Valid $driveLetters
        if (-not $letter) {
            Write-Host ""
            Write-Host "  $($script:Sym.Fail) '$Drive' is not one of: $($driveLetters -join ', ')" -ForegroundColor Red
            return
        }
    } else {
        Show-DriveMenu -Drives $drives
        Write-Host ""
        Write-Host "  $($script:Sym.Disk) Available: " -NoNewline -ForegroundColor Green
        Write-Host ($driveLetters -join ", ") -ForegroundColor Cyan
        Write-Host ""

        $letter = Resolve-DriveLetter -Text (Read-Host "  Enter drive letter to analyze") -Valid $driveLetters
        if (-not $letter) {
            Write-Host "  $($script:Sym.Fail) Invalid drive selection." -ForegroundColor Red
            return
        }
    }

    $lastResult = Invoke-DriveAnalysis -DriveLetter $letter -RecordDepth $MaxDepth -RowCount $Top
    if ($NonInteractive) { return }

    # ---- Post-scan menu ----
    while ($true) {
        Write-Host ""
        Write-Host "  +------------ DriveX-Ray Menu -------------+" -ForegroundColor Cyan
        Write-Host "  |  [R] Rescan current drive                |" -ForegroundColor White
        Write-Host "  |  [D] Scan a different drive              |" -ForegroundColor White
        Write-Host "  |  [E] Export results to CSV               |" -ForegroundColor White
        Write-Host "  |  [Q] Quit                                |" -ForegroundColor White
        Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
        Write-Host ""

        $choice = (Read-Host "  Choice").Trim().ToUpperInvariant()

        try {
            switch ($choice) {
                'R' {
                    if ($lastResult) {
                        $lastResult = Invoke-DriveAnalysis -DriveLetter $lastResult.DriveLetter -RecordDepth $MaxDepth -RowCount $Top
                    } else {
                        Write-Host "  No previous scan to repeat." -ForegroundColor Yellow
                    }
                }
                'D' {
                    $drives       = @(Get-DriveInventory)   # refresh: media may have changed
                    $driveLetters = @($drives | Select-Object -ExpandProperty Name)
                    Show-DriveMenu -Drives $drives
                    $next = Resolve-DriveLetter -Text (Read-Host "  Enter drive letter") -Valid $driveLetters
                    if ($next) {
                        $lastResult = Invoke-DriveAnalysis -DriveLetter $next -RecordDepth $MaxDepth -RowCount $Top
                    } else {
                        Write-Host "  $($script:Sym.Fail) Invalid drive." -ForegroundColor Red
                    }
                }
                'E' {
                    if ($lastResult) {
                        Export-ResultsCsv -DriveLetter $lastResult.DriveLetter -Destination $ExportPath
                    } else {
                        Write-Host "  No results to export. Run a scan first." -ForegroundColor Yellow
                    }
                }
                'Q' {
                    Write-Host ""
                    Write-Host "  $($script:Sym.Wave) Thanks for using DriveX-Ray." -ForegroundColor Cyan
                    Write-Host ""
                    return
                }
                default { Write-Host "  Invalid choice. Use R, D, E or Q." -ForegroundColor Yellow }
            }
        } catch {
            # A failure in one action should not drop the user out of the menu.
            Write-Host ""
            Write-Host "  $($script:Sym.Fail) $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

try {
    Invoke-DriveXRay -Drive $Drive -MaxDepth $MaxDepth -Top $Top `
                     -ExportPath $ExportPath -NonInteractive:$NonInteractive
} catch [System.Management.Automation.PipelineStoppedException] {
    Write-Host ""
    Write-Host "  Scan cancelled." -ForegroundColor Yellow
} catch {
    Write-Host ""
    Write-Host "  $($script:Sym.Fail) Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkGray
} finally {
    Write-Progress -Activity "DriveX-Ray scan" -Completed
    $ErrorActionPreference = $script:PreviousErrorActionPreference
    # When launched via `irm ... | iex` the script scope *is* the global scope,
    # so tidy up rather than leaving state behind in the user's session.
    Remove-Variable -Name Results, EntryCounter, ProgressWatch, EnumOptions,
                          ConsoleWidth, UseEmoji, TraversalLimit,
                          FileThreshold, FolderThreshold,
                          FileTrimAt, FileKeep, FolderTrimAt, FolderKeep,
                          PreviousErrorActionPreference `
                    -Scope Script -ErrorAction SilentlyContinue
}

#endregion
