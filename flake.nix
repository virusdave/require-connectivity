{
  description = "Connectivity watchdog package and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f (import nixpkgs { inherit system; overlays = [ self.overlays.default ]; }));
    in {
      overlays.default = import ./overlays/default.nix;
      overlay = self.overlays.default;

      packages = forAllSystems (pkgs: {
        default = pkgs.require-connectivity;
        require-connectivity = pkgs.require-connectivity;
      });

      nixosModules.default = import ./modules/require-connectivity.nix;
      nixosModule = self.nixosModules.default;
    };
}
