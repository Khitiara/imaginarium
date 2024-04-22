set output-radix 16
dir /mnt/z/imaginarium/src/hal/ /mnt/z/imaginarium/src/util/ /mnt/z/imaginarium/src/krnl/
symbol-file /mnt/z/imaginarium/test/krnl.debug
target remote :1234
b __kstart
c