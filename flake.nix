{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    mkflake.url = "github:jonascarpay/mkflake";
    pyproject-nix.url = "github:nix-community/pyproject.nix";
  };
  outputs = inputs:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      topLevel = {
        lib = {
          uv2nixFor = { pkgs }:
            import ./default.nix {
              inherit pkgs;
              pypa = inputs.pyproject-nix.lib.pypa;
            };
        };
      };
      perSystem = system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          uv2nix = inputs.self.lib.uv2nixFor {
            inherit pkgs;
          };
          docs = pkgs.callPackage ./docs { inherit uv2nix; };
        in
        {
          devShells = {
            default = pkgs.mkShell {
              name = "uv2nix-dev-shell";
              packages = [
                pkgs.uv
              ];
            };
          };
          packages =
            {
              examples = {
                init = uv2nix.uv2nix {
                  src = ./examples/init;
                };
                edifice = uv2nix.uv2nix {
                  src = ./examples/edifice;
                  overlays = [
                    (final: prev: {
                      edifice-project = prev.edifice-project.overrideAttrs (old: {
                        nativeBuildInputs = old.nativeBuildInputs ++ [
                          final.setuptools
                        ];
                      });
                      pyedifice = prev.pyedifice.overrideAttrs (old: {
                        nativeBuildInputs = old.nativeBuildInputs ++ [
                          final.poetry-core
                        ];
                      });
                      qasync = prev.qasync.overrideAttrs (old: {
                        nativeBuildInputs = old.nativeBuildInputs ++ [
                          final.poetry-core
                        ];
                      });
                      typing-extensions = prev.typing-extensions.overrideAttrs (old: {
                        nativeBuildInputs = old.nativeBuildInputs ++ [
                          final.flit-core
                        ];
                      });
                    })
                  ];
                };
              };
              inherit (docs) docs manpages;
            };
        };
    in
    inputs.mkflake.lib.mkflake {
      inherit perSystem topLevel systems;
    };
}
