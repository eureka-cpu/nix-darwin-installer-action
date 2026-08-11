{ pkgs, config, ... }:
{
  environment.systemPackages = [ pkgs.hello ];

  system.primaryUser = "runner";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Nix itself is managed by an external installer (e.g. cachix/install-nix-action
  # or DeterminateSystems/nix-installer-action), not nix-darwin. Disabling this
  # stops nix-darwin from managing the installed Nix version, the nix-daemon
  # launchd job, and /etc/nix/nix.conf, so it doesn't fight the installer.
  nix.enable = false;

  system.stateVersion = config.system.maxStateVersion;
}
