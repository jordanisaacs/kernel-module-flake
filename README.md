# Kernel Module Flake

Get started by cloning this repository.

```bash
git clone git@github.com:jordanisaacs/kernel-module-flake
cd kernel-module-flake

# nix develop .# or direnv allow to get into the dev environment

runvm   # Calls QEMU with the necessary commands, uses sudo for enabling kvm

#### Inside QEMU
# insmod module/helloworld.ko   # Load the kernel module
# rmmod module/helloworld.ko    # Unload the module
#### C^A+X to exit

cd helloworld
bear -- make            # generate the compile_commands.json
vim helloworld.c        # Start editing!

# exit and then nix develop .# or just direnv reload
# to rebuild and update the runvm command
```

Time to build (on Ryzen 5 3600 - 6 cores):

![time](https://user-images.githubusercontent.com/19742638/201808063-3315027f-44c6-4bd7-bf48-a835b1ffe096.png)

## How it works

### Kernel Build

A custom kernel is built according to Chris Done's [Build and run minimal Linux / Busybox systems in Qemu](https://gist.github.com/chrisdone/02e165a0004be33734ac2334f215380e). Also some extra config is added which I got through Kaiwan Billimoria's [Linux Kernel Programming](https://www.packtpub.com/product/linux-kernel-programming/9781789953435). In order to do this in Nix a custom config file is generated using a modified version of the `configfile` derivation in the [generic kernel builder](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/os-specific/linux/kernel/generic.nix) also known as the `buildLinux` function. This was necessary as the default NixOS distribution defaults needed to be removed. More documentation is inside the flake. A new package set called `linuxDev` is then added as an overlay using `linuxPackagesFor`.

### initramfs

The initial ram disk is built using the new [make-initrd-ng](https://github.com/NixOS/nixpkgs/tree/master/pkgs/build-support/kernel/make-initrd-ng). It is called through its [nix wrapper](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/kernel/make-initrd-ng.nix) which safely copies the nix store packages needed over. Busybox is included and the helloworld kernel module.

### Kernel Module

The kernel module is built using nix. You can build it manually with `nix build .#helloworld`. It is included in the initramfs.

### Neovim Editor

A neovim editor is provided that is set up for Nix and C (CCLS) with LSPs for both and autoformatting. See my [neovim-flake](https://github.com/jordanisaacs/neovim-flake) for more details. The clang-format was copied over from the linux source tree. To get CCLS working correctly call `bear -- make` to get a `compile_commands.json`.

![editor preview](https://user-images.githubusercontent.com/19742638/201808644-68674027-277e-4d61-9ebe-e2197b570730.png)

### Direnv

If you have nix-direnv enabled a shell with everything you need should open when you `cd` into the directory after calling `direnv allow`

### Modifying the flake

The flake.nix is documented so it should be self explanatory for editing it to your needs. I will keep updating it with more features as I learn more about kernel development.
