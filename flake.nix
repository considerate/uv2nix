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
              pyproject-nix = inputs.pyproject-nix.lib;
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
              examples =
                {
                  init = uv2nix.uv2nix {
                    src = ./examples/init;
                    modules = [
                      {
                        distributions.torch.preferWheel = true;
                        distributions.pyproject-metadata.build-systems = [ "flit-core" ];
                        distributions.meson-python.build-systems = [ "meson" "ninja" ];
                        distributions.numpy.build-systems = [ "meson" "ninja" "cython" ];
                      }
                    ];
                    overlays = [
                      (import ./overlays/cuda.nix { inherit pkgs; })
                      (final: prev: {
                        intel-openmp = prev.intel-openmp.overridePythonAttrs (old: {
                          buildInputs = (old.buildInputs or [ ]) ++ [
                            pkgs.llvmPackages.openmp
                          ];
                        });
                        numpy = prev.numpy.overridePythonAttrs (old: {
                          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                            final.meson-python
                          ];
                          buildInputs = (old.buildInputs or [ ]) ++ [
                            pkgs.blas
                            pkgs.openblas
                          ];
                        });
                        tbb = prev.tbb.overridePythonAttrs (old: {
                          buildInputs = (old.buildInputs or [ ]) ++ [
                            pkgs.tbb_2021_11
                            pkgs.hwloc.lib
                          ];
                        });
                        nvidia-cudnn-cu12 = prev.nvidia-cudnn-cu12.overridePythonAttrs (old: {
                          buildInputs = (old.buildInputs or [ ]) ++ [
                            pkgs.zlib
                          ];
                        });
                      })
                    ];
                  };
                  edifice = uv2nix.uv2nix {
                    src = ./examples/edifice;
                    modules = [
                      {
                        distributions = {
                          pyedifice.build-systems = [ "poetry-core" ];
                          edifice-project.build-systems = [ "setuptools" ];
                        };
                      }
                    ];
                    overlays = [
                      (import ./examples/edifice/overlay.nix)
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
