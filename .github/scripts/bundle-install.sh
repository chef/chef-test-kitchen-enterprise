#!/usr/bin/env bash
# Wrapper for bundle install that clears VS Code/Copilot git environment variables
# that break bundler's bare repository clones.
set -euo pipefail

cd "$(dirname "$0")/../.."

  # Clear VS Code/Copilot CLI git env vars that break bundler's bare repo clones
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CONFIG_PARAMETERS
  
if [[ -n "${GIT_CONFIG_COUNT:-}" ]]; then
  for ((i=0; i< GIT_CONFIG_COUNT; i++)); do
    unset "GIT_CONFIG_KEY_${i}" "GIT_CONFIG_VALUE_${i}"
  done
  unset GIT_CONFIG_COUNT
fi
echo "==> Running bundle install..."
bundle install "$@"
echo "==> bundle install completed successfully"
