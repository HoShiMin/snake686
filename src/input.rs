use crate::boot;

pub type ScanCode = u8;

pub const SCAN_UP    : ScanCode = 0x48;
pub const SCAN_DOWN  : ScanCode = 0x50;
pub const SCAN_LEFT  : ScanCode = 0x4B;
pub const SCAN_RIGHT : ScanCode = 0x4D;

#[must_use]
pub fn take_scancode() -> ScanCode {
    let mut scancode = 0;
    unsafe {
        core::arch::asm!(
            "xchg {value}, [{addr}]",
            value = inout(reg_byte) scancode,
            addr = const boot::LAST_SCANCODE,
            options(preserves_flags, nostack)
        );
    }
    scancode
}