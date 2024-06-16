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
                        , pathSdist
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
      wheel-sources = map (w: { src = fetch-wheel w; format = "wheel"; }) compatible-wheels;
      path-sdists = lib.optional (pathSdist != null) { src = pathSdist.path; format = "pyproject"; };
      url-sdists = lib.optional (sdist != null) { src = fetch-sdist sdist; format = "pyproject"; };
      srcs =
        if preferWheel
        then wheel-sources ++ path-sdists ++ url-sdists
        else path-sdists ++ url-sdists ++ wheel-sources
      ;
      src-format = builtins.head srcs;
      inherit (src-format) src format;
      deps = map (dep: dep.name) dependencies ++ extraDependencies;
    in
    pythonPackages.buildPythonPackage {
      pname = name;
      version = version;
      src = src;
      format = format;
      propagatedBuildInputs = map
        (dep:
          pythonPackages.${dep}
            or(builtins.warn "Missing dependency ${dep} for ${name}" null)
        )
        deps;
      nativeBuildInputs = [ pkgs.autoPatchelfHook ] ++ lib.optionals (format == "wheel") [
        pythonPackages.wheelUnpackHook
        pythonPackages.pypaInstallHook
      ];
    };

  urlSdistModule = { config, ... }: {
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
  pathSdistModule = { config, ... }: {
    options.path = lib.mkOption {
      type = lib.types.path;
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
        type = lib.types.nullOr (lib.types.submodule urlSdistModule);
        default = null;
      };
      options.pathSdist = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule pathSdistModule);
        default = null;
      };
      options.wheels = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule wheelModule);
        default = [ ];
      };
    };
  lockedDistributions = { src, uvLock }:
    {
      config.distributions = builtins.listToAttrs (map
        (d:
          {
            name = d.name;
            value =
              builtins.removeAttrs d [ "wheel" "sdist" ] // (lib.listToAttrs (
                lib.optional (d ? wheel) { name = "wheels"; value = d.wheel; }
                ++ lib.optional (d ? sdist.path) { name = "pathSdist"; value = { path = src + "/${d.sdist.path}"; }; }
                ++ lib.optional (d ? sdist.url) { name = "sdist"; value = d.sdist; }
              ));
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
              options.packages =
                let
                  packageFor = name: _: config.python.pkgs.${name};
                in
                lib.mkOption {
                  type = lib.types.lazyAttrsOf lib.types.package;
                  default = lib.mapAttrs packageFor config.distributions;
                };
              options.apps =
                let
                  appFor = name: _: config.python.pkgs.toPythonApplication config.python.pkgs.${name};
                in
                lib.mkOption {
                  type = lib.types.lazyAttrsOf lib.types.package;
                  default = lib.mapAttrs appFor config.distributions;
                };
              options.shells =
                let
                  shellFor = name: distribution:
                    let
                      deps = map (dep: dep.name) distribution.dependencies ++ distribution.extraDependencies;
                      env = config.python.buildEnv.override {
                        extraLibs = map (dep: config.python.pkgs.${dep}) ([ name ] ++ deps);
                        ignoreCollisions = true;
                      };
                    in
                    env;
                in
                lib.mkOption {
                  type = lib.types.lazyAttrsOf lib.types.package;
                  default = lib.mapAttrs shellFor config.distributions;
                };
              options.devShells =
                let
                  shellFor = name: distribution:
                    let
                      deps = map (dep: dep.name) distribution.dependencies ++ distribution.extraDependencies;
                      env = (config.python.buildEnv.override {
                        extraLibs = map (dep: config.python.pkgs.${dep}) deps;
                        ignoreCollisions = true;
                      }).env;
                    in
                    env;
                in
                lib.mkOption {
                  type = lib.types.lazyAttrsOf lib.types.package;
                  default = lib.mapAttrs shellFor config.distributions;
                };
            })
        ];
        allModules = baseModules
          ++ lib.optional useLock (lockedDistributions { inherit src uvLock; })
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
