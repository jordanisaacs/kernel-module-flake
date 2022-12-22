// SPDX-License-Identifier: GPL-2.0

//! Rust out-of-tree sample.

use kernel::prelude::*;

module! {
    type: RustMinimal,
    name: "rust_out_of_tree",
    author: "Rust for Linux Contributors",
    description: "Rust out-of-tree sample",
    license: "GPL",
}

struct RustMinimal {
    numbers: Vec<i32>,
}

impl kernel::Module for RustMinimal {
    fn init(_name: &'static CStr, _module: &'static ThisModule) -> Result<Self> {
        pr_alert!("Rust out-of-tree sample (init)\n");

        let mut numbers = Vec::new();
        numbers.try_push(72)?;
        numbers.try_push(108)?;
        numbers.try_push(200)?;

        Ok(RustMinimal { numbers })
    }
}

impl Drop for RustMinimal {
    fn drop(&mut self) {
        pr_alert!("My numbers are {:?}\n", self.numbers);
        pr_alert!("Rust out-of-tree sample (exit)\n");
    }
}
