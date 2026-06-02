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
)
$pkg_build_deps=@(
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
        $env:CHEF_TEST_KITCHEN_ENTERPRISE = "true"

        Write-BuildLine " ** Enabling Windows long path support"
        # Enable Git long paths for bundler git operations
        git config --global core.longpaths true
        # Set Windows environment to support long paths in Ruby
        $env:MSYS = "winsymlinks:nativestrict"

        Write-BuildLine " ** Configuring bundler for this build environment"
        bundle config --local without "deploy maintenance test cookstyle"
        bundle config --local jobs 4
        bundle config --local retry 5
        bundle config --local silence_root_warning 1
        Write-BuildLine " ** Using bundler to retrieve the Ruby dependencies"
        bundle install
	    bundle lock
        gem build chef-test-kitchen-enterprise.gemspec
	    Write-BuildLine " ** Using gem to  install"
	    gem install chef-test-kitchen-enterprise*.gem --no-document --force

	    # Build and install the test-kitchen alias gem to satisfy driver dependencies
	    Write-BuildLine " ** Building test-kitchen alias gem"
	    gem build test-kitchen.gemspec
	    Write-BuildLine " ** Installing test-kitchen alias gem"
	    gem install test-kitchen*.gem --no-document --force
        Write-BuildLine " ** Cleaning up lint_roller Gemfile.lock"
        ruby ./cleanup_gem_lockfiles.rb
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

    write-output "*** invoke-install"
    $NoticeFile = "$PLAN_CONTEXT\..\NOTICE"

    if (Test-Path $NoticeFile) {
        Write-BuildLine "** Copying NOTICE to package directory"
        Copy-Item -Path $NoticeFile -Destination $pkg_prefix -Force
    } else {
        Write-BuildLine "** Warning: NOTICE not found at $NoticeFile"
    }

    Write-BuildLine "** Copy built & cached gems to install directory"
    Copy-Item -Path "$HAB_CACHE_SRC_PATH/$pkg_dirname/*" -Destination $pkg_prefix -Recurse -Force -Exclude @("gem_make.out", "mkmf.log", "Makefile",
                     "*/latest", "latest",
                     "*/JSON-Schema-Test-Suite", "JSON-Schema-Test-Suite")

    # Ensure we use the project lockfile (not lockfiles from vendored gems).
    $projectGemfileLockCandidates = @(
        (Join-Path "$HAB_CACHE_SRC_PATH/$pkg_dirname" "Gemfile.lock"),
        (Join-Path "$HAB_CACHE_SRC_PATH/$pkg_dirname/src" "Gemfile.lock"),
        (Join-Path $project_root "Gemfile.lock")
    )
    $projectGemfileLock = $projectGemfileLockCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $projectGemfileLock) {
        Write-BuildLine "ERROR: Project Gemfile.lock not found in expected locations"
        Exit 1
    }
    Write-BuildLine "** Using project Gemfile.lock from: $projectGemfileLock"
    Copy-Item -Path $projectGemfileLock -Destination (Join-Path $pkg_prefix "Gemfile.lock") -Force

    try {
        Push-Location $pkg_prefix
        $env:CHEF_TEST_KITCHEN_ENTERPRISE = "true"
        if (-not (Test-Path "$pkg_prefix/Gemfile.lock")) {
            Write-BuildLine "ERROR: Gemfile.lock still not found in $pkg_prefix"
            Exit 1
        }

        $bundleGemfileCandidates = @(
            (Join-Path "$HAB_CACHE_SRC_PATH/$pkg_dirname" "Gemfile"),
            (Join-Path "$HAB_CACHE_SRC_PATH/$pkg_dirname/src" "Gemfile"),
            (Join-Path $project_root "Gemfile"),
            (Join-Path $pkg_prefix "Gemfile")
        )
        $env:BUNDLE_GEMFILE = $bundleGemfileCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $env:BUNDLE_GEMFILE) {
            Write-BuildLine "ERROR: Project Gemfile not found in expected locations"
            Exit 1
        }
        $bundleDir = Split-Path -Parent $env:BUNDLE_GEMFILE
        if (-not (Test-Path (Join-Path $bundleDir "Gemfile.lock"))) {
            Copy-Item -Path "$pkg_prefix/Gemfile.lock" -Destination (Join-Path $bundleDir "Gemfile.lock") -Force
        }

        # Ensure appbundler and installed gems resolve from the packaged vendor path.
        $env:GEM_PATH = "$pkg_prefix/vendor"
        $env:GEM_HOME = "$pkg_prefix/vendor"

        if (-not (Test-Path "$pkg_prefix/bin")) {
            New-Item -ItemType Directory -Path "$pkg_prefix/bin" | Out-Null
        }

        $rubyPkgPath = (& hab pkg path core/ruby3_4-plus-devkit).Trim()
        $rubyExe = Join-Path $rubyPkgPath "bin\ruby.exe"
        $appbundler = Join-Path $pkg_prefix "vendor\bin\appbundler"

        Write-BuildLine "** generating binstubs for chef-test-kitchen-enterprise with precise version pins"
        & $rubyExe $appbundler $bundleDir "$pkg_prefix/bin" "chef-test-kitchen-enterprise"
        if ($LASTEXITCODE -ne 0) { Exit $LASTEXITCODE }

        Write-BuildLine "** patching generated binstubs for Habitat runtime env"
        $binstubPatch = Get-Content "$PLAN_CONTEXT\binstub_patch.bat" -Raw
        Get-ChildItem -Path "$pkg_prefix\bin\*.bat" -File | ForEach-Object {
            $binstubPath = $_.FullName
            $binstubContent = Get-Content $binstubPath -Raw
            $binstubContent = $binstubContent -replace '(?im)^@ECHO OFF', "@ECHO OFF`r`n$binstubPatch"
            Set-Content -Path $binstubPath -Value $binstubContent -Encoding ASCII -NoNewline
        }

	Write-BuildLine " ** Build and install complete"

        If ($lastexitcode -ne 0) { Exit $lastexitcode }
    } finally {
        Pop-Location
    }
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
    # Remove vendored .github directories to reduce scanner false positives.
    Get-ChildItem $pkg_prefix/vendor -Filter ".github" -Directory -Recurse -ErrorAction SilentlyContinue `
        | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
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
