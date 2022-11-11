obj-m += helloworld.o
# CFLAGS_module.o := -DDEBUG

all:
	make -C $(KERNEL)/lib/modules/$(KERNEL_VERSION)/build M=$(PWD) modules

clean:
	make -C $(KERNEL)/lib/modules/$(KERNEL_VERSION)/build M=$(PWD) clean
