<#
.SYNOPSIS
  Bring the local wowsims forever clone up to date with origin/master and rebuild wowsimcli when needed.

.DESCRIPTION
  Every sim run in the book calls this first (data/wowsims.R does it once per R session).

  1. git fetch origin. If origin/master moved, fast-forward master, then print the commit range and the commits that
     touch the warrior, Forever item, core or proto code.
  2. If bin/wowsimcli.exe was not built from the checked-out commit, regenerate the protos and rebuild it, and build
     the book's character-sheet helper (data/wowsims/statsheet) against the same checkout as
     bin/wowsimcli-statsheet.exe.
  3. Write bin/wowsimcli.version.json ({commit, short, date, subject, built_at}) and print it as the last line.

  It stops with an error, and leaves the version file saying the old commit, when anything fails: a failed fetch,
  local changes or commits in the clone, a merge that isn't a fast-forward, or a failed build. data/wowsims.R refuses
  to run a binary whose version file doesn't match the checked-out commit, so a stale binary is never used.

.PARAMETER Repo
  The wowsims clone. Defaults to $env:WOWSIMS_REPO, then C:\Users\pedro\src\wowsims-forever.

.PARAMETER Offline
  Skip the fetch (no network). The build check still runs.

.PARAMETER Force
  Rebuild even if the binary already matches the checked-out commit.
#>
param(
  [string]$Repo = $(if ($env:WOWSIMS_REPO) { $env:WOWSIMS_REPO } else { 'C:\Users\pedro\src\wowsims-forever' }),
  [switch]$Offline,
  [switch]$Force
)

# Native tools write progress to stderr; check exit codes by hand instead of letting PowerShell 5.1 throw on it.
$ErrorActionPreference = 'Continue'

function Fail([string]$msg) {
  [Console]::Error.WriteLine("wowsims_update: ERROR: $msg")
  exit 1
}
function Say([string]$msg) { Write-Host "wowsims_update: $msg" }
function Invoke-Git { & git.exe -C $Repo @args 2>&1 | ForEach-Object { "$_" } }

if (-not (Test-Path (Join-Path $Repo '.git'))) { Fail "no git clone at $Repo (set WOWSIMS_REPO or -Repo)" }

# Tools: Go, protoc (winget Google.Protobuf) and protoc-gen-go (go install), which may not be on PATH.
$extra = @('C:\Program Files\Go\bin', (Join-Path $env:USERPROFILE 'go\bin'))
$extra += Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') -Directory -Filter 'Google.Protobuf_*' -ErrorAction SilentlyContinue |
  ForEach-Object { Join-Path $_.FullName 'bin' }
$env:PATH = (($extra | Where-Object { Test-Path $_ }) -join ';') + ';' + $env:PATH
foreach ($tool in 'git', 'go', 'protoc', 'protoc-gen-go') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "$tool not found on PATH" }
}

$bin      = Join-Path $Repo 'bin'
$exe      = Join-Path $bin 'wowsimcli.exe'
$verFile  = Join-Path $bin 'wowsimcli.version.json'

