{
  inputs = {
    # https://github.com/NixOS/nixpkgs/pull/424753
    #nixpkgs.url = "nixpkgs/nixos-25.05";
    nixpkgs.url = "github:quentinmit/nixpkgs/openafs-cellservdb";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils, ... }@args:
    let
      findModules = dir:
        builtins.concatLists (builtins.attrValues (builtins.mapAttrs
          (name: type:
            if type == "regular" then [{
              name = builtins.elemAt (builtins.match "(.*)\\.nix" name) 0;
              value = dir + "/${name}";
            }] else if (
              builtins.readDir (dir + "/${name}"))
            ? "default.nix" then [{
              inherit name;
              value = dir + "/${name}";
            }]
            else
              (map
                (e: e // {name = "${name}/${e.name}";})
                (findModules (dir + "/${name}"))
              )
          ) (builtins.readDir dir)));
      findModules' = path: builtins.listToAttrs (findModules path);
      in {
        nixosModules = findModules' ./modules;
      } // (flake-utils.lib.eachDefaultSystem (system:
        let
          inherit ((
            import nixpkgs {
              inherit system;
            }
          )) pkgs;
          inherit (pkgs) lib;
        in {
          legacyPackages = pkgs;
          nixosTests = lib.mapAttrsRecursive (_: file: pkgs.testers.runNixOSTest {
            imports = [
              file
            ];
            defaults.imports = builtins.attrValues self.nixosModules;
          }) (findModules' ./tests);
        }));
}
