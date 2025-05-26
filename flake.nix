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
        packages.remove-trash = pkgs.buildGoModule rec {
          pname = "remove-trash";
          version = (builtins.readFile ./pkg/remove_trash/version);
          buildInputs = with pkgs; [ glibc.static ];
          CFLAGS = "-I${pkgs.glibc.dev}/include";
          LDFLAGS = "-L${pkgs.glibc}/lib";
          src = gitignoreSource ./.;
          vendorHash = "sha256-ZFsDzTGAC/kYmxobrOoRAQwP102+a6QeHuqKB0/F3p4=";
          ldflags = [ "-s" "-w" "-linkmode external" "-extldflags '-static'" ];
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            mkdir -p build
            $GOPATH/bin/docgen
            cp -r build/share $out/share
            cp $GOPATH/bin/remove-trash $out/bin/remove-trash
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
