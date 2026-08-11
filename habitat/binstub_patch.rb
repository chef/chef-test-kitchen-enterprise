hab_vendor = File.expand_path(File.join(__dir__, "..", "vendor"))
chef_gem_dir = File.join(Dir.home, ".chef", "ruby", RbConfig::CONFIG["ruby_version"], "gems")

unless ENV["APPBUNDLER_ALLOW_RVM"]
  ENV["APPBUNDLER_ALLOW_RVM"] = "true"
  # Only override GEM_HOME for direct invocation; hab pkg exec sets it via RUNTIME_ENVIRONMENT.
  ENV["GEM_HOME"] = hab_vendor
end

# Always extend GEM_PATH so chef-cli-installed plugins (~/.chef/ruby/VERSION/gems) are visible.
# hab_vendor stays first so bundled gems take precedence over user-installed ones.
existing_paths = ENV["GEM_PATH"]&.split(File::PATH_SEPARATOR) || []
ENV["GEM_PATH"] = ([hab_vendor, Gem.user_dir, chef_gem_dir] + existing_paths).uniq.join(File::PATH_SEPARATOR)

# Set SSL_CERT_FILE from the hab cacerts package so TLS works when the binary
# is invoked directly (e.g. via symlink) without going through `hab pkg exec`.
# The RUNTIME_ENVIRONMENT is only applied by `hab pkg exec`; direct invocations
# skip it, leaving OpenSSL with no trusted CA bundle.
unless ENV["SSL_CERT_FILE"]
  pkg_root = File.expand_path(File.join(__dir__, ".."))
  runtime_env = File.join(pkg_root, "RUNTIME_ENVIRONMENT")
  if File.exist?(runtime_env)
    File.foreach(runtime_env) do |line|
      key, val = line.chomp.split("=", 2)
      ENV[key] = val if key == "SSL_CERT_FILE" && val && File.exist?(val)
    end
  end
end
