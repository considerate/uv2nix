{ pkgs, lib ? pkgs.lib }:
let
  sdistModule = { config, ... }: {
    options.size = lib.mkOption {
      type = lib.types.int;
    };
    options.hash = lib.mkOption {
      type = lib.types.str;
    };
    options.url = lib.mkOption {
      type = lib.types.str;
    };
  };
  wheelModule = { config, ... }: {
    options.size = lib.mkOption {
      type = lib.types.int;
    };
    options.hash = lib.mkOption {
      type = lib.types.str;
    };
    options.url = lib.mkOption {
      type = lib.types.str;
    };
  };
  dependencyModule = { config, ... }: {
    options.name = lib.mkOption {
      type = lib.types.str;
    };
    options.version = lib.mkOption {
      type = lib.types.str;
    };
    options.source = lib.mkOption {
      type = lib.types.str;
    };
  };
  distributionModule = { preferWheels, pkgs, python }: { config, ... }: {
    options.src = lib.mkOption {
      # FIXME: define this using the other options
      type = lib.types.nullOr lib.types.path;
      default = null;
    };
    options.source = lib.mkOption {
      type = lib.types.str;
    };
    options.version = lib.mkOption {
      type = lib.types.str;
    };
    options.preferWheel = lib.mkOption {
      type = lib.types.bool;
      default = preferWheels;
    };
    options.dependencies = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule dependencyModule);
      default = [ ];
    };
    options.name = lib.mkOption {
      type = lib.types.str;
    };
    options.sdist = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule sdistModule);
      default = null;
    };
    options.wheel = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule wheelModule);
      default = null;
    };
  };
  lockedDistributions = { uvLock }: {
    config.distributions = builtins.listToAttrs (map (d: { name = d.name; value = d; }) uvLock.distribution);
  };
  uv2nix =
    { src
    , uvLockFile ? src + "/uv.lock"
    , uvLock ? builtins.fromTOML (builtins.readFile uvLockFile)
    , extraModules ? [ (lockedDistributions { inherit uvLock; }) ]
    }: lib.evalModules {
      modules = [
        { _module.args.pkgs = pkgs; }
        ({ config, ... }: {
          options.python = lib.mkOption {
            type = lib.types.package;
            default = pkgs.python3;
          };
          options.preferWheels = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          options.distributions = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule (distributionModule {
              inherit pkgs;
              inherit (config) preferWheels python;
            }));
            default = { };
          };
        })
      ] ++ extraModules;
    };
in
{
  inherit lockedDistributions uv2nix;
}
