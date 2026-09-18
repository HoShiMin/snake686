#![no_std]
#![no_main]
#![warn(clippy::pedantic)]
#![allow(clippy::cast_possible_truncation)]
#![allow(clippy::cast_possible_wrap)]
#![allow(clippy::cast_sign_loss)]
#![allow(clippy::struct_field_names)]
#![allow(clippy::decimal_bitwise_operands)]

//
// 0x0000: Interrupt Vector Table
// 0x0400: BIOS data area
// 0x0500: Conventional memory
// ...
// ↑ Stack
// 0x7C00: _start // Bootstrap code area (446 bytes)
// ↓ Code
// ...
// MBR Partition Table beginning:
// 0x7DBE: +0: Partition 1 Entry
//         +8: Partition 2 Entry
//        +16: Partition 3 Entry
//        +24: Partition 4 Entry
// 0x7DFE: 0xAA55 Boot signature
// 0x7E00: Conventional memory
// ...
// 0x80000: Extended BIOS Data Area
// ...
// 0xA0000: Video display memory
// ...
// 0xB8000: Text screen video memory
// ...
// 0xC0000: Video BIOS
// ...
// 0xC8000: BIOS expansion
// ...
// 0xF0000..0xFFFFF: Motherboard BIOS
//

mod boot;
mod vga;
mod input;
mod clk;
mod cpu;

const SNAKE_COLOR: vga::CellColor = vga::Color::from_parts(vga::Color::Green, vga::Color::Green);
const FOOD_COLOR: vga::CellColor = vga::Color::from_parts(vga::Color::LightBlue, vga::Color::LightBlue);


struct Snake {
    head: vga::Pos,
    tail: vga::Pos
}

impl Snake {
    #[must_use]
    fn new() -> Self {
        use vga::Cell;

        const SNAKE_CELL: Cell = Cell::new(1, SNAKE_COLOR);

        const OFFSET_TO_CENTER: usize = ((vga::HEIGHT / 2) * vga::WIDTH - (vga::WIDTH / 2)) * vga::CELL_BYTES;
        const SNAKE_WIDTH: usize = 5;

        let tail = vga::Pos::new(vga::ADDR + OFFSET_TO_CENTER - SNAKE_WIDTH * vga::CELL_BYTES);
        tail.write_cell(SNAKE_CELL);

        let mut head = tail;

        for _ in 0..SNAKE_WIDTH {
            head.add(vga::CELL_BYTES);
            head.write_cell(SNAKE_CELL);
        }

        Self { head, tail }
    }

    fn spawn_food() {
        loop {
            let rand_color_addr = vga::ADDR + ((cpu::rand() % vga::PLAIN_BYTES) | 1);
            let probing_cell = vga::read::<u8>(rand_color_addr);

            if probing_cell != 0 {
                continue;  // Try another cell if this cell is already claimed.
            }

            vga::write(rand_color_addr, FOOD_COLOR);

            break;
        }
    }

    fn shift(pos: &mut vga::Pos, scan: input::ScanCode) {
        pos.add((scan as i8 as isize as usize) << 1);

        let base = vga::ADDR;
        let normalized = (pos.get() - base) as isize;

        pos.set(base + normalized.rem_euclid(vga::PLAIN_BYTES as isize) as usize);
    }

    #[must_use]
    fn step(&mut self) -> bool {
        use vga::Cell;

        let head = &mut self.head;
        let direction = head.read_sym();

        Self::shift(head, direction);

        let prev_type = head.replace(Cell::new(direction, SNAKE_COLOR)).color();
        
        if prev_type == FOOD_COLOR {
            Self::spawn_food();
        } else {
            // Tuck our tail:
            let tail_direction = self.tail.replace(vga::CELL_EMPTY).sym();
            Self::shift(&mut self.tail, tail_direction);
        }

        prev_type != SNAKE_COLOR
    }

    fn handle_input(&mut self, scancode: input::ScanCode) {
        if scancode == 0 || (scancode & 0b1000_0000) != 0 {
            return;
        }

        let mut scans = ((input::SCAN_LEFT  as usize) << 24)
                      | ((input::SCAN_RIGHT as usize) << 16)
                      | ((input::SCAN_UP    as usize) << 8)
                      | ( input::SCAN_DOWN  as usize);

        let mut offsets = (( -1_i8 as u8 as usize) << 24)
                        | ((  1_i8 as u8 as usize) << 16)
                        | ((-80_i8 as u8 as usize) << 8)
                        | (  80_i8 as u8 as usize);

        for _ in 0..4 {
            if scancode == (scans as u8) {
                if self.head.read_sym() as i8 != -(offsets as i8) {
                    self.head.write_sym(offsets as u8);
                }
                return;
            }
            scans >>= 8;
            offsets >>= 8;
        }
    }
}

#[unsafe(no_mangle)]
extern "system" fn main() -> ! {
    loop {
        vga::clear();

        let mut snake = Snake::new();
        Snake::spawn_food();

        while snake.step() {
            let mut tick_count = 0;
            while tick_count < 50 {
                clk::wait_for_interrupt();
                tick_count += clk::take_counter();
                snake.handle_input(input::take_scancode());
            }
        }
    }
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}