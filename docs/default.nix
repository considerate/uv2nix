{ uv2nix, buildPackages, runCommand, nixos-render-docs }:
let
  eval = uv2nix.uv2nix {
    useLock = false;
  };
  options = buildPackages.nixosOptionsDoc {
    inherit (eval) options;
    warningsAreErrors = false;
  };
in
{
  docs = runCommand "options.md" { } ''
    cp ${options.optionsCommonMark}  $out
  '';
  manpages = runCommand "uv2nix.5"
    {
      nativeBuildInputs =
        [ buildPackages.installShellFiles nixos-render-docs ];
      allowedReferences = [ "out" ];
    } ''
    # Generate manpages.
    mkdir -p $out/share/man/man5
    nixos-render-docs -j $NIX_BUILD_CORES options manpage \
      --revision "0.0.1" \
      --header ${./uv2nix-header.5} \
      --footer ${./uv2nix-footer.5} \
      ${options.optionsJSON}/share/doc/nixos/options.json \
      $out/share/man/man5/uv2nix.5
  '';
}
