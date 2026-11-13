

OUTPUT_FORMAT("elf32-bigmips")
OUTPUT_ARCH(mips)
ENTRY(_start)

PHDRS {
    irq PT_LOAD AT (0x80000000);
    main PT_LOAD AT (0x80000400);
}

SECTIONS {
    /* Interrupt handlers */
    .intvectors 0x80000000 : {
        . = ALIGN(32);
        KEEP(*(.intvectors))
        __intvectors_end = .;
    }:irq

    /* App code */
    .text 0x80000400 : {
        *(.boot)
        *(.text)
        . = ALIGN(16);
    }:main

    .data : {
        *(.data*)
        n64_static_data_end = .;
    }

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss*)
        __bss_end = .;
    }
}
