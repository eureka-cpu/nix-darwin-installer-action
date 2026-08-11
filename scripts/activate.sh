#!/usr/bin/env bash
#
# Bootstrap and activate a nix-darwin configuration.
#
# Because `darwin-rebuild` is not yet on PATH before the first activation, we
# obtain it from a flake reference (`nix-darwin-ref`) via `nix run`, then hand
# off to it. Two config styles are supported:
#
#   * flake        -> `darwin-rebuild <cmd> --flake <ref>`
#   * config-file  -> channel-based install using <darwin>/<darwin-config>
#
# If neither is given, falls back to this action's own bundled default
# config-file (modules/default.nix) so the action works with zero user config.
#
# Driven entirely by INPUT_* environment variables set by action.yml.

set -euo pipefail

# --- platform guard ------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "::error::install-nix-darwin only runs on macOS runners (got $(uname -s))."
  exit 1
fi

FLAKE="${INPUT_FLAKE:-}"
CONFIG_FILE="${INPUT_CONFIG_FILE:-}"
COMMAND="${INPUT_COMMAND:-switch}"
NIX_DARWIN_REF="${INPUT_NIX_DARWIN_REF:-github:nix-darwin/nix-darwin}"
NIXPKGS_CHANNEL="${INPUT_NIXPKGS_CHANNEL:-nixpkgs-unstable}"
NIX_DARWIN_CHANNEL="${INPUT_NIX_DARWIN_CHANNEL:-https://github.com/nix-darwin/nix-darwin/archive/master.tar.gz}"
EXTRA_ARGS="${INPUT_EXTRA_ARGS:-}"
GITHUB_TOKEN="${INPUT_GITHUB_TOKEN:-}"
USE_SUDO="${INPUT_USE_SUDO:-true}"

# --- input validation ----------------------------------------------------------
if [[ -n "$FLAKE" && -n "$CONFIG_FILE" ]]; then
  echo "::error::Provide either 'flake' or 'config-file', not both."
  exit 1
fi
if [[ -z "$FLAKE" && -z "$CONFIG_FILE" ]]; then
  echo "No 'flake' or 'config-file' provided; using the action's bundled default configuration."
  CONFIG_FILE="${GITHUB_ACTION_PATH}/modules/default.nix"
fi

# --- locate the nix binary -----------------------------------------------------
# The installer updates PATH for later steps, but sudo's secure_path can drop
# it, so we resolve an absolute path and invoke that under sudo.
if ! command -v nix >/dev/null 2>&1; then
  if [[ -e /nix/var/nix/profiles/default/bin/nix ]]; then
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
  fi
fi
NIX_BIN="$(command -v nix || true)"
if [[ -z "$NIX_BIN" ]]; then
  echo "::error::'nix' not found on PATH. This action requires Nix to be installed by an earlier step (e.g. cachix/install-nix-action or DeterminateSystems/nix-installer-action)."
  exit 1
fi
NIX_CHANNEL="$(dirname "$NIX_BIN")/nix-channel"

# --- sudo wrapper --------------------------------------------------------------
SUDO=()
if [[ "$USE_SUDO" == "true" ]]; then
  SUDO=(sudo)
fi

# Options for the `nix run ...#darwin-rebuild` bootstrap calls below. Flakes
# are only needed to fetch darwin-rebuild itself here, so we pass the flag
# ourselves rather than requiring the caller's Nix install to have it enabled.
# Access tokens keep GitHub fetches under the API rate limit.
NIX_OPTS=(--extra-experimental-features "nix-command flakes")
if [[ -n "$GITHUB_TOKEN" ]]; then
  NIX_OPTS+=(--option access-tokens "github.com=${GITHUB_TOKEN}")
fi

echo "Using nix: $NIX_BIN"
"${SUDO[@]}" "$NIX_BIN" --version || true

# --- back up pre-existing /etc files ----------------------------------------
# nix-darwin refuses to overwrite an /etc file it manages unless its content
# matches one of a hardcoded set of known hashes (installer/macOS version
# combos it recognizes). That allowlist lags behind installer and macOS
# updates, so a fresh runner's Nix installer step routinely produces content
# nix-darwin doesn't recognize, aborting activation with "unexpected files in
# /etc". On an ephemeral CI runner there's nothing in these files worth
# preserving, so back them up the way nix-darwin's own error message suggests
# before it gets a chance to complain.
echo "::group::Backing up pre-existing /etc files nix-darwin doesn't recognize"
for etcFile in /etc/nix/nix.conf /etc/bashrc /etc/zshrc /etc/zprofile /etc/zshenv; do
  if [[ -f "$etcFile" && ! -L "$etcFile" ]]; then
    echo "Backing up $etcFile -> $etcFile.before-nix-darwin"
    "${SUDO[@]}" mv "$etcFile" "$etcFile.before-nix-darwin"
  fi
done
echo "::endgroup::"

# --- activate ------------------------------------------------------------------
if [[ -n "$FLAKE" ]]; then
  echo "::group::Activating nix-darwin (flake: ${FLAKE}, command: ${COMMAND})"
  # shellcheck disable=SC2086 # EXTRA_ARGS is intentionally word-split
  "${SUDO[@]}" "$NIX_BIN" run "${NIX_DARWIN_REF}#darwin-rebuild" "${NIX_OPTS[@]}" -- \
    "$COMMAND" --flake "$FLAKE" $EXTRA_ARGS
  echo "::endgroup::"
else
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "::error::config-file '${CONFIG_FILE}' not found."
    exit 1
  fi

  echo "::group::Subscribing to channels (nixpkgs: ${NIXPKGS_CHANNEL})"
  "${SUDO[@]}" "$NIX_CHANNEL" --add "https://nixos.org/channels/${NIXPKGS_CHANNEL}" nixpkgs
  "${SUDO[@]}" "$NIX_CHANNEL" --add "${NIX_DARWIN_CHANNEL}" darwin
  "${SUDO[@]}" "$NIX_CHANNEL" --update
  echo "::endgroup::"

  echo "::group::Staging configuration to /etc/nix-darwin/configuration.nix"
  "${SUDO[@]}" mkdir -p /etc/nix-darwin
  "${SUDO[@]}" cp "$CONFIG_FILE" /etc/nix-darwin/configuration.nix
  echo "::endgroup::"

  echo "::group::Activating nix-darwin (config-file, command: ${COMMAND})"
  # <darwin> resolves via the root 'darwin' channel added above.
  # <darwin-config> points at the staged file.
  # shellcheck disable=SC2086
  "${SUDO[@]}" "$NIX_BIN" run "${NIX_DARWIN_REF}#darwin-rebuild" "${NIX_OPTS[@]}" -- \
    "$COMMAND" \
    -I "darwin-config=/etc/nix-darwin/configuration.nix" \
    $EXTRA_ARGS
  echo "::endgroup::"
fi

# --- outputs -------------------------------------------------------------------
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  SYSTEM="$(readlink /run/current-system 2>/dev/null || true)"
  echo "system=${SYSTEM}" >> "$GITHUB_OUTPUT"
fi

echo "nix-darwin activation complete."
