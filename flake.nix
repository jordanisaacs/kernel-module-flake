{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    neovim-flake.url = "github:jordanisaacs/neovim-flake";
  };

  outputs = {
    self,
    nixpkgs,
    neovim-flake,
  }: let
    system = "x86_64-linux";
    enableBPF = true;
    enableRust = true;
    enableEditor = true;
    useRustForLinux = false;

    kernelWithRustInputs = old: old ++ (with pkgs; [rustc rustfmt cargo rust-bindgen]);

    kernelArgs = with pkgs; rec {
      version = "6.1";
      # branchVersion needs to be x.y
      extraMeta.branch = lib.versions.majorMinor version;
      src =
        if useRustForLinux
        then
          fetchurl {
            url = "https://github.com/Rust-for-Linux/linux/archive/bd123471269354fdd504b65b1f1fe5167cb555fc.tar.gz";
            sha256 = "sha256-BcTrK9tiGgCsmYaKpS/Xnj/nsCVGA2Aoa1AktHBgbB0=";
          }
        else
          fetchurl {
            url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
            sha256 = "sha256-LKHxcFGkMPb+0RluSVJxdQcXGs/ZfZZXchJQJwOyXes=";
          };

      # Add kernel patches here
      kernelPatches = [
        {
          name = "bindgen-version-fix";
          patch = ./patches/bindgen-libclang-version.patch;
        }
      ];

      localVersion = "-development";
      modDirVersion = let
        appendV =
          if useRustForLinux
          then ".0-rc1"
          else ".0";
      in
        version + appendV + localVersion;

      # See https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/boot/kernel_config.nix
      structuredExtraConfig = with pkgs.lib.kernel;
        {
          DEBUG_FS = yes;
          DEBUG_KERNEL = yes;
          DEBUG_MISC = yes;
          DEBUG_BUGVERBOSE = yes;
          DEBUG_BOOT_PARAMS = yes;
          DEBUG_STACK_USAGE = yes;
          DEBUG_SHIRQ = yes;
          DEBUG_ATOMIC_SLEEP = yes;

          IKCONFIG = yes;
          IKCONFIG_PROC = yes;
          # Compile with headers
          IKHEADERS = yes;

          SLUB_DEBUG = yes;
          DEBUG_MEMORY_INIT = yes;
          KASAN = yes;

          # FRAME_WARN - warn at build time for stack frames larger tahn this.

          MAGIC_SYSRQ = yes;

          LOCALVERSION = freeform localVersion;

          LOCK_STAT = yes;
          PROVE_LOCKING = yes;

          FTRACE = yes;
          STACKTRACE = yes;
          IRQSOFF_TRACER = yes;

          KGDB = yes;
          UBSAN = yes;
          BUG_ON_DATA_CORRUPTION = yes;
          SCHED_STACK_END_CHECK = yes;
          UNWINDER_FRAME_POINTER = yes;
          "64BIT" = yes;

          # initramfs/initrd support
          BLK_DEV_INITRD = yes;

          PRINTK = yes;
          PRINTK_TIME = yes;
          EARLY_PRINTK = yes;

          # Support elf and #! scripts
          BINFMT_ELF = yes;
          BINFMT_SCRIPT = yes;

          # Create a tmpfs/ramfs early at bootup.
          DEVTMPFS = yes;
          DEVTMPFS_MOUNT = yes;

          TTY = yes;
          SERIAL_8250 = yes;
          SERIAL_8250_CONSOLE = yes;

          PROC_FS = yes;
          SYSFS = yes;

          MODULES = yes;
          MODULE_UNLOAD = yes;

          # FW_LOADER = yes;
        }
        // (
          if enableBPF
          then {
            BPF_SYSCALL = yes;
            # Enable kprobes and kallsyms: https://www.kernel.org/doc/html/latest/trace/kprobes.html#configuring-kprobes
            # Debug FS is be enabled (done above) to show registered kprobes in /sys/kernel/debug: https://www.kernel.org/doc/html/latest/trace/kprobes.html#the-kprobes-debugfs-interface
            KPROBES = yes;
            KALLSYMS_ALL = yes;
          }
          else {}
        )
        // (
          if enableRust
          then {
            GCC_PLUGINS = no;
            RUST = yes;
            RUST_OVERFLOW_CHECKS = yes;
            RUST_DEBUG_ASSERTIONS = yes;
          }
          else {}
        );

      # Flags that get passed to generate-config.pl
      generateConfigFlags = {
        # Ignores any config errors (eg unused config options)
        ignoreConfigErrors = false;
        # Build every available module
        autoModules = false;
        preferBuiltin = false;
      };
    };

    # Config file derivation
    configfile = with pkgs;
      stdenv.mkDerivation ({
          kernelArch = stdenv.hostPlatform.linuxArch;
          extraMakeFlags = [];

          inherit (kernelPkg) src patches version;
          pname = "linux-config";

          inherit (kernelArgs.generateConfigFlags) autoModules preferBuiltin ignoreConfigErrors;
          generateConfig = "${nixpkgs}/pkgs/os-specific/linux/kernel/generate-config.pl";

          kernelConfig = configfile.moduleStructuredConfig.intermediateNixConfig;
          passAsFile = ["kernelConfig"];

          depsBuildBuild = [buildPackages.stdenv.cc];
          nativeBuildInputs = let
            i = [perl gmp libmpc mpfr bison flex pahole];
          in
            if enableRust
            then kernelWithRustInputs i
            else i;

          platformName = stdenv.hostPlatform.linux-kernel.name;
          # e.g. "bzImage"
          kernelTarget = stdenv.hostPlatform.linux-kernel.target;

          makeFlags =
            lib.optionals (stdenv.hostPlatform.linux-kernel ? makeFlags) stdenv.hostPlatform.linux-kernel.makeFlags;

          postPatch =
            kernel.postPatch
            + ''
              # Patch kconfig to print "###" after every question so that
              # generate-config.pl from the generic builder can answer them.
              sed -e '/fflush(stdout);/i\printf("###");' -i scripts/kconfig/conf.c
            '';

          preUnpack = kernel.preUnpack or "";

          buildPhase = ''
            export buildRoot="''${buildRoot:-build}"
            export HOSTCC=$CC_FOR_BUILD
            export HOSTCXX=$CXX_FOR_BUILD
            export HOSTAR=$AR_FOR_BUILD
            export HOSTLD=$LD_FOR_BUILD
            # Get a basic config file for later refinement with $generateConfig.
            make $makeFlags \
              -C . O="$buildRoot" allnoconfig \
              HOSTCC=$HOSTCC HOSTCXX=$HOSTCXX HOSTAR=$HOSTAR HOSTLD=$HOSTLD \
              CC=$CC OBJCOPY=$OBJCOPY OBJDUMP=$OBJDUMP READELF=$READELF \
              $makeFlags

            # Create the config file.
            echo "generating kernel configuration..."
            ln -s "$kernelConfigPath" "$buildRoot/kernel-config"
            DEBUG=1 ARCH=$kernelArch KERNEL_CONFIG="$buildRoot/kernel-config" AUTO_MODULES=$autoModules \
              PREFER_BUILTIN=$preferBuiltin BUILD_ROOT="$buildRoot" SRC=. MAKE_FLAGS="$makeFlags" \
              perl -w $generateConfig
          '';

          installPhase = "mv $buildRoot/.config $out";

          enableParallelBuilding = true;

          passthru = rec {
            module = import "${nixpkgs}/nixos/modules/system/boot/kernel_config.nix";
            # used also in apache
            # { modules = [ { options = res.options; config = svc.config or svc; } ];
            #   check = false;
            # The result is a set of two attributes
            moduleStructuredConfig =
              (lib.evalModules {
                modules = [
                  module
                  {
                    settings = kernelArgs.structuredExtraConfig;
                    _file = "structuredExtraConfig";
                  }
                ];
              })
              .config;

            structuredConfig = moduleStructuredConfig.settings;
          };
        }
        // (
          if enableRust
          then {
            RUST_LIB_SRC = pkgs.rustPlatform.rustLibSrc;
          }
          else {}
        ));

    kernelPkg = let
      kernel = (pkgs.callPackage "${nixpkgs}/pkgs/os-specific/linux/kernel/manual-config.nix" {}) {
        inherit (kernelArgs) src modDirVersion version kernelPatches;
        inherit (pkgs) lib stdenv;
        inherit configfile;

        # Because allowedImportFromDerivation is not enabled,
        # the function cannot set anything based on the configfile. These settings do not
        # actually change the .config but let the kernel derivation know what can be built.
        # See manual-config.nix for other options
        config = {
          # Enables the dev build
          CONFIG_MODULES = "y";
        };
      };

      overrideKernel =
        if enableRust
        then
          kernel.overrideAttrs (old: {
            nativeBuildInputs = old.nativeBuildInputs ++ (with pkgs; [rustc cargo rust-bindgen pkg-config ncurses]);

            RUST_LIB_SRC = pkgs.rustPlatform.rustLibSrc;

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
              unlink $out/lib/modules/${kernelArgs.modDirVersion}/build
              unlink $out/lib/modules/${kernelArgs.modDirVersion}/source

              mkdir -p $dev/lib/modules/${kernelArgs.modDirVersion}/{build,source}

              # To save space, exclude a bunch of unneeded stuff when copying.
              (cd .. && rsync --archive --prune-empty-dirs \
                  --exclude='/build/' \
                  * $dev/lib/modules/${kernelArgs.modDirVersion}/source/)

              cd $dev/lib/modules/${kernelArgs.modDirVersion}/source

              cp $buildRoot/{.config,Module.symvers} $dev/lib/modules/${kernelArgs.modDirVersion}/build

              make modules_prepare $makeFlags "''${makeFlagsArray[@]}" O=$dev/lib/modules/${kernelArgs.modDirVersion}/build
              make rust-analyzer $makeFlags "''${makeFlagsArray[@]}" O=$dev/lib/modules/${kernelArgs.modDirVersion}/build

              # For reproducibility, removes accidental leftovers from a `cc1` call
              # from a `try-run` call from the Makefile
              rm -f $dev/lib/modules/${kernelArgs.modDirVersion}/build/.[0-9]*.d

              # Keep some extra files on some arches (powerpc, aarch64)
              for f in arch/powerpc/lib/crtsavres.o arch/arm64/kernel/ftrace-mod.o; do
                if [ -f "$buildRoot/$f" ]; then
                  cp $buildRoot/$f $dev/lib/modules/${kernelArgs.modDirVersion}/build/$f
                fi
              done

              # !!! No documentation on how much of the source tree must be kept
              # If/when kernel builds fail due to missing files, you can add
              # them here. Note that we may see packages requiring headers
              # from drivers/ in the future; it adds 50M to keep all of its
              # headers on 3.10 though.

              chmod u+w -R ..

              arch=$(cd $dev/lib/modules/${kernelArgs.modDirVersion}/build/arch; ls)
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
              sed -i Makefile -e 's|= ${pkgs.buildPackages.kmod}/bin/depmod|= depmod|'
            '';
          })
        else kernel;

      kernelPassthru = {
        inherit (kernelArgs) structuredExtraConfig modDirVersion configfile;
        passthru = overrideKernel.passthru // (removeAttrs kernelPassthru ["passthru"]);
      };

      finalKernel = pkgs.lib.extendDerivation true kernelPassthru overrideKernel;
    in
      finalKernel;

    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        neovim-flake.overlays.default
        (self: super: {
          linuxDev = self.linuxPackagesFor kernelPkg;
          busybox = super.busybox.override {
            enableStatic = true;
          };
        })
      ];
    };

    neovimPkg =
      (neovim-flake.lib.neovimConfiguration {
        inherit pkgs;
        modules = [
          {
            config = {
              vim.lsp = {
                enable = true;
                lightbulb.enable = true;
                lspSignature.enable = true;
                trouble.enable = true;
                nvimCodeActionMenu.enable = true;
                formatOnSave = true;
                clang = {
                  enable = true;
                  c_header = true;
                };
                rust = {
                  enable = enableRust;
                  rustAnalyzerOpts = let
                    cmd =
                      pkgs.writeShellScript
                      "module-ra-check"
                      ''make -s "KRUSTFLAGS+=--error-format=json" 2>&1 | grep -v "^make"'';
                  in ''
                    ["rust-analyzer"] = {
                      cargo = {
                        buildScripts = {
                          overrideCommand = {"${cmd}"},
                        },
                      },
                      checkOnSave = {
                        overrideCommand = {"${cmd}"},
                      },
                    },
                  '';
                };
                nix.enable = true;
              };
              vim.statusline.lualine = {
                enable = true;
                theme = "onedark";
              };
              vim.visuals = {
                enable = true;
                nvimWebDevicons.enable = true;
                lspkind.enable = true;
                indentBlankline = {
                  enable = true;
                  fillChar = "";
                  eolChar = "";
                  showCurrContext = true;
                };
                cursorWordline = {
                  enable = true;
                  lineTimeout = 0;
                };
              };
              vim.theme = {
                enable = true;
                name = "onedark";
                style = "darker";
              };
              vim.autopairs.enable = true;
              vim.autocomplete = {
                enable = true;
                type = "nvim-cmp";
              };
              vim.filetree.nvimTreeLua.enable = true;
              vim.tabline.nvimBufferline.enable = true;
              vim.telescope = {
                enable = true;
              };
              vim.markdown = {
                enable = true;
                glow.enable = true;
              };
              vim.treesitter = {
                enable = true;
                context.enable = true;
              };
              vim.keys = {
                enable = true;
                whichKey.enable = true;
              };
              vim.git = {
                enable = true;
                gitsigns.enable = true;
              };
              vim.tabWidth = 8;
            };
          }
        ];
      })
      .neovim;

    linuxPackages = pkgs.linuxDev;
    kernel = linuxPackages.kernel;

    runQemuV2 = pkgs.writeScriptBin "runvm" ''
      sudo qemu-system-x86_64 \
        -enable-kvm \
        -m 1G \
        -kernel ${kernel}/bzImage \
        -initrd ${initramfs}/initrd.gz \
        -nographic -append "console=ttyS0"
    '';

    buildCInputs = with pkgs; [
      nukeReferences
      kernel.dev
    ];

    buildCModule = {
      name,
      src,
    }:
      pkgs.stdenv.mkDerivation {
        KERNEL = kernel.dev;
        KERNEL_VERSION = kernel.modDirVersion;
        buildInputs = buildCInputs;
        inherit name src;

        installPhase = ''
          mkdir -p $out/lib/modules/$KERNEL_VERSION/misc
          for x in $(find . -name '*.ko'); do
            nuke-refs $x
            cp $x $out/lib/modules/$KERNEL_VERSION/misc/
          done
        '';

        meta.platforms = ["x86_64-linux"];
      };

    buildRustInputs = with pkgs; [
      nukeReferences
      rustc
      kernel.dev
    ];

    buildRustModule = {
      name,
      src,
    }:
      pkgs.stdenv.mkDerivation {
        KERNEL = kernel.dev;
        KERNEL_VERSION = kernel.modDirVersion;
        buildInputs = buildRustInputs;
        inherit name src;

        installPhase = ''
          mkdir -p $out/lib/modules/$KERNEL_VERSION/misc
          for x in $(find . -name '*.ko'); do
            nuke-refs $x
            cp $x $out/lib/modules/$KERNEL_VERSION/misc/
          done
        '';

        meta.platforms = ["x86_64-linux"];
      };

    helloworld = buildCModule {
      name = "helloworld";
      src = ./helloworld;
    };

    rustOutOfTree = buildRustModule {
      name = "rust-out-of-tree";
      src =
        if useRustForLinux
        then ./rfl_rust
        else ./rust;
    };

    genRustAnalyzer =
      pkgs.writers.writePython3Bin
      "generate_rust_analyzer"
      {}
      (builtins.readFile ./scripts/generate_rust_analyzer.py);

    shellInputs = with pkgs;
      [
        bear # for compile_commands.json, use bear -- make
        runQemuV2
        git
        gdb
        qemu
        pahole

        # static analysis
        flawfinder
        cppcheck
        sparse
        rustc
      ]
      ++ lib.optional enableEditor neovimPkg
      ++ lib.optionals enableRust (buildRustInputs ++ [cargo rustfmt genRustAnalyzer]);

    shellPkg = pkgs.mkShell {
      nativeBuildInputs = shellInputs; #++ buildCInputs;
      KERNEL = kernel.dev;
      KERNEL_VERSION = kernel.modDirVersion;
      RUST_LIB_SRC = pkgs.rustPlatform.rustLibSrc;
    };

    ebpf_stacktrace = pkgs.stdenv.mkDerivation {
      name = "ebpf_stacktrace";
      src = ./ebpf_stacktrace;
      installPhase = ''
        runHook preInstall

        mkdir $out
        cp ./helloworld $out/
        cp ./helloworld_dbg $out/
        cp runit.sh $out/

        runHook postInstall
      '';
      meta.platforms = ["x86_64-linux"];
    };

    initramfs = let
      initrdBinEnv = pkgs.buildEnv {
        name = "initrd-emergency-env";
        paths = map pkgs.lib.getBin initrdBin;
        pathsToLink = ["/bin" "/sbin"];
        postBuild = pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList (n: v: "ln -s ${v} $out/bin/${n}") extraBin);
      };

      moduleEnv = pkgs.buildEnv {
        name = "initrd-modules";
        paths = [helloworld] ++ pkgs.lib.optional enableRust rustOutOfTree;
        pathsToLink = ["/lib/modules/${kernel.modDirVersion}/misc"];
      };

      config =
        {
          "/bin" = "${initrdBinEnv}/bin";
          "/sbin" = "${initrdBinEnv}/sbin";
          "/init" = init;
          "/modules" = "${moduleEnv}/lib/modules/${kernel.modDirVersion}/misc";
        }
        // (
          if enableBPF
          then {
            "/ebpf" = ebpf_stacktrace;
          }
          else {}
        );

      initrdBin = [pkgs.bash pkgs.busybox pkgs.kmod];
      extraBin =
        {
          strace = "${pkgs.strace}/bin/strace";
        }
        // (
          if enableBPF
          then {
            stackcount = "${pkgs.bcc}/bin/stackcount";
          }
          else {}
        );

      storePaths =
        [pkgs.foot.terminfo]
        ++ (
          if enableBPF
          then [pkgs.bcc pkgs.python3]
          else []
        );

      initialRamdisk = pkgs.makeInitrdNG {
        compressor = "gzip";
        strip = false;
        contents =
          map (path: {
            object = path;
            symlink = "";
          })
          storePaths
          ++ pkgs.lib.mapAttrsToList (n: v: {
            object = v;
            symlink = n;
          })
          config;
      };

      init = pkgs.writeScript "init" ''
        #!/bin/sh

        export PATH=/bin/

        mkdir /proc
        mkdir /sys
        mount -t proc none /proc
        mount -t sysfs none /sys
        mount -t debugfs debugfs /sys/kernel/debug

        mknod -m 666 /dev/null c 1 3
        mknod -m 666 /dev/tty c 5 0
        mknod -m 644 /dev/random c 1 8
        mknod -m 644 /dev/urandom c 1 9

        mkdir -p /run/booted-system/kernel-modules/lib/modules/${kernel.modDirVersion}/build
        tar -xf /sys/kernel/kheaders.tar.xz -C /run/booted-system/kernel-modules/lib/modules/${kernel.modDirVersion}/build

        cat <<!

        Boot took $(cut -d' ' -f1 /proc/uptime) seconds

                _       _     __ _
          /\/\ (_)_ __ (_)   / /(_)_ __  _   ___  __
         /    \| | '_ \| |  / / | | '_ \| | | \ \/ /
        / /\/\ \ | | | | | / /__| | | | | |_| |>  <
        \/    \/_|_| |_|_| \____/_|_| |_|\__,_/_/\_\

        Welcome to mini_linux


        !

        # Get a new session to allow for job control and ctrl-* support
        exec setsid -c /bin/sh
      '';
    in
      initialRamdisk;
  in {
    packages.${system} = {
      inherit initramfs kernel helloworld ebpf_stacktrace rustOutOfTree;
      kernelConfig = configfile;
    };

    devShells.${system}.default = shellPkg;
  };
}
