obj-m += rust_out_of_tree.o

KDIR = $(KERNEL)/lib/modules/$(KERNEL_VERSION)/build

default:
	make -C $(KDIR) M=$(PWD)

rust-analyzer:
	$(Q) generate_rust_analyzer $(KDIR) `ls *.rs | head -n 1` > rust-project.json

clean:
	make -C $(KDIR) M=$(PWD) clean
