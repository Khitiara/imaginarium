set output-radix 16
dir /mnt/z/imaginarium/src/hal/ /mnt/z/imaginarium/src/util/ /mnt/z/imaginarium/src/krnl/
symbol-file /mnt/z/imaginarium/test/krnl.elf
target remote :1234
b _start
c