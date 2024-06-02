let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  pyproject-nix-src = builtins.fetchTarball {
    url = lock.nodes.pyproject-nix.locked.url or "https://github.com/nix-community/pyproject.nix/archive/${lock.nodes.pyproject-nix.locked.rev}.tar.gz";
    sha256 = lock.nodes.pyproject-nix.locked.narHash;
  };
in
{ pkgs
, lib ? pkgs.lib
, pypa ? (import pyproject-nix-src { inherit lib; }).lib.pypa
}:
let
  build-package = { python }: { name, version, src, format, dependencies, ... }:
    python.pkgs.buildPythonPackage {
      pname = name;
      version = version;
      src = src;
      format = format;
      propagatedBuildInputs = map (dep: [ python.pkgs.${dep.name} ]) dependencies;
    };

  sdistModule = { config, ... }: {
    options.url = lib.mkOption {
      type = lib.types.str;
    };
    options.hash = lib.mkOption {
      type = lib.types.str;
    };
    options.size = lib.mkOption {
      type = lib.types.int;
    };
  };
  wheelModule = { config, ... }: {
    options.url = lib.mkOption {
      type = lib.types.str;
    };
    options.hash = lib.mkOption {
      type = lib.types.str;
    };
    options.size = lib.mkOption {
      type = lib.types.int;
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
  distributionModule = { preferWheels, pkgs, python }: { config, ... }:
    let
      # Only use wheels matching current python version and system architechture
      # https://github.com/nix-community/poetry2nix/blob/0a592572706db14e49202892318d3812061340a0/mk-poetry-dep.nix#L29
      compatible-wheels =
        let
          wheelFilesByFileName = lib.listToAttrs (map (fileEntry: lib.nameValuePair fileEntry.url fileEntry) config.wheels);
          compatible = pypa.selectWheels python.stdenv.targetPlatform python (map (fileEntry: pypa.parseWheelFileName fileEntry.url) config.wheels);
        in
        map (wheel: wheelFilesByFileName.${wheel.filename}) compatible;
      fetch-sdist = { url, hash, size }: builtins.fetchurl {
        inherit url;
        sha256 = hash;
      };
      fetch-wheel = { url, hash, size }: builtins.fetchurl {
        inherit url;
        sha256 = hash;
      };
      useWheel = config.preferWheel || config.sdist == null;
      src-format =
        if useWheel && builtins.length config.compatible-wheels > 0
        then { src = fetch-wheel (builtins.head config.compatible-wheels); format = "wheel"; }
        else if config.sdist != null
        then { src = fetch-sdist config.sdist; format = "pyproject"; }
        else { src = null; format = "pyproject"; }
      ;
      inherit (src-format) src format;
    in

    {
      options.name = lib.mkOption {
        type = lib.types.str;
        example = ''wheel'';
      };
      options.version = lib.mkOption {
        type = lib.types.str;
        example = ''2.6.12'';
      };
      options.src = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = src;
      };
      options.source = lib.mkOption {
        type = lib.types.str;
      };
      options.format = lib.mkOption {
        type = lib.types.str;
        default = format;
      };
      options.compatible-wheels = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule wheelModule);
        default = compatible-wheels;
      };
      options.preferWheel = lib.mkOption {
        type = lib.types.bool;
        default = preferWheels;
      };
      options.dependencies = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule dependencyModule);
        default = [ ];
      };
      options.sdist = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule sdistModule);
        default = null;
      };
      options.wheels = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule wheelModule);
        default = [ ];
      };
      options.package = lib.mkOption {
        type = lib.types.package;
        defaultText = ''python.pkgs.''${name}'';
        default = python.pkgs.${config.name};
      };
    };
  lockedDistributions = { uvLock }:
    {
      config.distributions = builtins.listToAttrs (map
        (d: {
          name = d.name;
          value =
            if d ? wheel then
              builtins.removeAttrs d [ "wheel" ] // { wheels = d.wheel; }
            else d;
        })
        uvLock.distribution
      );
    };
  uv2nix =
    { src
    , uvLockFile ? src + "/uv.lock"
    , uvLock ? builtins.fromTOML (builtins.readFile uvLockFile)
    , useLock ? true
    , modules ? [ ]
    , overlays ? [ ]
    , python ? pkgs.python3
    }:
    let
      baseModules = [
        { _module.args.pkgs = pkgs; }
        ({ config, ... }:
          let
            allOverlays = [
              (final: prev: lib.mapAttrs (_: d: build-package { inherit python; } d) config.distributions)
            ] ++ overlays;
            py = python.override {
              packageOverrides = lib.foldr lib.composeExtensions (_final: _prev: { }) allOverlays;
              self = py;
            };
          in
          {
            options.python = lib.mkOption {
              type = lib.types.package;
              default = py;
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
      ];
      allModules = baseModules
        ++ lib.optional useLock (lockedDistributions { inherit uvLock; })
        ++ modules
      ;
    in
    lib.evalModules {
      modules = allModules;
    };
in
{
  inherit lockedDistributions uv2nix;
}
