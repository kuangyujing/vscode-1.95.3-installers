# VS Code 1.95.3 Offline Kit

Everything needed to install VS Code 1.95.3 on the client PCs and to place the VS Code Server on Remote - SSH hosts without access to Microsoft's download servers.

This document is written for an AI agent that performs the installation and configuration. Follow the steps literally and run the verification commands.

## 0. Invariants

- VS Code 1.95.3, quality `stable`, commit `f1a4fb101478ce6ec82fe9627c43efbf9e98c813`. Every file here is tied to this commit. Never mix with another version or commit.
- Remote - SSH extension 0.115.1 (requires VS Code `^1.93.0`). Do not upgrade it.
- Auto-update stays disabled on every client (3.2).
- "VS Code Server" below means the server that Remote - SSH places under `~/.vscode-server` on a remote host (executable `bin/code-server`). It is unrelated to coder's "code-server".
- To read version and commit of an installed client: `code --version` (line 1 = version, line 2 = commit) or `resources/app/product.json` (`version`, `commit`).

## 1. Contents

```
client/windows/   VSCodeUserSetup-{x64,arm64}-1.95.3.exe   VSCodeSetup-{x64,arm64}-1.95.3.exe   VSCode-win32-{x64,arm64}-1.95.3.zip
client/macos/     VSCode-darwin-universal.zip   VSCode-darwin.zip (Intel)   VSCode-darwin-arm64.zip
client/linux/     code_1.95.3-*_{amd64,arm64}.deb   code-1.95.3-*.el8.{x86_64,aarch64}.rpm   code-stable-{x64,arm64}-*.tar.gz
server/           vscode-server-linux-{x64,arm64,armhf}.tar.gz   vscode-server-linux-legacy-{x64,arm64,armhf}.tar.gz
                  vscode-server-linux-alpine.tar.gz   vscode-server-alpine-arm64.tar.gz
                  vscode-server-darwin-{x64,arm64}.zip   vscode-server-win32-{x64,arm64}.zip
server/web/       vscode-server-linux-{x64,arm64}-web.tar.gz      (only for `code serve-web`; Remote - SSH does not use these)
cli/              vscode_cli_{alpine_x64,alpine_arm64,linux_x64,linux_arm64,linux_armhf}_cli.tar.gz
                  vscode_cli_{darwin_x64,darwin_arm64,win32_x64,win32_arm64}_cli.zip
extensions/       23 files named <publisher>.<name>-<version>.vsix
scripts/          download-vscode.ps1, download-extensions.ps1 (re-download; verified files are skipped), *.log
manifest-vscode.json, SHA256SUMS-vscode.txt          38 files: target, path, size, sha256 (from the official update API), source URL
manifest-extensions.json, SHA256SUMS-extensions.txt  23 files: id, version, engine, extensionKind, size, sha256
```

Archive layouts (all archives checked):

- CLI archives contain exactly one file, `code` (`code.exe` in the win32 zips).
- Server archives contain one top-level directory `vscode-server-<platform>/` with `bin/code-server` (`bin\code-server.cmd` on Windows), `node` (`node.exe`), `product.json`, ... . Strip that directory when extracting. The legacy tarballs use the same top-level name as the non-legacy ones (`vscode-server-linux-x64` etc.).

## 2. Verify integrity before use

Run from the kit root. Expect no `FAILED` output.

```
# Linux
sha256sum -c SHA256SUMS-vscode.txt && sha256sum -c SHA256SUMS-extensions.txt
# macOS
shasum -a 256 -c SHA256SUMS-vscode.txt && shasum -a 256 -c SHA256SUMS-extensions.txt
# Windows (PowerShell 7)
Get-Content SHA256SUMS-vscode.txt, SHA256SUMS-extensions.txt | ForEach-Object { $h, $f = $_ -split '  ', 2; if ((Get-FileHash $f -Algorithm SHA256).Hash -ine $h) { "FAILED $f" } }
```

## 3. Client PCs

### 3.1 Install

| OS | File | Action | `code` CLI afterwards |
|---|---|---|---|
| Windows, portable (how this PC is set up) | `client/windows/VSCode-win32-x64-1.95.3.zip` | Extract to `C:\Code` | `C:\Code\bin\code.cmd` |
| Windows, per-user installer | `client/windows/VSCodeUserSetup-x64-1.95.3.exe` | `VSCodeUserSetup-x64-1.95.3.exe /VERYSILENT /MERGETASKS=!runcode` | `%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd` |
| Windows, system-wide installer | `client/windows/VSCodeSetup-x64-1.95.3.exe` | same flags, needs admin | `C:\Program Files\Microsoft VS Code\bin\code.cmd` |
| macOS | `client/macos/VSCode-darwin-universal.zip` | `unzip`, move `Visual Studio Code.app` to `/Applications` | `/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code` |
| Linux, Debian/Ubuntu | `client/linux/code_1.95.3-*_amd64.deb` | `sudo apt install ./code_1.95.3-*_amd64.deb` | `/usr/bin/code` |
| Linux, RHEL/Fedora | `client/linux/code-1.95.3-*.el8.x86_64.rpm` | `sudo dnf install ./code-1.95.3-*.el8.x86_64.rpm` | `/usr/bin/code` |
| Linux, other | `client/linux/code-stable-x64-*.tar.gz` | extract anywhere | `<dir>/bin/code` |

Use the arm64 variants on arm64 machines. Verify: `code --version` prints `1.95.3` and `f1a4fb101478ce6ec82fe9627c43efbf9e98c813`.

### 3.2 Settings (user `settings.json`)

Required on every client (already present on this PC):

```jsonc
"update.mode": "none",
"extensions.autoUpdate": "off",
"extensions.autoCheckUpdates": false
```

Remote - SSH settings that affect server download. Keep the defaults unless a step says otherwise.

| Setting | Default | Effect |
|---|---|---|
| `remote.SSH.useExecServer` | `true` | `true`: CLI-based layout (4.2). `false`: legacy layout (4.3). |
| `remote.SSH.localServerDownload` | `"auto"` | `auto`: host downloads, falls back to download on the client + scp. `always`: client only. `off`: host only. Irrelevant once files are pre-placed. |
| `remote.SSH.serverInstallPath` | `null` | `{"<host>": "/abs/path"}` uses `/abs/path/.vscode-server` instead of `~/.vscode-server` for that host. |
| `remote.SSH.remotePlatform` | `null` | This PC has `{"C2": "linux", "ATR": "macOS"}`. |

### 3.3 Extensions

```
# Windows:      Get-ChildItem extensions\*.vsix | ForEach-Object { code --install-extension $_.FullName }
# macOS/Linux:  for f in extensions/*.vsix; do code --install-extension "$f"; done
code --list-extensions --show-versions      # expect the 23 id@version pairs from manifest-extensions.json
```

- All 23 are universal (no platform-specific builds). The same file works on every OS and on remote hosts.
- `ms-vscode-remote.remote-ssh` 0.115.1 is an extension pack referencing `ms-vscode-remote.remote-ssh-edit` (included) and `ms-vscode.remote-explorer` (not installed on this PC, not included, not required).

## 4. VS Code Server on remote hosts

Facts, taken from the install scripts embedded in Remote - SSH 0.115.1 and from VS Code 1.95.3 `cli/src`:

- Both modes check for an existing installation before downloading anything. Pre-placed files mean no network access is attempted.
- If a download is needed and the host cannot reach `update.code.visualstudio.com`, the download is retried through the client PC (exec-server mode: CLI delegates HTTP over the SSH connection; legacy mode: client downloads and copies with scp). Manual placement is only required when the client cannot download either.
- Server data directory is `~/.vscode-server` (product.json `serverDataFolderName`). Remote extensions live in `~/.vscode-server/extensions`, user data in `~/.vscode-server/data`.
- Old installs are pruned to the 5 most recent (`code-<40hex>` files; `cli/servers/lru.json`; `bin/`). Not a concern with one pinned commit.

### 4.1 Choose the artifacts

On the host: `uname -m` (arch), `ldd --version | head -1` (glibc), `ls /lib/ld-musl-* 2>/dev/null` (musl).

| Host | CLI file (exec-server mode only) | Server file |
|---|---|---|
| Linux x86_64, glibc >= 2.28 and libstdc++ GLIBCXX >= 3.4.25 (any current AWS/Azure image) | `cli/vscode_cli_alpine_x64_cli.tar.gz` | `server/vscode-server-linux-x64.tar.gz` |
| Linux x86_64, glibc 2.17 - 2.27 (GLIBCXX >= 3.4.19) | same | `server/vscode-server-linux-legacy-x64.tar.gz` |
| Linux aarch64 | `cli/vscode_cli_alpine_arm64_cli.tar.gz` | `server/vscode-server-linux-arm64.tar.gz` (old glibc: `-legacy-arm64`) |
| Linux armv7l | `cli/vscode_cli_linux_armhf_cli.tar.gz` | `server/vscode-server-linux-armhf.tar.gz` (GLIBCXX >= 3.4.26; legacy build: >= 3.4.22) |
| Alpine / musl | `cli/vscode_cli_alpine_{x64,arm64}_cli.tar.gz` | `server/vscode-server-linux-alpine.tar.gz` or `server/vscode-server-alpine-arm64.tar.gz` |
| macOS Intel / Apple Silicon | `cli/vscode_cli_darwin_{x64,arm64}_cli.zip` | `server/vscode-server-darwin-{x64,arm64}.zip` |

These are the rules the CLI itself applies (`cli/src/util/prereqs.rs`) and the download names the install scripts use. In exec-server mode the CLI does not check which server build was pre-placed; choose correctly.

### 4.2 Exec-server mode (default): manual placement

Target layout:

```
~/.vscode-server/
  code-<commit>                                 CLI binary = the file "code" from the CLI archive, executable
  cli/servers/Stable-<commit>/server/           server archive contents, top-level directory stripped
```

Files created later at runtime: `~/.vscode-server/.cli.<commit>.log`, `cli/servers/Stable-<commit>/{log.txt,pid.txt}`, `cli/servers/lru.json`.

Steps for a Linux x86_64 host, run as the SSH login user (swap file names per 4.1):

```sh
scp cli/vscode_cli_alpine_x64_cli.tar.gz server/vscode-server-linux-x64.tar.gz <host>:/tmp/
ssh <host>

COMMIT=f1a4fb101478ce6ec82fe9627c43efbf9e98c813
mkdir -p ~/.vscode-server && chmod 750 ~/.vscode-server
tar -xzf /tmp/vscode_cli_alpine_x64_cli.tar.gz -C ~/.vscode-server         # produces ~/.vscode-server/code
mv ~/.vscode-server/code ~/.vscode-server/code-$COMMIT
chmod +x ~/.vscode-server/code-$COMMIT
mkdir -p ~/.vscode-server/cli/servers/Stable-$COMMIT/server
tar -xzf /tmp/vscode-server-linux-x64.tar.gz --strip-components 1 --no-same-owner -C ~/.vscode-server/cli/servers/Stable-$COMMIT/server
rm -f /tmp/vscode_cli_alpine_x64_cli.tar.gz /tmp/vscode-server-linux-x64.tar.gz

# verify: both commands must succeed and print 1.95.3 and the commit
~/.vscode-server/code-$COMMIT --version
~/.vscode-server/cli/servers/Stable-$COMMIT/server/bin/code-server --version
test -x ~/.vscode-server/cli/servers/Stable-$COMMIT/server/node && echo node-ok
```

macOS host: replace the two `tar -xzf` lines with `unzip -o /tmp/vscode_cli_darwin_<arch>_cli.zip -d ~/.vscode-server` and `tar -xf /tmp/vscode-server-darwin-<arch>.zip --strip-components 1 -C ~/.vscode-server/cli/servers/Stable-$COMMIT/server` (macOS `tar` is bsdtar and extracts zip).

What Remote - SSH does on the next connection: the install script finds `code-<commit>` and logs `Found existing installation at /home/<user>/.vscode-server...`, then runs `code-<commit> command-shell --cli-data-dir ~/.vscode-server/cli --parent-process-id <pid> --on-host=127.0.0.1 --on-port`. On the client's `serve` request the CLI finds `cli/servers/Stable-<commit>` (existence check only) and starts `server/bin/code-server --start-server --enable-remote-auto-shutdown --socket-path=... --connection-token=... --accept-server-license-terms`. Without that directory it would download `server-linux-x64` from `update.code.visualstudio.com`.

Verification after the first connection:

- Output panel "Remote - SSH" contains `Found existing installation at` and no `Downloading` lines.
- On the host: `ls ~/.vscode-server/cli/servers/` shows only `Stable-<commit>` and `lru.json` (no `*.staging`), and `cli/servers/Stable-<commit>/log.txt` contains `Extension host agent listening on`.

### 4.3 Legacy mode (`"remote.SSH.useExecServer": false`)

Target layout: `~/.vscode-server/bin/<commit>/` = server archive contents with the top-level directory stripped. The install script checks for `node` and `bin/code-server` there. Runtime files: `~/.vscode-server/.<commit>.{log,pid,token}`.

