.global _start

BOOTSECTOR_BEGIN = 0x7C00

CONVENTIONAL_MEMORY_1_BEGIN = 0x500
CONVENTIONAL_MEMORY_1_SIZE  = BOOTSECTOR_BEGIN - CONVENTIONAL_MEMORY_1_BEGIN

CONVENTIONAL_MEMORY_2_BEGIN = 0x7E00
CONVENTIONAL_MEMORY_2_SIZE  = 0x80000 - CONVENTIONAL_MEMORY_2_BEGIN

FRAMEBUFFER_BEGIN = 0xB8000
SCREEN_WIDTH  = 80
SCREEN_HEIGHT = 25

STACK_BASE = CONVENTIONAL_MEMORY_1_BEGIN + CONVENTIONAL_MEMORY_1_SIZE  # Grows down

IDT_BASE              = CONVENTIONAL_MEMORY_2_BEGIN
IDT_NUMBER_OF_ENTRIES = 256
IDT_ENTRY_SIZE        = 8
IDT_SIZE = IDT_NUMBER_OF_ENTRIES * IDT_ENTRY_SIZE

TIMER_COUNTER_ADDRESS = IDT_BASE + IDT_SIZE
LAST_SCANCODE_ADDRESS = TIMER_COUNTER_ADDRESS + 4

IDT_ENTRY_SIZE = 8


.rodata

#
# We define the entire Global Descriptor Table
# to avoid generating it in runtime.
#
GDT:
    #
    # The first entry must be empty.
    #
    .8byte 0x0000000000000000

    #
    # Code segment (offset is +8 bytes):
    #  Bit offset                   Value
    #  -----------------------------------------------------
    #   +00 Segment Limit [15:0]    = 0xFFFF
    #   +16 Base Address  [15:0]    = 0x0000
    #   +32 Base Address  [23:16]   = 0x00
    #   +40 Accessed                = 1
    #   +41 Readable                = 1
    #   +42 Conforming              = 1
    #   +43 Code/Data               = 1 (marks that this is a code segment)
    #   +44 System/User             = 1 (marks that this is a user segment: either code or data)
    #   +45 DPL                     = 0b00 (Ring0 code segment)
    #   +47 Present                 = 1
    #   +48 Segment Limit [19:16]   = 0x0F (0b1111)
    #   +52 AVL                     = 1
    #   +53 <NONE>                  = 0
    #   +54 Default Operand-Size    = 1 (default operand size and address size is 32 bits)
    #   +55 Granularity             = 1 (segment limit is a multiple of 4096)
    #   +56 Base address [31:24]    = 0x00
    #
    .8byte 0x00DF9F000000FFFF

    #
    # Data segment (offset is +16 bytes):
    #  Bit offset                   Value
    #  -----------------------------------------------------
    #   +00 Segment Limit [15:0]    = 0xFFFF
    #   +16 Base Address  [15:0]    = 0x0000
    #   +32 Base Address  [23:16]   = 0x00
    #   +40 Accessed                = 1
    #   +41 Writeable               = 1
    #   +42 Expand-down             = 0
    #   +43 Code/Data               = 0 (marks that this is a data segment)
    #   +44 System/User             = 1 (marks that this is a user segment: either code or data)
    #   +45 DPL                     = 0b00 (Ring0 code segment)
    #   +47 Present                 = 1
    #   +48 Segment Limit [19:16]   = 0x0F (0b1111)
    #   +52 AVL                     = 1
    #   +53 <NONE>                  = 0
    #   +54 Default Operand-Size    = 1 (default operand size and address size is 32 bits)
    #   +55 Granularity             = 1 (segment limit is a multiple of 4096)
    #   +56 Base address [31:24]    = 0x00
    #
    .8byte 0x00DF93000000FFFF
GDT_END:

