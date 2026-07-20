MEMORY { FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 4K }
SECTIONS {
  .vectors 0x00000000 : { KEEP(*(.vectors)) } > FLASH
  .text : { *(.text) *(.text.*) *(.rodata*) } > FLASH
  /DISCARD/ : { *(.ARM.attributes) *(.comment) }
}
