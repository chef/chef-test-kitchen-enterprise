#
# Author:: Chef Software, Inc.
#
# Copyright:: Copyright (c) 2024-2026 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#!/usr/bin/env powershell

#Requires -Version 5

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$PkgIdent
)

$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
$ErrorActionPreference = 'Stop'

function Fail {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [int]$ExitCode = 1
  )

  Write-Host "`nERROR: $Message`n" -ForegroundColor Red
  exit $ExitCode
}

$env:CHEF_LICENSE = 'accept-no-persist'
$env:HAB_LICENSE = 'accept-no-persist'
$env:HAB_NONINTERACTIVE = 'true'
$env:HAB_BLDR_CHANNEL = 'base-2025'

if (-not $PkgIdent) {
  Fail "no hab package identity provided"
}

$project_root = "$(git rev-parse --show-toplevel)"
Set-Location $project_root

Write-Host "--- :mag_right: Testing $PkgIdent executables"

# Pkg ident is origin/name/version/release. We want the version field.
$pkgParts = $PkgIdent.Split('/')
if ($pkgParts.Length -lt 3) {
  Fail "unexpected package identity format: '$PkgIdent'"
}
$expectedVersion = $pkgParts[2]

# Ensure the `kitchen` executable is available.
$kitchenCmd = Get-Command kitchen -ErrorAction SilentlyContinue
if (-not $kitchenCmd) {
  Fail "kitchen is not on PATH; PATH is: $env:Path"
}

# Prefer the explicit subcommand. Some Windows environments don't support `-v`
# as a flag the same way as the bash smoke test.
$versionOutput = & kitchen --version 2>&1
if ($LASTEXITCODE -ne 0) {
  $versionOutput = & kitchen version 2>&1
}

if ($LASTEXITCODE -ne 0) {
  Fail "kitchen version failed: $versionOutput" $LASTEXITCODE
}

$match = [regex]::Match($versionOutput, '(?i)version\s+(\d+\.\d+\.\d+)')
if (-not $match.Success) {
  Fail "unable to parse kitchen version from output: $versionOutput"
}

$actualVersion = $match.Groups[1].Value
if ($expectedVersion -ne $actualVersion) {
  Fail "test-kitchen is not the expected version. Expected '$expectedVersion', got '$actualVersion'"
}

Write-Host "--- :kitchen: Running kitchen converge smoke test"

$kitchenYaml = Join-Path $project_root "kitchen.dummy.yml"
if (-not (Test-Path $kitchenYaml)) {
  Fail "$kitchenYaml not found; cannot run kitchen converge smoke test"
}

# Use a driver/transport combo that doesn't require external infrastructure.
$env:KITCHEN_LOCAL_YAML = $kitchenYaml

& kitchen diagnose all
if ($LASTEXITCODE -ne 0) { Fail "kitchen diagnose failed" $LASTEXITCODE }

& kitchen list
if ($LASTEXITCODE -ne 0) { Fail "kitchen list failed" $LASTEXITCODE }

# Only converge the localhost instance; kitchen.dummy.yml also defines a windows platform.
& kitchen converge default-localhost
if ($LASTEXITCODE -ne 0) { Fail "kitchen converge default-localhost failed" $LASTEXITCODE }

# Verify the instance.
& kitchen verify default-localhost
if ($LASTEXITCODE -ne 0) { Fail "kitchen verify default-localhost failed" $LASTEXITCODE }

# Best-effort cleanup so CI workspaces stay clean.
& kitchen destroy default-localhost
if ($LASTEXITCODE -ne 0) { Fail "kitchen destroy default-localhost failed" $LASTEXITCODE }
