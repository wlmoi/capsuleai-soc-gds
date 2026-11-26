#!/bin/bash
set -e
cd "$(dirname "$0")"
python3 -m ziglang cc -target riscv32-freestanding-none -mcpu=generic_rv32+m -O2 -nostdlib -ffreestanding \
  -fno-builtin -fno-unwind-tables -fno-asynchronous-unwind-tables -T link.ld start.S firmware.c -o firmware.elf
python3 -m ziglang objcopy -O binary firmware.elf firmware.bin
python3 - <<'PY'
import struct
b = open('firmware.bin', 'rb').read(); b += b'\0' * (-len(b) % 4)
w = [struct.unpack('<I', b[i:i+4])[0] for i in range(0, len(b), 4)]
w += [0] * (4096 - len(w))
open('firmware.hex', 'w').write('\n'.join(f'{x:08x}' for x in w) + '\n')
print(len(b), 'bytes of firmware')
PY
