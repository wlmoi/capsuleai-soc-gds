SECTIONS {
  . = 0;
  .text : { *(.text.start) *(.text*) *(.rodata*) *(.srodata*) }
  .data : { *(.data*) *(.sdata*) *(.bss*) *(.sbss*) }
  /DISCARD/ : { *(.eh_frame*) *(.comment) *(.riscv.attributes) *(.note*) }
}
