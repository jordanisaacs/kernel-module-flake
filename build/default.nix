{
  pkgs,
  lib ? pkgs.lib,
}: {
  buildCModule = pkgs.callPackage ./c-module.nix {};
  buildRustModule = pkgs.callPackage ./rust-module.nix {};

  buildInitramfs = pkgs.callPackage ./initramfs.nix {};

  buildKernelConfig = pkgs.callPackage ./kernel-config.nix {};
  buildKernel = pkgs.callPackage ./kernel.nix {};

  buildQemuCmd = pkgs.callPackage ./run-qemu.nix {};
}
