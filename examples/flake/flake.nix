{
  description = "Minimal nix-darwin configuration used to exercise install-nix-darwin in CI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, nix-darwin }:
    {
      darwinConfigurations."cachix" = nix-darwin.lib.darwinSystem {
        modules = [ ./configuration.nix ];
      };

      # Same idea, but without the Linux builder: Determinate's installer
      # conflicts with nix-darwin managing the Nix install (see
      # configuration-determinate.nix), so this exercises that path in CI.
      darwinConfigurations."determinate" = nix-darwin.lib.darwinSystem {
        modules = [ ./configuration-determinate.nix ];
      };
    };
}
