# generated by zon2nix (https://github.com/nix-community/zon2nix)

{ linkFarm, fetchzip }:

linkFarm "zig-packages" [
  {
    name = "122066d86920926a4a674adaaa10f158dc4961c2a47e588e605765455d74ca72c2ad";
    path = fetchzip {
      url = "https://github.com/Hejsil/zig-clap/archive/c394594d218c3c936547e590b461e69e6e0b20c4.tar.gz";
      hash = "sha256-miFzgfH9svxLy+HpCyJwJbplRlACVAiLHhuNze5f0cM=";
    };
  }
]
