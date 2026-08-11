{ config, ... }:
{
  # GitHub's macOS runners run as the `runner` user on Apple Silicon.
  system.primaryUser = "runner";
  nixpkgs.hostPlatform = "aarch64-darwin";

  nix = {
    # nix.linux-builder.enable requires nix.enable. nix-darwin recognizes
    # /etc/nix/nix.conf written by cachix/install-nix-action and the
    # Determinate installer, so it layers its own settings on top instead of
    # fighting them.
    enable = true;

    # Necessary for using `linux-builder`.
    settings.trusted-users = [ "root" "@admin" ];

    # Linux builder VM, so aarch64-linux/x86_64-linux derivations can build in
    # CI. Deliberately left at pkgs.darwin.linux-builder's own defaults
    # (1 core, 3 GB RAM, 20 GB disk) instead of sizing it up: GitHub's
    # standard macOS runners only have 3 vCPUs and 14 GB RAM, and free disk
    # space swings widely between image releases, including regressions to
    # under 20 GB (see actions/runner-images#10511), so there isn't a stable
    # baseline to size against. Raise cores/memorySize/diskSize via
    # `linux-builder.config.virtualisation` if you're on a larger runner or
    # self-hosted hardware. Also needs a runner with nested virtualization
    # support, which GitHub's shared macOS runners may not provide.
    linux-builder = {
      enable = true;
      ephemeral = true;
    };
  };

  # Keep this pinned to the schema version you tested against.
  # Or use `config.system.maxStateVersion` to suppress warnings and use the
  # latest version.
  system.stateVersion = config.system.maxStateVersion;
}
