final: prev:
let inherit (final) pkgs;
  inherit (final.python) stdenv;
  inherit (pkgs) lib;
  inherit (pkgs.buildPackages) pkg-config;
in
{
  pyqt6 =
    let
      # The build from source fails unless the pyqt6 version agrees
      # with the version of qt6 from nixpkgs. Thus, we prefer using
      # the wheel here.
      pyqt6-wheel = prev.pyqt6.override { preferWheel = true; };
      pyqt6 = pyqt6-wheel.overridePythonAttrs (old:
        let
          confirm-license = pkgs.writeText "confirm-license.patch" ''
            diff --git a/project.py b/project.py
            --- a/project.py
            +++ b/project.py
            @@ -163,8 +163,7 @@

                     # Automatically confirm the license if there might not be a command
                     # line option to do so.
            -        if tool == 'pep517':
            -            final.confirm_license = True
            +        final.confirm_license = True

                     final._check_license()


          '';
          isWheel = old.src.isWheel or false;
        in
        {
          propagatedBuildInputs = old.propagatedBuildInputs or [ ] ++ [
            final.dbus-python
          ];
          nativeBuildInputs = old.nativeBuildInputs or [ ] ++ [
            pkg-config
            final.pyqt6-sip
            final.sip
            final.pyqt-builder
            pkgs.xorg.lndir
            pkgs.qt6.qmake
          ] ++ lib.optionals isWheel [
            pkgs.qt6.full # building from source doesn't properly pick up libraries from pyqt6-qt6
          ];
          patches = lib.optionals (!isWheel) [
            confirm-license
          ];
          env.NIX_CFLAGS_COMPILE = "-fpermissive";
          # be more verbose
          postPatch = ''
            cat >> pyproject.toml <<EOF
            [tool.sip.project]
            verbose = true
            EOF
          '';
          dontWrapQtApps = true;
          dontConfigure = true;
          enableParallelBuilding = true;
          # HACK: parallelize compilation of make calls within pyqt's setup.py
          # pkgs/stdenv/generic/setup.sh doesn't set this for us because
          # make gets called by python code and not its build phase
          # format=pyproject means the pip-build-hook hook gets used to build this project
          # pkgs/development/interpreters/python/hooks/pip-build-hook.sh
          # does not use the enableParallelBuilding flag
          postUnpack = ''
            export MAKEFLAGS+="''${enableParallelBuilding:+-j$NIX_BUILD_CORES}"
          '';
          preFixup = lib.optionalString isWheel ''
            addAutoPatchelfSearchPath ${final.pyqt6-qt6}/${final.python.sitePackages}/PyQt6
          '';
        });
    in
    pyqt6;
  pyqt6-qt6 = prev.pyqt6-qt6.overridePythonAttrs (old: {
    autoPatchelfIgnoreMissingDeps = [ "libmysqlclient.so.21" "libmimerapi.so" "libQt6*" ];
    preFixup = ''
      addAutoPatchelfSearchPath $out/${final.python.sitePackages}/PyQt6/Qt6/lib
    '';
    propagatedBuildInputs = old.propagatedBuildInputs or [ ] ++ [
      pkgs.libxkbcommon
      pkgs.gtk3
      pkgs.speechd
      pkgs.gst
      pkgs.gst_all_1.gst-plugins-base
      pkgs.gst_all_1.gstreamer
      pkgs.postgresql.lib
      pkgs.unixODBC
      pkgs.pcsclite
      pkgs.xorg.libxcb
      pkgs.xorg.xcbutil
      pkgs.xorg.xcbutilcursor
      pkgs.xorg.xcbutilerrors
      pkgs.xorg.xcbutilimage
      pkgs.xorg.xcbutilkeysyms
      pkgs.xorg.xcbutilrenderutil
      pkgs.xorg.xcbutilwm
      pkgs.libdrm
      pkgs.pulseaudio
    ];
  });
  shiboken6 = prev.shiboken6.overridePythonAttrs (_old: {
    postFixup = ''
      find $out/${final.python.sitePackages} -name __pycache__ -prune -exec rm -vrf {} \;
    '';
  });

  pyside6-essentials = prev.pyside6-essentials.overridePythonAttrs (old: lib.optionalAttrs stdenv.isLinux {
    autoPatchelfIgnoreMissingDeps = [ "libmysqlclient.so.21" "libmimerapi.so" "libQt6*" ];
    preFixup = ''
      addAutoPatchelfSearchPath $out/${final.python.sitePackages}/PySide6
      addAutoPatchelfSearchPath ${final.shiboken6}/${final.python.sitePackages}/shiboken6
    '';
    postFixup = ''
      find $out/${final.python.sitePackages} -name __pycache__ -prune -exec rm -vrf {} \;
    '';
    buildInputs = (old.buildInputs or [ ]) ++ [
      pkgs.qt6.full
    ];
    propagatedBuildInputs = old.propagatedBuildInputs or [ ] ++ [
      pkgs.libxkbcommon
      pkgs.gtk3
      pkgs.speechd
      pkgs.gst
      pkgs.gst_all_1.gst-plugins-base
      pkgs.gst_all_1.gstreamer
      pkgs.postgresql.lib
      pkgs.unixODBC
      pkgs.pcsclite
      pkgs.xorg.libxcb
      pkgs.xorg.xcbutil
      pkgs.xorg.xcbutilcursor
      pkgs.xorg.xcbutilerrors
      pkgs.xorg.xcbutilimage
      pkgs.xorg.xcbutilkeysyms
      pkgs.xorg.xcbutilrenderutil
      pkgs.xorg.xcbutilwm
      pkgs.libdrm
      pkgs.pulseaudio
      final.shiboken6
    ];
  });

  pyside6-addons = prev.pyside6-addons.overridePythonAttrs (old: lib.optionalAttrs stdenv.isLinux {
    autoPatchelfIgnoreMissingDeps = [
      "libmysqlclient.so.21"
      "libmimerapi.so"
      "libQt6Quick3DSpatialAudio.so.6"
      "libQt6Quick3DHelpersImpl.so.6"
    ];
    preFixup = ''
      addAutoPatchelfSearchPath ${final.shiboken6}/${final.python.sitePackages}/shiboken6
      addAutoPatchelfSearchPath ${final.pyside6-essentials}/${final.python.sitePackages}/PySide6
    '';
    propagatedBuildInputs = old.propagatedBuildInputs or [ ] ++ [
      pkgs.nss
      pkgs.xorg.libXtst
      pkgs.alsa-lib
      pkgs.xorg.libxshmfence
      pkgs.xorg.libxkbfile
    ];
  });
  pyside6 = prev.pyside6.overridePythonAttrs (old: lib.optionalAttrs stdenv.isLinux {
    preBuild = (old.preBuild or "") + ''
      find .
    '';
    postFixup = ''
      find $out/${final.python.sitePackages} -name __pycache__ -prune -exec rm -vrf {} \;
    '';
  });
}
