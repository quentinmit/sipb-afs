{
  # `inputs` specifies Nix language dependencies for this flake
  inputs = {
    # https://github.com/NixOS/nixpkgs/pull/424753
    #nixpkgs.url = "nixpkgs/nixos-25.05";
    nixpkgs.url = "github:quentinmit/nixpkgs/openafs-cellservdb";
  };
  # `outputs` is a function that takes the resolved dependencies as arguments
  # and returns the flake's products.
  outputs = { self, nixpkgs, ... }: {
    # nixosModules is an attrset of NixOS modules (https://nixos.org/manual/nixos/stable/#sec-modularity) defined in this flake.
    nixosModules.base = import ./modules/base.nix;
    # overlays is an attrset of nixpkgs overlays (https://nixos.org/manual/nixpkgs/stable/#sec-overlays-definition) defined in this flake.
    overlays.default = import ./pkgs/overlays.nix;
    # legacyPackages is an attrset of targets, each of which is an attrset of
    # packages that can be built.
    #
    # For convenience, we're just re-exposing the full set of packages from
    # nixpkgs (pinned by the inputs above/flake.lock) with our overlay applied.
    legacyPackages.x86_64-linux = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        self.overlays.default
      ];
      # TSM is unfree
      config.allowUnfree = true;
    };
    # The package nixosTests.cell is a self-contained test that spawns two AFS
    # servers and exercises the cell.
    packages.x86_64-linux.nixosTests.cell = self.legacyPackages.x86_64-linux.testers.runNixOSTest {
      imports = [
        ./tests/cell.nix
      ];
      # Add all local NixOS modules
      defaults.imports = builtins.attrValues self.nixosModules;
    };
    # This was the name the test was previously exposed under; this is just an alias for the new name.
    nixosTests.x86_64-linux.cell = self.packages.x86_64-linux.nixosTests.cell;
  };
}