GDTR:
    #
    # Global Descriptor Table Register:
    #  Bit offset              Value
    #  -----------------------------------------------------
    #   +00 Limit            = (sizeof(GDT) - 1) - the last accessbile byte in the GDT
    #   +16 Linear address   = &GDT
    #
    .2byte (GDT_END - GDT) - 1  # Limit (the last accessible byte of the GDT)
    .4byte GDT                  # Base (linear address of the GDT)


#
# We define the template for a single entry in Interrupt Descriptor Table
# to generate the whole table in runtime as it's too large to define it statically.
#
IDTR:
    .2byte IDT_SIZE - 1  # Limit
    .4byte IDT_BASE      # Base


#
# Starts at the beginning of the boot sector.
#
.text

#
# We start here, in 16-bit real mode.
# All we need to do here is switch to 32-bit Protected Mode.
#
# Refer to:
#  - Intel Software Developer's Manual, Vol.3, 12.9.1 Switching to Protected Mode.
#  - AMD Architecture Programmer's Manual, Vol.2, 14.4 Initializaing Protected Mode.
#
.code16
_start:
    #
    # Disable blinking, enable intense bit in the background color.
    # IBM PS/2 and PC BIOS Interface Techical Reference, 2-20, INT 10H - Video.
    #
    mov ax, 0x1003
    xor bx, bx
    int 0x10

    #
    # Disable interrupts before switching to Protected Mode
    # to avoid unexpected interrupts before setting up
    # a proper interrupt descriptor table.
    #
    cli

    #
    # Load our Global Descriptor Table
    # with the defined code and data segments.
    #
    mov ecx, offset GDTR
    lgdt [ecx]

    #
    # Set the Protection Enable (CR0.PE) bit.
    #
    mov eax, cr0
    or   al, 1
    mov cr0, eax

    #
    # Starting at this point, we're in Protected Mode,
    # but the segment registers (cs, ds, ss) still have
    # their previous values.
    #
    # In order to reload them to the segments described
    # in our GDT, we have to perform a far intersegment
    # jump: that will update the code segment register,
    # and then, we'll update ds, ss, es and fs manually.
    #
    # So, perform a far jump to 32-bit segment.
    #
    ljmp 0b1000, offset start32  # 0b1000 = (Selector index = 1 (code segment in our GDT), TI = 0, RPL = 0)


