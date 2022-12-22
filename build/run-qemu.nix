{writeScriptBin}: {
  kernel,
  initramfs,
}:
writeScriptBin "runvm" ''
  sudo qemu-system-x86_64 \
    -enable-kvm \
    -m 1G \
    -kernel ${kernel}/bzImage \
    -initrd ${initramfs}/initrd.gz \
    -nographic -append "console=ttyS0"
''
