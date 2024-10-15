{
  description = "TeslaMate Logger";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    devenv-root.url = "file+file:///dev/null";
    devenv-root.flake = false;
  };

  outputs = inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      flake.nixosModules.default = import ./nix/module.nix { inherit self; };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # See ./nix/flake-modules/*.nix for the modules that are imported here.
      imports = [
        inputs.flake-parts.flakeModules.partitions
        ./nix/flake-modules/checks.nix
        ./nix/flake-modules/package.nix
      ];

      # Setup separate flake.lock for dev dependencies
      partitionedAttrs.devShells = "dev";
      partitionedAttrs.formatter = "dev";
      partitions.dev.extraInputsFlake = ./nix/dev;
      partitions.dev.extraInputs = {
        # propagate devenv-root to dev partition
        inherit (inputs) devenv-root;
      };
      partitions.dev.module = {
        imports = [ ./nix/dev/flake-module.nix ];
      };
    };
}