#
# It's a 32-bit entry point.
#
# We came here from the 16-bit entry point
# via a far jump to the 32-bit code segment.
#
# We don't use paging (PTEs) here to simplify
# memory management (CR0.PG is set to 0), so
# the only mechanism that manages memory is
# segmentation.
#
# As paging is not enabled, virtual address are
# equal to physical addresses.
#
.code32
start32:
    #
    # First of all, set all the rest of segment
    # selectors to our data segment.
    #
    # Segment selector has the following format:
    # 
    # +----------------+----+-----+
    # | Selector index | TI | RPL |
    # +----------------+----+-----+
    # 16               3    2     0
    #
    # Selector index - index of the segment in GDT.
    # TI (Table indicator) - 0 for GDT, 1 for LDT.
    # RPL (Requestor Privilege Level) - 0..3 for Ring0..Ring3.
    #
    mov ax, (2 << 3)  # (Index = 2 (in our GDT), TI = 0 (use GDT), RPL = 0b00 (Ring0))
    mov ds, ax  #
    mov es, ax  # All of them will use our data segment.
    mov ss, ax  #

    #
    # Setting up the stack.
    # We use the first part of conventional memory [0x500..0x7BFF]
    # setting the stack pointer to the end of this region as
    # a stack grows down.
    #
    # In order to save some bytes, we use a 16-bit mov.
    # It's guaranteed that the high part is zeroed as
    # we came from 16-bit mode with a 16-bit stack.
    #
    mov sp, STACK_BASE

    #
    # Create Interrupt Descriptor Table with 256 entries (each of 8 bytes long).
    # We'll generate it on the fly in conventional memory [0x7E00..(0x7E00 + 255*8)].
    #

    #
    # 32-bit Interrupt-Gate:
    #  Bit offset                               Value
    #  -----------------------------------------------------
    #   +00 Target Code-Segment Offset [15:0]   = ISR.Low (low 16 bits of interrupt handler address)
    #   +16 Target Code-Segment Selector        = 0b1000 (SelectorIndex[7:3]:TI[2]:RPL[1:0] = 1:0:00)
    #   +32 Reserved                            = 0
    #   +40 Type                                = 0b1110 (32-bit interrupt gate)
    #   +44 System/User                         = 0 (this is a system segment: LDT, TSS or Gate)
    #   +45 DPL                                 = 0b00 (it's a Ring0 segment)
    #   +47 Present                             = 1
    #   +48 Target Code-Segment Offset [31:16]  = ISR.High (high 16 bits of interrupt handler address)
    #

    mov cx, 0x7E00  # It's guaranteed that the high part is zeroed as we set it in 16-bit code by setting a 16-bit address of IDTR in ECX.

    mov edx, 0b10001110 << 8  # IDT[N].High: Type: 32-bit interrupt gate, System segment, DPL = 0, Present = 1, ISR.High = 0 as our code resides in 16-bit range. 

    IRQ0_OFFSET = 32 * IDT_ENTRY_SIZE
    IRQ1_OFFSET = IRQ0_OFFSET + IDT_ENTRY_SIZE

    ISR_CS_SELECTOR = (0b1000 << 16)  # Selector = 1 (code segment in our GDT), Table Indicator = 0 (GDT), RPL = 0 (Ring0)

    IRQ0_LOW = isr_timer + ISR_CS_SELECTOR
    mov dword ptr [ecx + IRQ0_OFFSET], offset IRQ0_LOW  # IDT[IRQ0].Low
    mov dword ptr [ecx + IRQ0_OFFSET + 4], edx          # IDT[IRQ0].High

    IRQ1_LOW = isr_keyboard + ISR_CS_SELECTOR
    mov dword ptr [ecx + IRQ1_OFFSET], offset IRQ1_LOW  # IDT[IRQ1].Low
    mov dword ptr [ecx + IRQ1_OFFSET + 4], edx          # IDT[IRQ1].High

    #
    # Load Interrupt Descriptor Table.
    # It's safe as we have interrupts disabled.
    # They were disabled in 16-bit Real Mode and are still disabled.
    #
    # The high part of ECX is still zeroed.
    #

    mov cx, offset IDTR
    lidt [ecx]

    #
    # By default, interrupts from external devices are delivered through 8259 PIC (Programmable Interrupt Controller).
    # This is the legacy controller that was superseded by APIC: IOAPIC + LAPIC (xAPIC, and then x2APIC),
    # but until we enabled them, all we have is this legacy 8259 PIC.
    # And we will continue to use it for simplicity.
    #
    # You can read about 8259 PIC here:
    # - https://wiki.osdev.org/8259_PIC
    # - https://pccomponents.com/datasheets/INTEL-P8259A2.pdf - Datasheet for the original Intel 8259A
    # - Intel 700 Series Chipset Family Platform Controller Hub (PCH) Datasheet, Vol.2, 30 Interrupt, 30.1 Interrupt Registers Summary.
    #
    # 8259 PIC has to parts: master and slave.
    # Each part handles 8 IRQ lines:
    # - IRQ0..IRQ7 in Master PIC.
    # - IRQ8..IRQ15 in Slave PIC.
    # The Slave PIC is connected to IRQ2 of the Master PIC.
    #
    #  Master
    # +------+       Slave
    # | IRQ0 |     +-------+
    # |*IRQ2 <--+  | IRQ8  |
    # | IRQ3 |  |  | IRQ9  |
    # | IRQ4 |  +--| IRQ10 |
    # | IRQ5 |     | IRQ11 |
    # | IRQ6 |     | IRQ12 |
    # | IRQ7 |     | IRQ13 |
    # +------+     | IRQ14 |
    #              | IRQ15 |
    #              +-------+
    #
    # In Real Mode, IRQ0..IRQ7 are mapped to vectors 8..15 in IVT,
    # and IRQ8..IRQ15 are mapped to vectors 0x70..0x77 (112..119).
    #
    # But in Protected Mode, the CPU reserves 0x00..0x1F for its own
    # exceptions, so the IRQs 0..7 conflict with these exceptions,
    # and we have to remap these IRQ lines to somewhat above 0x1F.
    #
    # A common approach is to map IRQ0..IRQ7 to 0x20..0x27.
    # We can do that via reinitialization sequence of master PIC
    # through the ports 0x20 (MICW1) and 0x21 (MICW2, MICW3 and MICW4).
    # "MICW" is "Master Initialization Control Word".
    #
    # For the complete list of IO ports with their description,
    # please, refer to the following sources:
    # - AMD Processor Programming Reference, Vol.6, 11 FCH (Fusion Controller Hub), 11.3.1.1 Registers, LEGACYIO entries.
    # - Intel 700 Series Chipset Family Platform Controller Hub (PCH) Datasheet, Vol.1, 3.0 Memory Mapping, 3.1.2 Fixed I/O Address Ranges.
    # - Intel 700 Series Chipset Family Platform Controller Hub (PCH) Datasheet, Vol.2, 30 Interrupt, 30.1 Interrupt Registers Summary.
    #
    # MICW1 (0x20):
    #  Bit offset                 Value
    #  -----------------------------------------------------
    #  +00 ICW4 Write Required    = 1
    #  +01 Single or Cascade      = 0 (must be programmed to 0 to indicate two controllers operating in cascade mode)
    #  +02 ADI-IGNORED            = 0 (ignored for PCH, should be programmed to 0)
    #  +03 Edge/Level Bank Select = 0 (disabled, replaced by the edge/level triggered control registers (ELCR))
    #  +04 ICW/OCW select         = 1 (must be 1 to select ICW1 and enable the ICW2, ICW3 and, optionally, ICW4 sequence)
    #  +05 ICW/OCW select         = 0b000 (these bits are MCS-85 specific, and not needed, should be programmed to 000)
    #
    # MICW2 (0x21):
    #  Bit offset                        Value
    #  -----------------------------------------------------
    #  +00 Interrupt Request Level       = 0b000 (when writing ICW2, these bits should all be 0)
    #  +03 Interrupt Vector Base Address = 0bXXXXX (the most significant 5 bits of the index in IVT)
    # Note!
    # The resulting IVT index will be (IVT Base Address / 8) + 0..7.
    #
    # MICW3 (0x21):
    #  Bit offset                         Value
    #  -----------------------------------------------------
    #  +00 MICW[1:0]                      = 0b00 (these bits must be programmed to 0)
    #  +02 Cascaded Controller Connection = 1 (this bit must always be set to 1 to indicate the slave controller is cascaded on IRQ2)
    #  +03 MICW3[7:3]                     = 0 (these bits must be programmed to 0)
    #
    # MICW4 (0x21):
    #  Bit offset                         Value
    #  -----------------------------------------------------
    #  +00 Microprocessor Mode            = 1 (this bit must be written to 1 to indicate that we're on an Intel Architecture-based system)
    #  +01 Automatic End of Interrupt     = 0 (normally should be 0)
    #  +02 Master/Slave in Buffered Mode  = 0 (not used, should always be 0)
    #  +03 Buffered Mode                  = 0 (must be cleared for non-buffered mode, writing 1 will result in undefined behavior)
    #  +04 Special Fully Nested Mode      = 0 (should normally be disabled by writing 0)
    #  +05 Reserved                       = 0b000
    #

    mov al, 0b00010001  # MICW1 - start the sequence of ICW2, ICW3, ICW4
    out 0x20, al

    mov dx, 0x21
    
    mov al, 0b00100000  # MICW2 - remap IRQ0..IRQ7 to 0x20..0x27
    out dx, al

    mov al, 0b00000100  # MICW3 - Cascading Slave PIC via IRQ2
    out dx, al

    mov al, 0b00000001  # MICW4 - We're on Intel Architecture-based system
    out dx, al

    #
    # Now Master PIC in a command state, so the PIC will treat the following
    # writes into 0x21 as the command words, not as the initialization words.
    #

    #
    # We interested in keyboard interrupts only,
    # so mask all the rest of them in Master PIC.
    #
    # The keyboard interrupt is bound on IRQ1.
    # You can find all IRQ bindings here:
    # - IBM PC/AT Technical Reference, Mar.86, 1-13 System Board, Hardware Interrupt Listing.
    #
    # By masking IRQ2 we also mask all the Slave IRQs.
    # We can do this via MOCW1 (Master Operational Control Word).
    # MOCW1 (0x21):
    #  Bit offset                 Value
    #  -----------------------------------------------------
    #  +00 Interrupt Request Mask = 0bXXXXXXXX
    #

    mov al, 0b11111100  # Mask all IRQs from Master and Slave PICs except IRQ1 (Keyboard interrupt from 8259 PIC)
    out dx, al          # Mask IRQs in Master PIC

    #
    # Set timer interval to 1 msec by setting a divisor
    # to the base frequency 1'193'182 Hz.
    # The divisor will be 0x4A9.
    #
    
    mov al, 0b00110100
    out 0x43, al
    
    mov al, 0xA9
    out 0x40, al

    mov al, 0x04
    out 0x40, al

    #
    # Now, we can safely unlock interrupts on the CPU.
    #

    sti

    #
    # Ok, let's go!
    #

    call main  # Doesn't return

