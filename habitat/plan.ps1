$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction']='Stop'

$env:HAB_BLDR_CHANNEL = "base-2025"
$env:HAB_REFRESH_CHANNEL = "base-2025"
$pkg_name="chef-test-kitchen-enterprise"
$pkg_origin="chef"
$pkg_version=$(Get-Content "$PLAN_CONTEXT/../VERSION")
$pkg_maintainer="The Chef Maintainers <humans@chef.io>"

$pkg_deps=@(
  "core/ruby3_4-plus-devkit"
  "core/git"
)
$pkg_bin_dirs=@("bin"
                "vendor/bin")
$project_root= (Resolve-Path "$PLAN_CONTEXT/../").Path

function Invoke-Before {
    Set-PkgVersion
}
function Invoke-SetupEnvironment {
    Push-RuntimeEnv -IsPath GEM_PATH "$pkg_prefix/vendor"

    Set-RuntimeEnv APPBUNDLER_ALLOW_RVM "true" # prevent appbundler from clearing out the carefully constructed runtime GEM_PATH
    Set-RuntimeEnv FORCE_FFI_YAJL "ext"
    Set-RuntimeEnv LANG "en_US.UTF-8"
    Set-RuntimeEnv LC_CTYPE "en_US.UTF-8"
    Set-RuntimeEnv CHEF_TEST_KITCHEN_ENTERPRISE "true"
}

function Invoke-Build {
    try {
        $env:Path += ";c:\\Program Files\\Git\\bin"
        Push-Location $project_root
        $env:GEM_HOME = "$HAB_CACHE_SRC_PATH/$pkg_dirname/vendor"

        Write-BuildLine " ** Enabling Windows long path support"
        # Enable Git long paths for bundler git operations
        git config --global core.longpaths true
        # Set Windows environment to support long paths in Ruby
        $env:MSYS = "winsymlinks:nativestrict"
        
        Write-BuildLine " ** Configuring bundler for this build environment"
        bundle config --local without "deploy maintenance"
        bundle config --local jobs 4
        bundle config --local retry 5
        bundle config --local silence_root_warning 1
        Write-BuildLine " ** Using bundler to retrieve the Ruby dependencies"
        bundle install
	    bundle lock --local
        gem build chef-test-kitchen-enterprise.gemspec
	    Write-BuildLine " ** Using gem to  install"
	    gem install chef-test-kitchen-enterprise*.gem --no-document --force
	    
	    # Build and install the test-kitchen alias gem to satisfy driver dependencies
	    Write-BuildLine " ** Building test-kitchen alias gem"
	    gem build test-kitchen.gemspec
	    Write-BuildLine " ** Installing test-kitchen alias gem"
	    gem install test-kitchen*.gem --no-document --force

        ruby ./post-bundle-install.rb
        If ($lastexitcode -ne 0) { Exit $lastexitcode }

        # Install chef-official-distribution AFTER post-bundle-install
        Install-ChefOfficialDistribution

        Write-BuildLine " ** Build complete"
    } finally {
        Pop-Location
    }

}
function Invoke-Install {
    Write-BuildLine "** Copy built & cached gems to install directory"
    Copy-Item -Path "$HAB_CACHE_SRC_PATH/$pkg_dirname/*" -Destination $pkg_prefix -Recurse -Force -Exclude @("gem_make.out", "mkmf.log", "Makefile",
                     "*/latest", "latest",
                     "*/JSON-Schema-Test-Suite", "JSON-Schema-Test-Suite")
    
    # Ensure Gemfile.lock is copied to the package root (it's in src/ subdirectory)
    Write-BuildLine "** Checking for Gemfile.lock at $HAB_CACHE_SRC_PATH/$pkg_dirname/src/Gemfile.lock"
    if (Test-Path "$HAB_CACHE_SRC_PATH/$pkg_dirname/src/Gemfile.lock") {
        Write-BuildLine "** Copying Gemfile.lock to $pkg_prefix/Gemfile.lock"
        Copy-Item -Path "$HAB_CACHE_SRC_PATH/$pkg_dirname/src/Gemfile.lock" -Destination "$pkg_prefix/Gemfile.lock" -Force
    } else {
        Write-BuildLine "** Gemfile.lock not found at expected location, checking alternatives..."
        Get-ChildItem "$HAB_CACHE_SRC_PATH/$pkg_dirname" -Filter "Gemfile.lock" -Recurse | ForEach-Object {
            Write-BuildLine "** Found Gemfile.lock at: $($_.FullName)"
            Copy-Item -Path $_.FullName -Destination "$pkg_prefix/Gemfile.lock" -Force
        }
    }

    try {
        Push-Location $pkg_prefix
        if (-not (Test-Path "$pkg_prefix/Gemfile.lock")) {
            Write-BuildLine "ERROR: Gemfile.lock still not found in $pkg_prefix"
            Exit 1
        }

        # Set GEM_PATH to include both vendor and the system gem paths
        $env:GEM_PATH = "$pkg_prefix/vendor"
        $env:GEM_HOME = "$pkg_prefix/vendor"

        # Create bin directory if it doesn't exist
        if (-not (Test-Path "$pkg_prefix/bin")) {
            New-Item -ItemType Directory -Path "$pkg_prefix/bin" | Out-Null
        }

        # Find the gem and create wrapper for kitchen binary
        $kitchenGemDir = Get-ChildItem "$pkg_prefix/vendor/gems" -Filter "chef-test-kitchen-enterprise-*" -Directory | Select-Object -First 1
        if ($kitchenGemDir) {
            Write-BuildLine "** Found gem directory: $($kitchenGemDir.FullName)"
            $realKitchenBin = "$($kitchenGemDir.FullName)/bin/kitchen"
            if (Test-Path $realKitchenBin) {
                Write-BuildLine "** Creating wrapper for kitchen binary"

                # Remove any existing kitchen files in bin directory
                Remove-Item "$pkg_prefix/bin/kitchen" -Force -ErrorAction SilentlyContinue
                Remove-Item "$pkg_prefix/bin/kitchen.bat" -Force -ErrorAction SilentlyContinue

                # Remove kitchen from vendor/bin if it exists (to avoid conflicts)
                Remove-Item "$pkg_prefix/vendor/bin/kitchen" -Force -ErrorAction SilentlyContinue

                Wrap-KitchenBinary "$pkg_prefix/bin/kitchen" $realKitchenBin
            }
        }
        
	Write-BuildLine " ** Build and install complete"

        If ($lastexitcode -ne 0) { Exit $lastexitcode }
    } finally {
        Pop-Location
    }
}

