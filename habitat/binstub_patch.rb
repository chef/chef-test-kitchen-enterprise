unless ENV["APPBUNDLER_ALLOW_RVM"]
  ENV["APPBUNDLER_ALLOW_RVM"] = "true"
  # Set GEM_PATH/GEM_HOME to ONLY the hab vendor dir — do NOT append the existing
  # GEM_PATH (which contains RVM gems). Those RVM gems have native extensions compiled
  # for a different Ruby and cause "Ignoring X because its extensions are not built"
  # warnings. This package has everything it needs vendored.
  hab_vendor = File.expand_path(File.join(__dir__, "..", "vendor"))
  ENV["GEM_HOME"] = hab_vendor
  ENV["GEM_PATH"] = hab_vendor
end

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
