{ pkgs, lib ? pkgs.lib }:
{
  uv2nixEnv =
    { src
    , uvLockFile ? src + "/uv.lock"
    , python ? pkgs.python3
    , uvLock ? builtins.readTOML uvLockFile
    }: builtins.trace uvLock { };
}
