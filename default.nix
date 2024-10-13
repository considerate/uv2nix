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
  build-systems-json = builtins.fromJSON (builtins.readFile ./build-systems.json);
  build-package =
    { pythonPackages }:
    { name
    , version
    , preferWheel
    , compatible-wheels
    , sdist
    , dependencies
    , extraDependencies
    , build-systems
    , source
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
      wheel-sources = map
        (w: {
          src = fetch-wheel w;
          format = "wheel";
        })
        compatible-wheels;
      sdists = lib.optional (sdist != null) {
        src = if sdist ? url then fetch-sdist sdist.url else sdist.path;
        format = "pyproject";
      };
      srcs =
        if source ? editable then [{ src = source.editable; format = "pyproject"; }]
        else
          if preferWheel
          then wheel-sources ++ sdists
          else sdists ++ wheel-sources
      ;
      src-format = builtins.head srcs;
      inherit (src-format) src format;
      deps = map (dep: dep.name) dependencies ++ extraDependencies;


      project-toml = builtins.fromTOML (builtins.readFile (pkgs.stdenv.mkDerivation {
        name = "parse-${name}-build-systems";
        src = src;
        phases = [ "unpackPhase" "installPhase" ];
        installPhase = ''
          cp pyproject.toml $out
        '';
      }));
      parsed-build-systems = lib.optionals (format == "pyproject") (project-toml.build-system.requires);

      matching-build-system = system:
        if lib.isString system
        then true
        else if lib.isAttrs system
        then
          let
            matchesFrom = system.from == null || lib.versionAtLeast version system.from;
            machesUntil = system.until == null || lib.versionOlder version system.until;
          in
          matchesFrom && machesUntil
        else false
      ;
      matching-build-systems = lib.filter matching-build-system build-systems;
      add-build-system = system:
        if lib.isString system
        then system
        else system.buildSystem;
      buildSystems =
        if builtins.length matching-build-systems > 0
        then map add-build-system matching-build-systems
        else map (buildSystem: builtins.elemAt (builtins.match "[[:space:]]*([a-zA-Z0-9-]+).*" buildSystem) 0) parsed-build-systems;
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
      nativeBuildInputs = map (b: pythonPackages.${b}) buildSystems ++ [ pkgs.autoPatchelfHook ] ++ lib.optionals (format == "wheel") [
        pythonPackages.wheelUnpackHook
        pythonPackages.pypaInstallHook
      ];
    };

  buildSystemModule = { config, ... }: {
    options.buildSystem = lib.mkOption {
      type = lib.types.str;
    };
    options.from = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    options.until = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
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
    options.specifier = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };
  packageModule = { preferWheels, pkgs, python }: { config, ... }:
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
        type = lib.types.attrTag {
          editable = lib.mkOption {
            type = lib.types.path;
          };
          registry = lib.mkOption {
            type = lib.types.str;
          };
        };
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
      options.dev-dependencies = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf (lib.types.submodule dependencyModule));
        default = { };
      };
      options.extraDependencies = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      options.sdist = lib.mkOption {
        # TODO: extend the `attrTag` to allow defining the options directly under sdist somehow.
        type = lib.types.nullOr (lib.types.attrTag {
          url = lib.mkOption {
            type = lib.types.submodule urlSdistModule;
          };
          path = lib.mkOption {
            type = lib.types.submodule pathSdistModule;
          };
        });
        default = null;
      };
      options.wheels = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule wheelModule);
        default = [ ];
      };
      options.build-systems = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.str (lib.types.submodule buildSystemModule));
        default = build-systems-json.${config.name} or [ ];
      };
      options.metadata = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
    };
  lockedPackages = { src, uvLock }:
    {
      config.distributions = builtins.listToAttrs (map
        (d:
          {
            name = d.name;
            value =
              builtins.removeAttrs d [ "sdist" ] // lib.optionalAttrs (d ? source.editable) {
                source.editable = src + "/${d.source.editable}";
              } // (lib.listToAttrs (
                lib.optional (d ? sdist.url)
                  {
                    name = "sdist";
                    value = {
                      url = d.sdist;
                    };
                  }
                ++ lib.optional (d ? sdist.path) {
                  name = "sdist";
                  value = {
                    path = {
                      # make path relative to `src`
                      path = src + "/${d.sdist.path}";
                    } // d.sdist;
                  };
                }
              ));
          })
        uvLock.package
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
                type = lib.types.attrsOf (lib.types.submodule (packageModule {
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
          ++ lib.optional useLock (lockedPackages { inherit src uvLock; })
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
  inherit lockedPackages uv2nix;
}
