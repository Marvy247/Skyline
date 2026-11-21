#!/usr/bin/env bash
# Installs the exact dependency set Skyline was built and tested against.
#
# `contracts/lib` is intentionally not committed: vendoring dependencies into
# a hackathon repository is worse than a one-command bootstrap. Every version
# below is pinned to a tag or commit. The script is idempotent; delete
# `contracts/lib` to force a clean reinstall.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v forge >/dev/null 2>&1; then
  echo "error: forge not found. Install Foundry: https://book.getfoundry.sh/getting-started/installation" >&2
  exit 1
fi

install_dep() {
  local alias="$1" spec="$2" label="$3"
  if [ -d "lib/$alias" ] && [ -n "$(ls -A "lib/$alias" 2>/dev/null)" ]; then
    echo "Already present: $alias ($label)"
    return
  fi
  echo "Installing $alias ($label)"
  forge install "$spec" --no-git --shallow
}

install_dep forge-std foundry-rs/forge-std@v1.17.0 "forge-std v1.17.0"
install_dep openzeppelin-contracts OpenZeppelin/openzeppelin-contracts@v5.1.0 "OpenZeppelin Contracts v5.1.0"
install_dep v4-core Uniswap/v4-core@v4.0.0 "Uniswap v4-core v4.0.0"

# v4-core v4.0.0 pins solmate at this commit (6.2.0). It is installed at the
# top level so the `solmate/` remapping does not depend on v4-core's own
# submodule layout.
install_dep solmate transmissions11/solmate@4b47a19038b798b4a33d9749d25e570443520647 "solmate 6.2.0 (v4-core pinned commit)"

echo
echo "Dependencies installed. Next:"
echo "  forge build"
echo "  forge test"
