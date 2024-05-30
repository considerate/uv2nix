{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    mkflake.url = "github:jonascarpay/mkflake";
  };
  outputs = inputs:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      topLevel = {
        lib = {
          uv2nixFor = { pkgs }: import ./default.nix { inherit pkgs; };
        };
      };
      perSystem = system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          uv2nix = inputs.self.lib.uv2nixFor { inherit pkgs; };
        in
        {
          packages = {
            example = uv2nix.uv2nix {
              src = ./examples/init;
            };
          };
        };
    in
    inputs.mkflake.lib.mkflake {
      inherit perSystem topLevel systems;
    };
}
