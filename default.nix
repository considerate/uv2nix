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
  build-package =
    { pythonPackages }: { name
                        , version
                        , preferWheel
                        , compatible-wheels
                        , sdist
                        , dependencies
                        , extraDependencies
                        , ...
                        }:
    let
      fetch-sdist = { url, hash, size }: builtins.fetchurl {
        inherit url;
        sha256 = hash;
      };
      fetch-wheel = { url, hash, size }: builtins.fetchurl {
        inherit url;
        sha256 = hash;
      };
      useWheel = preferWheel || sdist == null;
      src-format =
        if useWheel && builtins.length compatible-wheels > 0
        then { src = fetch-wheel (builtins.head compatible-wheels); format = "wheel"; }
        else if sdist != null
        then { src = fetch-sdist sdist; format = "pyproject"; }
        else { src = null; format = "pyproject"; }
      ;
      inherit (src-format) src format;
    in
    pythonPackages.buildPythonPackage {
      pname = name;
      version = version;
      src = src;
      format = format;
      propagatedBuildInputs = map
        (dep:
          pythonPackages.${dep.name}
            or(builtins.warn "Missing dependency ${dep.name} for ${name}" null)
        )
        dependencies ++ map
        (dep:
          pythonPackages.${dep}
            or(builtins.warn "Missing dependency ${dep} for ${name}" null))
        extraDependencies;
    };

  urlSdist = { config, ... }: {
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
  pathSdist = { config, ... }: {
    options.path = lib.mkOption {
      type = lib.types.str;
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
    options.marker = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
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
      options.source = lib.mkOption {
        type = lib.types.str;
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
      options.extraDependencies = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      # NOTE: evalModules doesn't really support sum types of submodules.
      # This hacks a "sum type" by having two nullable fields
      options.sdist = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule urlSdist);
        default = null;
      };
      options.pathSdist = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule pathSdist);
        default = null;
      };
      options.wheels = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule wheelModule);
        default = [ ];
      };
      # options.package = lib.mkOption {
      #   type = lib.types.package;
      #   defaultText = ''python.pkgs.''${name}'';
      #   default = python.pkgs.${config.name};
      # };
      # options.env = lib.mkOption {
      #   type = lib.types.package;
      #   defaultText = ''(python.buildEnv.override {extraLibs = [package]}).env'';
      #   default = (python.buildEnv.override {
      #     extraLibs = [ config.package ];
      #     ignoreCollisions = true;
      #   }).env;
      # };
    };
  lockedDistributions = { uvLock }:
    {
      config.distributions = builtins.listToAttrs (map
        (d:
          let
            isPathSdist = d ? sdist.path;
            isUrlSdist = d ? sdist.url;
            hasWheels = d ? wheel;
          in
          {
            name = d.name;
            value =
              builtins.removeAttrs d [ "wheel" "sdist" ] // lib.listToAttrs (
                lib.optional hasWheels { name = "wheels"; value = d.wheel; }
                ++ lib.optional isPathSdist { name = "pathSdist"; value = d.sdist; }
                ++ lib.optional isUrlSdist { name = "sdist"; value = d.sdist; }
              );
          })
        uvLock.distribution
      );
    };
  uv2nix =
    { src ? null
    , uvLockFile ? src + "/uv.lock"
    , uvLock ? builtins.fromTOML (builtins.readFile uvLockFile)
    , useLock ? true
    , modules ? [ ]
    , overlays ? [ ]
    , python ? pkgs.python3
    }:
      assert useLock -> src != null;
      let
        baseModules = [
          { _module.args.pkgs = pkgs; }
          ({ config, ... }:
            let
              allOverlays = [
                (final: prev:
                  lib.mapAttrs (_: d: build-package { pythonPackages = final; } d) config.distributions)
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
      lib.evalModules
        {
          modules = allModules;
        } // {
        inherit uvLock;
      };
in
{
  inherit lockedDistributions uv2nix;
}
