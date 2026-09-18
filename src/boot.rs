core::arch::global_asm!(include_str!("boot.s"));  // Let the magic happen...

///
/// We placed IDT at the beginning of
/// conventional memory.
///
const IDT_BASE: usize = 0x7E00;

///
/// IDT consists 256 entries by 8 bytes each.
/// 
const IDT_SIZE: usize = 256 * 8;

///
/// This variable is filled in `isr_timer` for IRQ0 in `boot.s`.
/// 
pub const TIMER_COUNTER: usize /* *mut u32 */ = IDT_BASE + IDT_SIZE;

///
/// This variable is filled in `isr_keyboard` for IRQ1 in `boot.s`.
/// 
pub const LAST_SCANCODE: usize /* *mut u8 */ = IDT_BASE + IDT_SIZE + core::mem::size_of::<u32>();