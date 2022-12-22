{
  stdenv,
  lib,
  callPackage,
  rustc,
  cargo,
  rust-bindgen,
  buildPackages,
  rustPlatform,
}: {
  src,
  configfile,
  modDirVersion,
  version,
  enableRust ? true,
  kernelPatches ? {},
  nixpkgs, # Nixpkgs source
}: let
  baseKernel = (callPackage "${nixpkgs}/pkgs/os-specific/linux/kernel/manual-config.nix" {}) {
    inherit src modDirVersion version kernelPatches configfile;
    inherit lib stdenv;

    # Because allowedImportFromDerivation is not enabled,
    # the function cannot set anything based on the configfile. These settings do not
    # actually change the .config but let the kernel derivation know what can be built.
    # See manual-config.nix for other options
    config = {
      # Enables the dev build
      CONFIG_MODULES = "y";
    };
  };

  kernel =
    if enableRust
    then
      baseKernel.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [rustc cargo rust-bindgen];

        RUST_LIB_SRC = rustPlatform.rustLibSrc;

        # Override install:
        # 1. Don't remove the rust directories
        # 2. Install rust-analyzer support
        postInstall = ''
          mkdir -p $dev
          cp vmlinux $dev/
          if [ -z "''${dontStrip-}" ]; then
            installFlagsArray+=("INSTALL_MOD_STRIP=1")
          fi
          make modules_install $makeFlags "''${makeFlagsArray[@]}" \
            $installFlags "''${installFlagsArray[@]}"
          unlink $out/lib/modules/${modDirVersion}/build
          unlink $out/lib/modules/${modDirVersion}/source

          mkdir -p $dev/lib/modules/${modDirVersion}/{build,source}

          # To save space, exclude a bunch of unneeded stuff when copying.
          (cd .. && rsync --archive --prune-empty-dirs \
              --exclude='/build/' \
              * $dev/lib/modules/${modDirVersion}/source/)

          cd $dev/lib/modules/${modDirVersion}/source

          cp $buildRoot/{.config,Module.symvers} $dev/lib/modules/${modDirVersion}/build

          make modules_prepare $makeFlags "''${makeFlagsArray[@]}" O=$dev/lib/modules/${modDirVersion}/build
          make rust-analyzer $makeFlags "''${makeFlagsArray[@]}" O=$dev/lib/modules/${modDirVersion}/build

          # For reproducibility, removes accidental leftovers from a `cc1` call
          # from a `try-run` call from the Makefile
          rm -f $dev/lib/modules/${modDirVersion}/build/.[0-9]*.d

          # Keep some extra files on some arches (powerpc, aarch64)
          for f in arch/powerpc/lib/crtsavres.o arch/arm64/kernel/ftrace-mod.o; do
            if [ -f "$buildRoot/$f" ]; then
              cp $buildRoot/$f $dev/lib/modules/${modDirVersion}/build/$f
            fi
          done

          # !!! No documentation on how much of the source tree must be kept
          # If/when kernel builds fail due to missing files, you can add
          # them here. Note that we may see packages requiring headers
          # from drivers/ in the future; it adds 50M to keep all of its
          # headers on 3.10 though.

          chmod u+w -R ..

          arch=$(cd $dev/lib/modules/${modDirVersion}/build/arch; ls)
          # Remove unused arches
          for d in $(cd arch/; ls); do
            if [ "$d" = "$arch" ]; then continue; fi
            if [ "$arch" = arm64 ] && [ "$d" = arm ]; then continue; fi
            rm -rf arch/$d
          done

          # Remove all driver-specific code (50M of which is headers)
          rm -fR drivers

          # Keep all headers
          find .  -type f -name '*.h' -print0 | xargs -0 -r chmod u-w

          # Keep linker scripts (they are required for out-of-tree modules on aarch64)
          find .  -type f -name '*.lds' -print0 | xargs -0 -r chmod u-w

          # Keep root and arch-specific Makefiles
          chmod u-w Makefile arch/"$arch"/Makefile*

          # Keep whole scripts dir
          chmod u-w -R scripts

          # Keep whole rust dir
          chmod u-w -R rust

          # Delete everything not kept
          find . -type f -perm -u=w -print0 | xargs -0 -r rm

          # Delete empty directories
          find -empty -type d -delete

          # Remove reference to kmod
          sed -i Makefile -e 's|= ${buildPackages.kmod}/bin/depmod|= depmod|'
        '';
      })
    else baseKernel;

  kernelPassthru = {
    inherit (configfile) structuredConfig;
    inherit modDirVersion configfile;
    passthru = kernel.passthru // (removeAttrs kernelPassthru ["passthru"]);
  };
in
  lib.extendDerivation true kernelPassthru kernel