# - - - - - - - -[ END OF ENTRY POINT ]- - - - - - - -

#
# Handler of IRQ0.
#
isr_timer:
    pusha

    #
    # As we have a single-CPU configuration,
    # we can safely increment this variable
    # without locking.
    #
    inc dword ptr [TIMER_COUNTER_ADDRESS]
    jmp isr_completion


#
# Handler of IRQ1 (Output Buffer Full).
# You can see more about the keyboard handling here:
# - IBM PC/AT Technical Reference, Mar.86, 1-13 System Board, Hardware Interrupt Listing.
#
isr_keyboard:
    pusha

    #
    # I/O port 0x60 contains a 8-bit scancode of the pressed key.
    # As we're in a context of IRQ1, it's guaranteed that the keyboard output
    # buffer is full and we don't need to consult with the bit 1 of the
    # keyboard status register on the port 0x64.
    #
    # Reference:
    # - IBM PC/AT Technical Reference, Mar.86, 1-51 System Board, Output Buffer.
    #

    in al, 0x60
    mov [LAST_SCANCODE_ADDRESS], al

#
# Completion of ISRs.
# We moved it into a dedicated block to save some bytes.
#
isr_completion:
    #
    # Tell the PIC that the interrupt was handled
    # and it's OK to resume sending interrupts.
    #
    # We send End-of-Interrupt to the master PIC.
    # We issue the MOCW2 command:
    #  +00 Interrupt Level Select = 0b000
    #  +03 OCW2 select            = 0b00  - By this field PIC determines that this is exactly an OCW2 command, and not OCW3.
    #  +05 Rotate and EOI Codes   = 0b001 - Non-specific EOI command
    #
    # Refer to:
    # - Intel 700 Series Chipset Family Platform Controller Hub (PCH) Datasheet, Vol.2, 30 Interrupt, 30.1.2 Master Operational Control Word 2 (MOCW2).
    # - https://wiki.osdev.org/X86_Interrupts
    # - https://wiki.osdev.org/8259_PIC
    #
    mov al, 0x20  # 0x20 is MOCW2 with "Rotate and EOI Codes" set to 0b001.
    out 0x20, al  # Send it to the master PIC.

    popa
    iretd