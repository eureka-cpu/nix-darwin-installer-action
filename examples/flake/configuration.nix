{ pkgs, ... }:
{
  imports = [ ../../modules/default.nix ];

  environment.systemPackages = [ pkgs.hello ];
}
