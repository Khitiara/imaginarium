; Config end
ldr_memmap_num equ ldr + 8
ldr_memmap_entries equ ldr + 16
memmap_location equ ldr + 0x100
ebx_save equ ldr + 0x200

  mov es, [ebx_save] ; Get a zero into es
  mov di, memmap_location
  mov word [ldr_memmap_entries], di

memmap_loop:
  mov eax, 0xE820
  mov ebx, [ebx_save]
  mov ecx, 24
  mov edx, 0x534D4150

  mov byte[di + 20], 1

  int 0x15

  jc stopmemmap

  mov [ebx_save], ebx
  add di, 24
  inc word [ldr_memmap_num]

  test ebx, ebx
  jz stopmemmap

  jmp memmap_loop

stopmemmap:
