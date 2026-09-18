use crate::boot;

#[inline(always)]
#[allow(clippy::inline_always)]
pub fn wait_for_interrupt() {
    unsafe {
        core::arch::asm!(
            "hlt",
            options(nomem, nostack, preserves_flags)
        );
    }
}

#[must_use]
pub fn take_counter() -> u32 {
    let mut counter = 0;
    unsafe {
        core::arch::asm!(
            "xchg {value}, [{ptr}]",
            value = inout(reg) counter,
            ptr = const boot::TIMER_COUNTER,
            options(preserves_flags, nostack)
        );
    }
    counter
}