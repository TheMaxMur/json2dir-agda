{
  description = "json2dir written in Agda";
  inputs.nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/0.1";
  outputs = { nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      tools = system:
        let pkgs = import nixpkgs { inherit system; }; in
        pkgs.symlinkJoin {
          name = "json2dir-agda-toolchain";
          paths = [ pkgs.agda pkgs.ghc pkgs.gnumake pkgs.python3 ];
        };
    in {
      packages = eachSystem (system:
        let pkgs = import nixpkgs { inherit system; }; in {
          toolchain = tools system;
          default = pkgs.stdenv.mkDerivation {
            pname = "json2dir-agda";
            version = "0.1.0";
            src = nixpkgs.lib.cleanSourceWith {
              src = ./.;
              filter = path: type:
                let name = baseNameOf path; in
                nixpkgs.lib.cleanSourceFilter path type
                && !(builtins.elem name [ ".tools" "build" "json2dir" "result" "__pycache__" ])
                && !(nixpkgs.lib.hasSuffix ".agdai" name);
            };
            nativeBuildInputs = [ (tools system) ];
            buildPhase = "make";
            doCheck = true;
            checkPhase = "make test";
            installPhase = "make install PREFIX=$out";
            meta.mainProgram = "json2dir";
          };
        });
      devShells = eachSystem (system:
        let pkgs = import nixpkgs { inherit system; }; in {
          default = pkgs.mkShell { packages = [ (tools system) ]; };
        });
    };
}
