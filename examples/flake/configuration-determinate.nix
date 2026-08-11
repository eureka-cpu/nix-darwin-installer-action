{ pkgs, config, ... }:
{
  # GitHub's macOS runners run as the `runner` user on Apple Silicon.
  system.primaryUser = "runner";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Determinate's own daemon manages the Nix install, which conflicts with
  # nix-darwin doing the same. Determinate's docs have you disable
  # nix-darwin's management instead of the other way around, which also
  # rules out nix.linux-builder (it requires nix.enable). Not importing
  # ../../modules/default.nix here because of this: that module sets
  # nix.enable = true for the Linux builder, which doesn't work under
  # Determinate.
  nix.enable = false;

  environment.systemPackages = [ pkgs.hello ];

  system.stateVersion = config.system.maxStateVersion;
}
