$ErrorActionPreference="stop"

# Enable Windows long paths
Write-Host "--- Enabling Windows long paths"
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue

Write-Host "--- Enabling Git long paths"
# Enable Git long paths to handle deep directory structures in gem dependencies
git config --global core.longpaths true

Write-Host "--- Cleaning vendor/bundle cache"
# Remove cached vendor/bundle using cmd rmdir to handle long paths
if (Test-Path "vendor/bundle") {
    Write-Host "Removing vendor/bundle directory..."
    cmd /c "rmdir /s /q vendor\bundle" 2>$null
    if (Test-Path "vendor/bundle") {
        Write-Host "Warning: Could not fully clean vendor/bundle, continuing anyway..."
    }
}

Write-Host "--- bundle install"

bundle config --local path vendor/bundle
bundle config set --local without docs development profile
bundle install --jobs=7 --retry=3

Write-Host "+++ bundle exec task"
bundle exec $args
if ($LASTEXITCODE -ne 0) { throw "$args failed" }
