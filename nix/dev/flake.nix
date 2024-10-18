{
  description = "Dependencies for development purposes";

  inputs = {
    # Flakes don't give us a good way to depend on parent directory, so we don't.
    # As a consequence, this flake only provides dependencies, and
    # we can't use the `nix` CLI as expected.

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv.url = "github:cachix/devenv";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { ... }:
    {
      # The dev tooling is in ./flake-module.nix
      # See comment at `inputs` above.
      # It is loaded into partitions.dev by the root flake.
    };
}
