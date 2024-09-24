struc ldr_req
    .magic:     resd 1
    .flags:     resb 1
    alignb 8
    .resp:      resq 1
endstruc