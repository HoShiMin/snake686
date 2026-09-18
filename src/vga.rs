#![allow(dead_code)]

pub const ADDR: usize = 0xB8000;
pub const WIDTH: usize = 80;
pub const HEIGHT: usize = 25;

pub const CELL_BYTES: usize = core::mem::size_of::<Cell>();
pub const ROW_BYTES: usize = WIDTH * CELL_BYTES;
pub const PLAIN_SIZE: usize = WIDTH * HEIGHT;
pub const PLAIN_BYTES: usize = PLAIN_SIZE * CELL_BYTES;

pub type AnsiChar = u8;
pub type CellColor = u8;

#[repr(u8)]
#[derive(Clone, Copy)]
pub enum Color {
    Black,
    Blue,
    Green,
    Cyan,
    Red,
    Magenta,
    Brown,
    White,
    Gray,
    LightBlue,
    LightGreen,
    LightCyan,
    LightRed,
    LightMagenta,
    Yellow,
    BrightYellow
}

impl Color {
    #[must_use]
    pub const fn from_parts(background: Color, text: Color) -> CellColor {
        ((background as u8) << 4 | (text as u8)) & 0xFE
    }
}


#[repr(C)]
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Cell(u16);

impl Cell {
    #[must_use]
    pub const fn new(sym: u8, color: CellColor) -> Self {
        Self(((color as u16) << 8) | (sym as u16))
    }

    #[must_use]
    pub const fn as_raw(self) -> u16 {
        self.0
    }

    #[must_use]
    pub const fn from_raw(raw: u16) -> Self {
        Self(raw)
    }

    #[must_use]
    pub const fn sym(self) -> u8 {
        self.0 as u8
    }

    #[must_use]
    pub const fn color(self) -> u8 {
        (self.0 >> 8) as u8
    }
}

pub const CELL_EMPTY: Cell = Cell(0);


#[derive(Clone, Copy)]
pub struct Pos(usize);

impl Pos {
    #[must_use]
    pub const fn new(addr: usize) -> Self {
        Self(addr)
    }

    #[must_use]
    pub fn get(self) -> usize {
        self.0
    }

    pub fn set(&mut self, addr: usize) {
        self.0 = addr;
    }

    pub fn add(&mut self, value: usize) {
        self.0 += value;
    }

    pub fn sub(&mut self, value: usize) {
        self.0 -= value;
    }

    #[must_use]
    pub fn read_cell(self) -> Cell {
        let addr = self.0 as *const Cell;
        unsafe { core::ptr::read_volatile(addr) }
    }

    #[must_use]
    pub fn read_sym(self) -> AnsiChar {
        let addr = self.0 as *const AnsiChar;
        unsafe { core::ptr::read_volatile(addr) }
    }

    #[must_use]
    pub fn read_color(self) -> AnsiChar {
        let addr = (self.0 + 1) as *const AnsiChar;
        unsafe { core::ptr::read_volatile(addr) }
    }

    pub fn write_cell(self, cell: Cell) {
        let addr = self.0 as *mut Cell;
        unsafe { core::ptr::write_volatile(addr, cell); }
    }

    pub fn write_sym(self, sym: AnsiChar) {
        let addr = self.0 as *mut AnsiChar;
        unsafe { core::ptr::write_volatile(addr, sym); }
    }

    pub fn write_color(self, color: CellColor) {
        let addr = (self.0 + 1) as *mut CellColor;
        unsafe { core::ptr::write_volatile(addr, color); }
    }

    #[must_use]
    pub fn replace(self, cell: Cell) -> Cell {
        let mut raw = cell.as_raw();
        unsafe {
            core::arch::asm!(
                "xchg {reg16:x}, [{offset}]",
                offset = in(reg) self.0,
                reg16 = inout(reg) raw,
                options(preserves_flags, nostack)
            );
        }

        Cell::from_raw(raw)
    }
}

#[must_use]
pub fn read<T: Copy>(addr: usize) -> T {
    unsafe { core::ptr::read_volatile(addr as *const T) }
}

pub fn write<T: Copy>(addr: usize, value: T) {
    unsafe { core::ptr::write_volatile(addr as *mut T, value); }
}

pub fn clear() {
    unsafe {
        core::arch::asm!(
            "2:",
            "  mov byte ptr [{base} + ecx], 0",
            "  loop 2b",
            base = const ADDR,
            in("ecx") PLAIN_BYTES - 1,
            options(nostack)
        );
    }
}