function Wrap-KitchenBinary {
    param(
        [string]$WrapperPath,
        [string]$RealBinPath
    )
    
    Write-BuildLine "Creating wrapper script at $WrapperPath"
    
    $rubyPath = Get-HabPackagePath "core/ruby3_4-plus-devkit"
    
    # Create a batch wrapper script that sets up the environment
    $wrapperContent = @"
@echo off
REM Wrapper script for Test Kitchen Enterprise
REM Sets up Ruby gem environment and executes kitchen

REM Set Ruby paths for gem loading - include both vendor and Ruby system gems
set "GEM_HOME=$pkg_prefix\vendor"
set "GEM_PATH=$pkg_prefix\vendor;$rubyPath\lib\ruby\gems\3.4.0"

REM Set encoding to UTF-8 to handle non-ASCII characters
set "RUBYOPT=-Eutf-8"

REM Execute the real kitchen binary with ruby
"$rubyPath\bin\ruby.exe" "$RealBinPath" %*
"@
    
    # Create the batch file (Windows will use .bat extension)
    Set-Content -Path "$WrapperPath.bat" -Value $wrapperContent -Encoding ASCII
    
    Write-BuildLine "Wrapper created successfully at $WrapperPath.bat"
}

function Invoke-After {
    # We don't need the cache of downloaded .gem files ...
    Remove-Item $pkg_prefix/vendor/cache -Recurse -Force
    # We don't need the gem docs.
    Remove-Item $pkg_prefix/vendor/doc -Recurse -Force
    # We don't need to ship the test suites for every gem dependency,
    # only inspec's for package verification.
    Get-ChildItem $pkg_prefix/vendor/gems -Filter "spec" -Directory -Recurse -Depth 1 `
        | Where-Object -FilterScript { $_.FullName -notlike "*test-kitchen*" }             `
        | Remove-Item -Recurse -Force
    # Remove the byproducts of compiling gems with extensions
    Get-ChildItem $pkg_prefix/vendor/gems -Include @("gem_make.out", "mkmf.log", "Makefile") -File -Recurse `
        | Remove-Item -Force
}

function Install-ChefOfficialDistribution {
    Write-BuildLine "Installing chef-official-distribution gem from Artifactory"

    $artifactorySource = "https://artifactory-internal.ps.chef.co/artifactory/omnibus-gems-local/"

    try {
        # Add Artifactory as gem source
        gem sources --add $artifactorySource
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to add Artifactory gem source"
        }

        # Install the gem
        gem install chef-official-distribution --no-document
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install chef-official-distribution gem"
        }

        Write-BuildLine "Successfully installed chef-official-distribution"
    }
    catch {
        Write-Error "Error installing chef-official-distribution: $_"
        exit 1
    }
    finally {
        # Always clean up gem sources
        try {
            gem sources --remove $artifactorySource
        } catch {
            # Ignore errors during cleanup
        }
    }
}
