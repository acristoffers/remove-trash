{
  inputs =
    {
      nixpkgs.url = github:NixOS/nixpkgs/nixpkgs-unstable;

      zig-overlay.url = github:mitchellh/zig-overlay;
      zig-overlay.inputs.nixpkgs.follows = "nixpkgs";

      gitignore.url = github:hercules-ci/gitignore.nix;
      gitignore.inputs.nixpkgs.follows = "nixpkgs";

      pcre2.url = github:PCRE2Project/pcre2/86919c90182854b5369bc10d5ad43b637f464f50;
      pcre2.flake = false;

      flake-utils.url = github:numtide/flake-utils;
    };

  outputs = inputs:
    let
      inherit (inputs) nixpkgs zig-overlay gitignore flake-utils;
      inherit (gitignore.lib) gitignoreSource;
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        zig = zig-overlay.packages.${system}.master;
        isLinux = nixpkgs.lib.hasSuffix "linux" system;
      in
      rec {
        formatter = pkgs.nixpkgs-fmt;
        packages.default = packages.remove-trash;
        packages.remove-trash = pkgs.stdenvNoCC.mkDerivation {
          name = "remove-trash";
          version = "master";
          src = gitignoreSource ./.;
          nativeBuildInputs = with pkgs; (if isLinux then [
            autoPatchelfHook
            zig
          ] else [ zig ]);
          dontConfigure = true;
          dontInstall = true;
          doPatchElf = true;
          buildPhase = ''
            mkdir -p $out
            mkdir -p .cache
            ln -s ${pkgs.callPackage ./deps.nix { }} .cache/p
            cp -Lr ${inputs.pcre2} lib/pcre2
            chmod +rw -R lib/pcre2
            sh fix-zig-in-pcre2.sh
            zig build install --cache-dir $(pwd)/zig-cache --global-cache-dir $(pwd)/.cache -Doptimize=ReleaseSafe --prefix $out
          '';
        };
        apps = rec {
          remove-trash = { type = "app"; program = "${packages.remove-trash}/bin/remove-trash"; };
          default = remove-trash;
        };
      }
    );
}