```sh
COMMIT=f1a4fb101478ce6ec82fe9627c43efbf9e98c813
mkdir -p ~/.vscode-server/bin/$COMMIT
tar -xzf /tmp/vscode-server-linux-x64.tar.gz --strip-components 1 --no-same-owner -C ~/.vscode-server/bin/$COMMIT
test -x ~/.vscode-server/bin/$COMMIT/node && ~/.vscode-server/bin/$COMMIT/bin/code-server --version
```

Client setting: `"remote.SSH.useExecServer": false`. Remote - SSH logs `Found existing installation at /home/<user>/.vscode-server/bin/<commit>...` and starts `bin/code-server --start-server --server-data-dir ~/.vscode-server --host=127.0.0.1 --port=0 --accept-server-license-terms --enable-remote-auto-shutdown --connection-token-file ~/.vscode-server/.<commit>.token`. (If it had to download, the host-side download would use `server-linux-legacy-<arch>` and the client-side fallback `server-linux-<arch>`; both run on glibc >= 2.28.)

### 4.4 Windows remote hosts (not used in this environment)

Exec-server: `%USERPROFILE%\.vscode-server\code-<commit>.exe` (from `cli/vscode_cli_win32_<arch>_cli.zip`) and `%USERPROFILE%\.vscode-server\cli\servers\Stable-<commit>\server\` (zip contents, top-level directory stripped). Legacy: `%USERPROFILE%\.vscode-server\bin\<commit>\`.

### 4.5 Extensions on the host

`extensionKind` (column in `manifest-extensions.json`): `ui`-only extensions stay on the client; the others are installed on the host when used in a Remote - SSH window. Install offline from the placed server:

```sh
COMMIT=f1a4fb101478ce6ec82fe9627c43efbf9e98c813
SERVER=~/.vscode-server/cli/servers/Stable-$COMMIT/server        # legacy mode: ~/.vscode-server/bin/$COMMIT
$SERVER/bin/code-server --server-data-dir ~/.vscode-server --extensions-dir ~/.vscode-server/extensions --install-extension /tmp/<file>.vsix
$SERVER/bin/code-server --server-data-dir ~/.vscode-server --extensions-dir ~/.vscode-server/extensions --list-extensions --show-versions
```

GUI alternative: in a connected window run `Extensions: Install from VSIX...`; the file picker browses host files.

Not archived: extensions installed only on hosts. Check `ls ~/.vscode-server/extensions` on each host (`C2`, `ATR`) and fetch their .vsix while the Marketplace still serves them.

### 4.6 Cleanup

Command palette `Remote-SSH: Uninstall VS Code Server from Host...`, or on the host: kill `code-server` and `code-<commit>` processes, then `rm -rf ~/.vscode-server`.

## 5. Re-download (only while the sources are reachable)

```
pwsh ./scripts/download-vscode.ps1        # PowerShell 7 + curl.exe; sha256 from the update API; verified files are skipped
pwsh ./scripts/download-extensions.ps1    # reads %USERPROFILE%\.vscode\extensions\extensions.json
```

URL scheme: `https://update.code.visualstudio.com/commit:<commit>/<target>/stable` (server, CLI) and `https://update.code.visualstudio.com/1.95.3/<target>/stable` (clients); metadata with sha256 at the same paths under `/api/versions/`. `<target>` = `target` column of `manifest-vscode.json`. Extensions: `https://marketplace.visualstudio.com/_apis/public/gallery/publishers/<publisher>/vsextensions/<name>/<version>/vspackage` (response is gzip-encoded).

## 6. Open items

- The manual placement in 4.2/4.3 is derived from the install scripts and CLI source; it has not yet been exercised end to end on a host. Run the checks in 4.2 after the first connection.
- Host-only extensions are not archived (4.5).
- Not downloaded: armhf client packages; web-server builds for armhf, alpine and legacy.

## Sources

- Remote - SSH 0.115.1: `%USERPROFILE%\.vscode\extensions\ms-vscode-remote.remote-ssh-0.115.1\out\extension.js` (legacy Linux/Windows scripts, Windows exec-server script), `out\install-script\scripts\linux-exec-server-installer.sh`
- VS Code 1.95.3 CLI, https://github.com/microsoft/vscode/tree/1.95.3/cli/src : `tunnels/code_server.rs`, `tunnels/paths.rs`, `tunnels/control_server.rs`, `download_cache.rs`, `util/prereqs.rs`, `util/http.rs`, `update_service.rs`
- https://code.visualstudio.com/docs/remote/ssh , https://code.visualstudio.com/docs/remote/troubleshooting , https://code.visualstudio.com/docs/remote/faq
- https://github.com/microsoft/vscode/issues/231029 (offline install broke with the exec-server layout)
