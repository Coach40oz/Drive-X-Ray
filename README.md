# Drive-X-Ray

**Visual disk space analyzer for the PowerShell console**

Drive-X-Ray tells you what is actually eating your disk. It scans a drive and
reports the largest folders, the largest files and a breakdown by file type,
all rendered as colour-coded tables and a treemap in the terminal. No install,
no dependencies, one script.

---

## Features

- **Fast .NET scan engine** — enumerates with `DirectoryInfo.EnumerateFileSystemInfos()`, reading size and attributes straight from the directory entry instead of re-stat'ing every file
- **Accurate sizes** — the whole tree is always measured; the depth setting limits how much is *listed*, never what is *counted*
- **Junction- and symlink-aware** — reparse points are skipped, so `C:\Users\All Users` is not counted a second time as `C:\ProgramData`
- **Treemap that adds up** — top-level folders plus explicit "files in drive root" and "not scanned" rows, so the percentages total 100%
- **Largest files and folders** — colour-coded tables with size, share of used space and last-modified date
- **File type analysis** — space by extension, with proportional bars
- **Coverage reporting** — tells you how much of the drive it could actually read, and warns when running unelevated costs you visibility
- **Post-scan menu** — rescan, switch drives, or export without restarting
- **CSV export** — files, folders and file types, written to the Desktop or a path you choose
- **Scriptable** — `-Drive`, `-MaxDepth`, `-Top`, `-ExportPath`, `-NonInteractive`
- **Adapts to your terminal** — every box and table is sized from the real console width
- **Works elevated or not** — inaccessible folders are counted and reported rather than aborting the scan

## Requirements

- Windows
- PowerShell 5.1 or later (PowerShell 7+ is faster and renders emoji)
- Administrator rights are optional but improve coverage of protected system folders

## Quick start

### Run directly from GitHub

```powershell
irm https://raw.githubusercontent.com/Coach40oz/Drive-X-Ray/main/DriveX-Ray.ps1 | iex
```

On Windows PowerShell 5.1:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/Coach40oz/Drive-X-Ray/main/DriveX-Ray.ps1'))
```

### Download and run locally

```powershell
git clone https://github.com/Coach40oz/Drive-X-Ray.git
cd Drive-X-Ray
.\DriveX-Ray.ps1
```

## Usage

Run it with no arguments for the interactive flow: pick a drive from the
detected list, watch the progress counter, then browse the report and use the
post-scan menu.

| Key | Action |
|-----|--------|
| `R` | Rescan the current drive |
| `D` | Scan a different drive |
| `E` | Export results to CSV |
| `Q` | Quit |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Drive` | *(prompts)* | Drive to scan. Accepts `C`, `C:` or `C:\` |
| `-MaxDepth` | `8` | How many folder levels are **listed**. `1` = top-level folders only. Does not affect measured sizes |
| `-Top` | `25` | Rows in the file and folder tables |
| `-ExportPath` | Desktop | Where `[E]` writes the CSV files |
| `-NonInteractive` | off | Scan, print the report and exit. Use with `-Drive` |

```powershell
# Just the top-level breakdown of C:, 40 rows
.\DriveX-Ray.ps1 -Drive C -MaxDepth 1 -Top 40

# Unattended: scan D: and exit
.\DriveX-Ray.ps1 -Drive D -NonInteractive
```

## Reading the output

- **Drive statistics** — total, used and free, with a usage bar
- **Scan summary** — folders and files scanned, folders that could not be read, links skipped, and the **coverage** percentage. Coverage well below 100% usually means you should re-run elevated
- **Treemap** — top-level folders as a share of used space. Because only depth-0 folders are shown, plus rows for loose root files and unreadable space, the bars partition the drive and sum to 100%
- **Largest folders** — sizes are cumulative, so a folder includes everything nested inside it. `% Used` is its share of used space, and `Depth` is its level below the drive root
- **Largest files** — the individual files worth deleting first
- **File type analysis** — where space goes by extension

## Technical notes

| Component | Detail |
|-----------|--------|
| Scan engine | `DirectoryInfo.EnumerateFileSystemInfos()`; size, attributes and timestamps come from the enumeration itself, so scanning a file costs no extra I/O |
| Access errors | `EnumerationOptions.IgnoreInaccessible` on PowerShell 7+; on 5.1 the enumerator's `MoveNext()` is guarded per directory, so one unreadable folder cannot abort the scan |
| Reparse points | Junctions and symlinks are detected via `FileAttributes.ReparsePoint` and skipped, preventing double-counting and traversal cycles |
| Depth | Traversal is unbounded (hard safety cap of 64 levels); `-MaxDepth` only limits which folders are listed |
| Memory | Candidate lists self-trim, raising the size threshold to the smallest survivor, so a multi-TB drive does not accumulate hundreds of thousands of objects |
| Size handling | `[uint64]` throughout, with explicit casts where PowerShell would otherwise promote to `double` |
| Progress | Throttled to ~5 updates/second so `Write-Progress` does not dominate the scan |
| Encoding | The source is pure ASCII. Box-drawing characters and emoji are built from code points at runtime, so the script renders correctly whether it is dot-sourced on a 5.1 ANSI console or piped through `iex` |
| Scoping | All state is `$script:` scoped and removed on exit |

## Development

Static analysis:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path .\DriveX-Ray.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
```

`PSScriptAnalyzerSettings.psd1` disables two rules that do not apply to an
interactive console application; everything else is expected to stay clean.

## Contributing

Contributions, issues and feature requests are welcome — see the
[issues page](https://github.com/Coach40oz/Drive-X-Ray/issues).

## License

[GNU General Public License v3.0](LICENSE)

## Author

Created by [Ulises Paiz](https://github.com/Coach40oz)
