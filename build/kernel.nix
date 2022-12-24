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
  enableRust ? false, # Install the Rust Analyzer
  enableGdb ? false, # Install the GDB scripts
  kernelPatches ? [],
  nixpkgs, # Nixpkgs source
}: let
  kernel =
    ((callPackage "${nixpkgs}/pkgs/os-specific/linux/kernel/manual-config.nix" {})
      {
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
      })
    .overrideAttrs (old: {
      nativeBuildInputs =
        old.nativeBuildInputs
        ++ lib.optionals enableRust [rustc cargo rust-bindgen];
      RUST_LIB_SRC = lib.optionalString enableRust rustPlatform.rustLibSrc;

      dontStrip = true;

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
        ${lib.optionalString enableRust ''
          make rust-analyzer $makeFlags "''${makeFlagsArray[@]}" O=$dev/lib/modules/${modDirVersion}/build
        ''}
        ${lib.optionalString enableGdb (builtins.trace enableGdb ''
          echo "Make scripts"
          make scripts_gdb $makeFlags "''${makeFlagsArray[@]}" O=$dev/lib/modules/${modDirVersion}/build
        '')}

        # For reproducibility, removes accidental leftovers from a `cc1` call
        # from a `try-run` call from the Makefile
        rm -f $dev/lib/modules/${modDirVersion}/build/.[0-9]*.d

        # Keep some extra files on some arches (powerpc, aarch64)
        for f in arch/powerpc/lib/crtsavres.o arch/arm64/kernel/ftrace-mod.o; do
          if [ -f "$buildRoot/$f" ]; then
            cp $buildRoot/$f $dev/lib/modules/${modDirVersion}/build/$f
          fi
        done

        # Not doing the nix default of removing files from the source tree.
        # This is because the source tree is necessary for debugging with GDB.

        # Remove reference to kmod
        sed -i Makefile -e 's|= ${buildPackages.kmod}/bin/depmod|= depmod|'
      '';
    });

  kernelPassthru = {
    inherit (configfile) structuredConfig;
    inherit modDirVersion configfile;
    passthru = kernel.passthru // (removeAttrs kernelPassthru ["passthru"]);
  };
in
  lib.extendDerivation true kernelPassthru kernel
