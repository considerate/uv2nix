{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
  };
  outputs = inputs:
    let
      forSystem = f: system: builtins.mapAttrs (_: value: { ${system} = value; }) (f system);
      forSystems = f: systems:
        builtins.foldl'
          (a: b: a // b)
          (builtins.map (forSystem f) systems);
    in
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
        in
        {
          packages = { };
        };
    in
    forSystems perSystem systems // topLevel;
}
