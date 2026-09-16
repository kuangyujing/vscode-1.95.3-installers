#Requires -Version 7
<#
  このPCの VS Code にインストール済みの拡張を、インストール済みと同じバージョンの .vsix として
  Marketplace から取得し、zip として開けること・package.json のバージョンが一致することを確認して保存する。
  既に検証済みの .vsix があればスキップするので、何度実行しても安全。

  使い方:  pwsh ./scripts/download-extensions.ps1 [-Root <保存先>] [-ExtensionsJson <extensions.json のパス>]
#>
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [string]$ExtensionsJson = "$env:USERPROFILE\.vscode\extensions\extensions.json"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$outDir = Join-Path $Root 'extensions'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$ext = Get-Content $ExtensionsJson -Raw | ConvertFrom-Json | Sort-Object { $_.identifier.id }

function Test-Vsix([string]$path) {
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
        try { return ($null -ne $zip.GetEntry('extension.vsixmanifest')) -and ($null -ne $zip.GetEntry('extension/package.json')) }
        finally { $zip.Dispose() }
    } catch { return $false }
}

# vspackage エンドポイントは gzip 圧縮したまま返すことがあるので、その場合は展開する
function Repair-GzipFile([string]$path) {
    $fs = [System.IO.File]::OpenRead($path); $b = New-Object byte[] 2; [void]$fs.Read($b, 0, 2); $fs.Dispose()
    if ($b[0] -eq 0x1f -and $b[1] -eq 0x8b) {
        $tmp = "$path.gunzip"
        $in = [System.IO.File]::OpenRead($path)
        $gz = New-Object System.IO.Compression.GZipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
        $out = [System.IO.File]::Create($tmp)
        $gz.CopyTo($out); $out.Dispose(); $gz.Dispose(); $in.Dispose()
        Move-Item $tmp $path -Force
    }
}

function Read-PackageJson([string]$path) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($path)
    try {
        $sr = New-Object System.IO.StreamReader($zip.GetEntry('extension/package.json').Open())
        try { return ($sr.ReadToEnd() | ConvertFrom-Json) } finally { $sr.Dispose() }
    } finally { $zip.Dispose() }
}

$manifest = @(); $failed = @()
foreach ($x in $ext) {
    $id = $x.identifier.id; $ver = $x.version
    $publisher, $name = $id.Split('.', 2)
    $tp = $x.metadata.targetPlatform
    $suffix = if ($tp -and $tp -ne 'undefined' -and $tp -ne 'universal') { "@$tp" } else { '' }
    $query = if ($suffix) { "?targetPlatform=$tp" } else { '' }
    $file = "$id-$ver$suffix.vsix"
    $dest = Join-Path $outDir $file
    $urls = @(
        "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$publisher/vsextensions/$name/$ver/vspackage$query"
        "https://$publisher.gallery.vsassets.io/_apis/public/gallery/publisher/$publisher/extension/$name/$ver/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage$query"
    )
    if ((Test-Path $dest) -and (Test-Vsix $dest)) {
        Write-Host "[skip] $file"
    } else {
        $got = $false
        foreach ($u in $urls) {
            $part = "$dest.part"
            Remove-Item $part -Force -ErrorAction SilentlyContinue
            & curl.exe -L --fail --silent --show-error --compressed --connect-timeout 30 --retry 5 --retry-delay 3 -o $part $u
            if ($LASTEXITCODE -eq 0 -and (Test-Path $part)) {
                Repair-GzipFile $part
                if (Test-Vsix $part) { Move-Item $part $dest -Force; $got = $true; Write-Host "[ ok ] $file"; break }
            }
            Write-Host "       failed: $u (curl exit $LASTEXITCODE)"
        }
        if (-not $got) { Write-Host "[FAIL] $file"; $failed += $id; continue }
    }
    $pkg = Read-PackageJson $dest
    if ($pkg.version -ne $ver) { Write-Host "[WARN] $file : package.json version is $($pkg.version)" }
    $manifest += [pscustomobject]@{
        id = $id; version = $ver
        targetPlatform = if ($suffix) { $tp } else { 'universal' }
        engine = $pkg.engines.vscode
        extensionKind = ($pkg.extensionKind -join ',')
        file = "extensions/$file"
        size = (Get-Item $dest).Length
        sha256 = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
    }
}

# LF 改行・BOM なしで書く (sha256sum -c が CRLF を受け付けないため)
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $Root 'manifest-extensions.json'), (($manifest | ConvertTo-Json -Depth 3) -replace "`r`n", "`n") + "`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $Root 'SHA256SUMS-extensions.txt'), (($manifest | ForEach-Object { "$($_.sha256)  $($_.file)" }) -join "`n") + "`n", $utf8)
$manifest | Format-Table id, version, engine, extensionKind, size -AutoSize | Out-String -Width 200 | Write-Host
Write-Host "done: $($manifest.Count) vsix, $($failed.Count) failed"
if ($failed.Count) { Write-Host "failed: $($failed -join ', ')"; exit 1 }
