#[must_use]
#[allow(clippy::cast_possible_truncation)]
pub fn rand() -> usize {
    unsafe { core::arch::x86::_rdtsc() as usize }
}