# --- 1. Update the clone --------------------------------------------------------------------------------------------
$branch = (Invoke-Git rev-parse --abbrev-ref HEAD | Select-Object -Last 1).Trim()
if ($branch -ne 'master') { Fail "the clone is on '$branch', not master" }
$dirty = Invoke-Git status --porcelain --untracked-files=no
if ($dirty) { Fail "the clone has local changes; commit or stash them first:`n$($dirty -join "`n")" }

$old = (Invoke-Git rev-parse HEAD | Select-Object -Last 1).Trim()
if (-not $Offline) {
  $out = Invoke-Git fetch --quiet origin master
  if ($LASTEXITCODE -ne 0) { Fail "git fetch failed (run with -Offline to use the current checkout):`n$($out -join "`n")" }
  $remote = (Invoke-Git rev-parse origin/master | Select-Object -Last 1).Trim()
  if ($remote -ne $old) {
    $ahead = (Invoke-Git rev-list --count "origin/master..HEAD" | Select-Object -Last 1).Trim()
    if ($ahead -ne '0') { Fail "master has $ahead local commit(s) not on origin/master; refusing to pull" }
    $out = Invoke-Git merge --ff-only --quiet origin/master
    if ($LASTEXITCODE -ne 0) { Fail "fast-forward to origin/master failed:`n$($out -join "`n")" }
    $n = (Invoke-Git rev-list --count "$old..HEAD" | Select-Object -Last 1).Trim()
    Say "updated $($old.Substring(0,7))..$($remote.Substring(0,7)) ($n commits)"
    $relevant = Invoke-Git log --oneline --no-merges "$old..HEAD" -- sim/warrior sim/common/forever sim/core proto
    if ($relevant) {
      Say "commits touching sim/warrior, sim/common/forever, sim/core or proto:"
      $relevant | ForEach-Object { Write-Host "    $_" }
    } else {
      Say "none of them touch sim/warrior, sim/common/forever, sim/core or proto"
    }
  } else {
    Say "origin/master has not moved ($($old.Substring(0,7)))"
  }
}
$head = (Invoke-Git rev-parse HEAD | Select-Object -Last 1).Trim()

# --- 2. Rebuild if the binary isn't from this commit ----------------------------------------------------------------
$built = $null
Remove-Item (Join-Path $bin 'wowsimcli.building.exe') -Force -ErrorAction SilentlyContinue   # left by a failed run
if (Test-Path $verFile) { try { $built = (Get-Content $verFile -Raw | ConvertFrom-Json).commit } catch { $built = $null } }
$sheetSrc = Join-Path $PSScriptRoot 'wowsims\statsheet'
$sheetExe = Join-Path $bin 'wowsimcli-statsheet.exe'
if ($Force -or -not (Test-Path $exe) -or -not (Test-Path $sheetExe) -or $built -ne $head) {
  Say "building wowsimcli at $($head.Substring(0,7)) (binary was from $(if ($built) { $built.Substring(0,7) } else { 'unknown' }))"
  Push-Location $Repo
  try {
    $protos = Get-ChildItem proto -Filter *.proto | ForEach-Object { "./proto/$($_.Name)" }
    $out = & protoc '--proto_path=./proto' '--go_opt=Mgoogle/protobuf/descriptor.proto=google.golang.org/protobuf/types/descriptorpb' '--go_out=./sim/core' @protos 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { Fail "protoc failed; the old binary was NOT updated:`n$($out -join "`n")" }
    $tmp = Join-Path $bin 'wowsimcli.building.exe'
    $out = & go build --tags=with_db -o $tmp ./cmd/wowsimcli 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) { Fail "go build failed; the old binary was NOT updated:`n$($out -join "`n")" }
    # Swap the new binary in. Windows won't overwrite an exe that's running (a gear-sim run, say), but it will rename
    # it, so the old one moves aside first; a run already going keeps using it. The version file is only written once
    # the binary in place is byte-for-byte the new build.
    $newHash = (Get-FileHash $tmp).Hash
    Remove-Item (Join-Path $bin 'wowsimcli.old*.exe') -Force -ErrorAction SilentlyContinue
    if (Test-Path $exe) {
      $aside = Join-Path $bin ("wowsimcli.old-{0}.exe" -f (Get-Date -Format 'yyyyMMddHHmmss'))
      try { Rename-Item $exe (Split-Path $aside -Leaf) -ErrorAction Stop } catch { Fail "could not move the old binary aside: $_" }
    }
    try { Move-Item $tmp $exe -ErrorAction Stop } catch { Fail "could not put the new binary in place: $_" }
    if ((Get-FileHash $exe).Hash -ne $newHash) { Fail "the binary in place is not the new build" }
    Remove-Item (Join-Path $bin 'wowsimcli.old*.exe') -Force -ErrorAction SilentlyContinue   # fails quietly while in use
  } finally { Pop-Location }

  # The book's character-sheet helper (data/wowsims/statsheet), built against the same checkout.
  Push-Location $sheetSrc
  try {
    Copy-Item (Join-Path $Repo 'go.sum') 'go.sum' -Force
    $out = & go mod edit "-replace=github.com/wowsims/forever=$($Repo -replace '\\','/')" 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { Fail "go mod edit failed for statsheet:`n$($out -join "`n")" }
    $tmp = Join-Path $bin 'wowsimcli-statsheet.building.exe'
    $out = & go build --tags=with_db -o $tmp . 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) { Fail "statsheet build failed:`n$($out -join "`n")" }
    if (Test-Path $sheetExe) {
      Remove-Item $sheetExe -Force -ErrorAction SilentlyContinue
      if (Test-Path $sheetExe) { Rename-Item $sheetExe ("wowsimcli-statsheet.old-{0}.exe" -f (Get-Date -Format 'yyyyMMddHHmmss')) }
    }
    try { Move-Item $tmp $sheetExe -ErrorAction Stop } catch { Fail "could not put the new statsheet in place: $_" }
  } finally { Pop-Location }
  $info = [ordered]@{
    commit   = $head
    short    = $head.Substring(0, 7)
    date     = (Invoke-Git log -1 --format=%cs HEAD | Select-Object -Last 1).Trim()
    subject  = (Invoke-Git log -1 --format=%s HEAD | Select-Object -Last 1).Trim()
    built_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  }
  # UTF-8 without a BOM, so R's jsonlite reads it cleanly
  [IO.File]::WriteAllText($verFile, ($info | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
  Say "built $($info.short) ($($info.date))"
} else {
  Say "wowsimcli is already built from $($head.Substring(0,7))"
}

# --- 3. Report the version ------------------------------------------------------------------------------------------
Get-Content $verFile -Raw
