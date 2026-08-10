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
      darwinConfigurations."ci" = nix-darwin.lib.darwinSystem {
        modules = [ ./configuration.nix ];
      };
    };
}
