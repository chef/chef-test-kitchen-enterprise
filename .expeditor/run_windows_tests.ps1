$ErrorActionPreference="stop"

Write-Host "--- Enabling Git long paths"
# Enable Git long paths to handle deep directory structures in gem dependencies
git config --global core.longpaths true

Write-Host "--- Cleaning vendor/bundle cache"
# Remove cached vendor/bundle to avoid Ruby version incompatibilities
if (Test-Path "vendor/bundle") {
    Remove-Item -Recurse -Force "vendor/bundle"
}

Write-Host "--- bundle install"

bundle config --local path vendor/bundle
bundle config set --local without docs development profile
bundle install --jobs=7 --retry=3

Write-Host "+++ bundle exec task"
bundle exec $args
if ($LASTEXITCODE -ne 0) { throw "$args failed" }
