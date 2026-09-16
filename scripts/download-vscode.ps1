#Requires -Version 7
<#
  VS Code 1.95.3 本体 / VS Code Server / VS Code CLI を update.code.visualstudio.com から取得し、
  公式APIが返す sha256 と照合して保存する。
  既に検証済みのファイルがあればスキップするので、何度実行しても安全。

  使い方:  pwsh ./scripts/download-vscode.ps1 [-Root <保存先ディレクトリ>]
#>
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent)
)
$ErrorActionPreference = 'Stop'
$Version = '1.95.3'
$Commit  = 'f1a4fb101478ce6ec82fe9627c43efbf9e98c813'
$Quality = 'stable'

# dir: 保存先サブディレクトリ / ver: APIのバージョン指定 / target: update API のターゲット名
$items = @(
    # ---- クライアント本体 ----
    @{ dir = 'client/windows'; ver = $Version; target = 'win32-x64-user' }       # ユーザーインストーラ
    @{ dir = 'client/windows'; ver = $Version; target = 'win32-x64' }            # システムインストーラ
    @{ dir = 'client/windows'; ver = $Version; target = 'win32-x64-archive' }    # zip (展開するだけ)
    @{ dir = 'client/windows'; ver = $Version; target = 'win32-arm64-user' }
    @{ dir = 'client/windows'; ver = $Version; target = 'win32-arm64' }
    @{ dir = 'client/windows'; ver = $Version; target = 'win32-arm64-archive' }
    @{ dir = 'client/macos';   ver = $Version; target = 'darwin-universal' }
    @{ dir = 'client/macos';   ver = $Version; target = 'darwin' }               # Intel
    @{ dir = 'client/macos';   ver = $Version; target = 'darwin-arm64' }         # Apple Silicon
    @{ dir = 'client/linux';   ver = $Version; target = 'linux-deb-x64' }
    @{ dir = 'client/linux';   ver = $Version; target = 'linux-rpm-x64' }
    @{ dir = 'client/linux';   ver = $Version; target = 'linux-x64' }            # tar.gz
    @{ dir = 'client/linux';   ver = $Version; target = 'linux-deb-arm64' }
    @{ dir = 'client/linux';   ver = $Version; target = 'linux-rpm-arm64' }
    @{ dir = 'client/linux';   ver = $Version; target = 'linux-arm64' }          # tar.gz
    # ---- VS Code Server (Remote - SSH がリモートに置くもの。コミット単位) ----
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-linux-x64' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-linux-arm64' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-linux-armhf' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-linux-legacy-x64' }    # 古い glibc 向け
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-linux-legacy-arm64' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-linux-legacy-armhf' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-linux-alpine' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-alpine-arm64' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-darwin' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-darwin-arm64' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-win32-x64' }
    @{ dir = 'server'; ver = "commit:$Commit"; target = 'server-win32-arm64' }
    # ---- VS Code Server (web UI 同梱版。code serve-web / ブラウザ利用向け) ----
    @{ dir = 'server/web'; ver = "commit:$Commit"; target = 'server-linux-x64-web' }
    @{ dir = 'server/web'; ver = "commit:$Commit"; target = 'server-linux-arm64-web' }
    # ---- VS Code CLI (Remote - SSH の exec server / code tunnel / code serve-web が使う) ----
    @{ dir = 'cli'; ver = "commit:$Commit"; target = 'cli-alpine-x64' }     # Remote-SSH が Linux ホストに置く静的リンク版
    @{ dir = 'cli'; ver = "commit:$Commit"; target = 'cli-alpine-arm64' }
    @{ dir = 'cli'; ver = "commit:$Commit"; target = 'cli-linux-x64' }
    @{ dir = 'cli'; ver = "commit:$Commit"; target = 'cli-linux-arm64' }
    @{ dir = 'cli'; ver = "commit:$Commit"; target = 'cli-linux-armhf' }
    @{ dir = 'cli'; ver = "commit:$Commit"; target = 'cli-darwin-x64' }
    @{ dir = 'cli'; ver = "commit:$Commit"; target = 'cli-darwin-arm64' }
    @{ dir = 'cli'; ver = "commit:$Commit"; target = 'cli-win32-x64' }
    @{ dir = 'cli'; ver = "commit:$Commit"; target = 'cli-win32-arm64' }
)

function Get-Sha256Lower([string]$path) { (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower() }

$manifest = @()
$failed = @()
foreach ($it in $items) {
    $target = $it.target
    try {
        $info = Invoke-RestMethod "https://update.code.visualstudio.com/api/versions/$($it.ver)/$target/$Quality"
        if ($info.version -ne $Commit) { throw "API returned commit $($info.version), expected $Commit" }
        $url = $info.url
        $expectedHash = $info.sha256hash.ToLower()
        $name = [System.IO.Path]::GetFileName(([uri]$url).AbsolutePath)
        $dir = Join-Path $Root $it.dir
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $dest = Join-Path $dir $name
        $part = "$dest.part"
        $head = Invoke-WebRequest -Uri $url -Method Head
        $expectedSize = [int64]($head.Headers['Content-Length'] | Select-Object -First 1)

        $ok = $false
        if (Test-Path $dest) {
            if ((Get-Item $dest).Length -eq $expectedSize -and (Get-Sha256Lower $dest) -eq $expectedHash) {
                $ok = $true
                Write-Host "[skip] $target -> $name (already verified)"
            } else {
                Write-Host "[redo] $target -> $name (existing file failed verification)"
                Remove-Item $dest -Force
            }
        }
        if (-not $ok) {
            Write-Host "[get ] $target -> $name ($([math]::Round($expectedSize / 1MB, 1)) MB)"
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                if ((Test-Path $part) -and (Get-Item $part).Length -eq $expectedSize) { break }
                & curl.exe -L --fail --silent --show-error --connect-timeout 30 --retry 5 --retry-delay 3 -C - -o $part $url
                if ($LASTEXITCODE -eq 0) { break }
                Write-Host "       curl exit $LASTEXITCODE (attempt $attempt)"
            }
            if (-not (Test-Path $part) -or (Get-Item $part).Length -ne $expectedSize) { throw "size mismatch after download: $name" }
            $hash = Get-Sha256Lower $part
            if ($hash -ne $expectedHash) { Remove-Item $part -Force; throw "sha256 mismatch: $name (got $hash, expected $expectedHash)" }
            Move-Item $part $dest -Force
            Write-Host "[ ok ] $name sha256 verified"
        }
        $manifest += [pscustomobject]@{
            target = $target; file = "$($it.dir)/$name"; size = $expectedSize; sha256 = $expectedHash; url = $url
        }
    } catch {
        Write-Host "[FAIL] $target : $($_.Exception.Message)"
        $failed += $target
    }
}

# LF 改行・BOM なしで書く (sha256sum -c が CRLF を受け付けないため)
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $Root 'manifest-vscode.json'), (($manifest | ConvertTo-Json -Depth 3) -replace "`r`n", "`n") + "`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $Root 'SHA256SUMS-vscode.txt'), (($manifest | ForEach-Object { "$($_.sha256)  $($_.file)" }) -join "`n") + "`n", $utf8)
Write-Host ""
Write-Host "done: $($manifest.Count) files verified, $($failed.Count) failed"
if ($failed.Count) { Write-Host "failed targets: $($failed -join ', ')"; exit 1 }
