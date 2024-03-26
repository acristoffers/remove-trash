{
  description = "Removes files like .DS_Store and Thumb.db from the disk";

  inputs =
    {
      nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

      flake-utils.url = "github:numtide/flake-utils";

      gitignore.url = "github:hercules-ci/gitignore.nix";
      gitignore.inputs.nixpkgs.follows = "nixpkgs";
    };

  outputs = inputs:
    let
      inherit (inputs) nixpkgs gitignore flake-utils;
      inherit (gitignore.lib) gitignoreSource;
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      rec {
        formatter = pkgs.nixpkgs-fmt;
        packages.default = packages.remove-trash;
        packages.remove-trash = pkgs.buildGoModule {
          pname = "remove-trash";
          version = (builtins.readFile ./pkg/remove_trash/version);
          src = gitignoreSource ./.;
          vendorHash = "sha256-9DLX4twuQ2+zmN0FKi6xto4BEqeV+PAF5lZShuLaBG4=";
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            mkdir -p build
            $GOPATH/bin/docgen
            cp -r build/share $out/share
            cp $GOPATH/bin/remove-trash $out/bin/remove-trash
            strip $out/bin/remove-trash
            runHook postInstall
          '';
        };
        apps = rec {
          remove-trash = { type = "app"; program = "${packages.remove-trash}/bin/remove-trash"; };
          default = remove-trash;
        };
        devShell = pkgs.mkShell {
          packages = with pkgs;[ packages.remove-trash go git man busybox ];
          shellHook = ''
            export fish_complete_path=${packages.remove-trash}/share/fish/completions
          '';
        };
      }
    );
}
