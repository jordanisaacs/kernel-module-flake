#define pr_fmt(fmt) "%s:%s(): " fmt, KBUILD_MODNAME, __func__

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>

MODULE_AUTHOR("Jordan Isaacs");
MODULE_DESCRIPTION("Hello world module");
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION("0.1");

static int __init hello_init(void)
{
	pr_info("Hello, world\n");

	return 0; /* success */
}

static void __exit hello_exit(void)
{
	pr_info("Goodbye, world\n");
}

module_init(hello_init);
module_exit(hello_exit);
