obj-m += rust_out_of_tree.o

KDIR = $(KERNEL)/lib/modules/$(KERNEL_VERSION)/build

default:
	make -C $(KDIR) M=$(PWD)
