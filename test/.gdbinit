set output-radix 16
dir /mnt/z/imaginarium/zuid/src/ /mnt/z/imaginarium/src/util/ /mnt/z/imaginarium/src/krnl/ /mnt/z/imaginarium/include
symbol-file /mnt/z/imaginarium/test/krnl.debug
target remote :1234
#b __kstart
#c