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
          uv2nixFor = { pkgs, pypa }: import ./default.nix { inherit pkgs pypa; };
        };
      };
      perSystem = system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          uv2nix = inputs.self.lib.uv2nixFor {
            inherit pkgs;
            inherit (inputs.pyproject-nix.lib) pypa;
          };
        in
        {
          packages = {
            examples = {
              init = uv2nix.uv2nix {
                src = ./examples/init;
              };
              edifice = uv2nix.uv2nix {
                src = ./examples/edifice;
              };
            };
          };
        };
    in
    inputs.mkflake.lib.mkflake {
      inherit perSystem topLevel systems;
    };
}
