{
  stdenv,
  nukeReferences,
  rustc,
}: {kernel}: {
  name,
  src,
}:
stdenv.mkDerivation {
  KERNEL = kernel.dev;
  KERNEL_VERSION = kernel.modDirVersion;
  buildInputs = [kernel.dev nukeReferences rustc];
  inherit name src;

  installPhase = ''
    mkdir -p $out/lib/modules/$KERNEL_VERSION/misc
    for x in $(find . -name '*.ko'); do
      nuke-refs $x
      cp $x $out/lib/modules/$KERNEL_VERSION/misc/
    done
  '';

  meta.platforms = ["x86_64-linux"];
}
