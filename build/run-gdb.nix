{
  lib,
  writeScriptBin,
  runCommand,
  gdb,
}: {
  kernel,
  modules ? [],
}: let
  moduleDirs =
    builtins.concatStringsSep
    " "
    (builtins.map
      (m: "${m}/lib/modules/${kernel.modDirVersion}/misc")
      modules);
in
  # Need a to go a directroy above source (eg. scripts) because vmlinux is using relative path
  writeScriptBin "rungdb" ''
    ${gdb}/bin/gdb \
      -ex "dir ${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/scripts" \
      -ex "file ${kernel.dev}/vmlinux" \
      -ex "source ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build/vmlinux-gdb.py" \
      -ex "alias lx-symbols-nix = lx-symbols ${moduleDirs}" \
      -ex "target remote localhost:1234"
  ''
