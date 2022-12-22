obj-m += helloworld.o
# CFLAGS_module.o := -DDEBUG

KDIR = $(KERNEL)/lib/modules/$(KERNEL_VERSION)/build

all:
	make -C $(KDIR) M=$(PWD) modules

clean:
	make -C $(KDIR) M=$(PWD) clean

# The following is from https://github.com/PacktPublishing/Linux-Kernel-Programming/blob/master/ch5/lkm_template/Makefile

# Detailed check on the source code styling / etc
checkpatch:
	make clean
	@echo
	@echo "--- kernel code style check with checkpatch.pl ---"
	@echo
	$(KDIR)/source/scripts/checkpatch.pl --no-tree -f --max-line-length=95 *.[ch]

#--- Static Analysis
# sa : "wrapper" target over the following kernel static analyzer targets
sa:
	make sa_sparse
	make sa_gcc
	make sa_flawfinder
	make sa_cppcheck

# static analysis with sparse
sa_sparse:
	make clean
	@echo
	@echo "--- static analysis with sparse ---"
	@echo
# if you feel it's too much, use C=1 instead
	make C=2 CHECK="sparse" -C $(KDIR) M=$(PWD) modules

# static analysis with gcc
sa_gcc:
	make clean
	@echo
	@echo "--- static analysis with gcc ---"
	@echo
	make W=1 -C $(KDIR) M=$(PWD) modules

# static analysis with flawfinder
sa_flawfinder:
	make clean
	@echo
	@echo "--- static analysis with flawfinder ---"
	@echo
	flawfinder *.[ch]

# static analysis with cppcheck
sa_cppcheck:
	make clean
	@echo
	@echo "--- static analysis with cppcheck ---"
	@echo
	cppcheck -v --force --enable=all -i .tmp_versions/ -i *.mod.c -i bkp/ --suppress=missingIncludeSystem .
