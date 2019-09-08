#!/bin/sh

tass="64tass"
dest="./build"
name="liaraforth"

$tass --m65816 "${name}.asm" --long-address --intel-hex -o "${dest}/${name}.hex" --list "${dest}/${name}.lst" 2>&1

# generate ascii file that may be compared byte-by-byte with tinkereres assembler output
#$tass --m65816 "${name}.asm" -b -o "${dest}/${name}.bin" 
#xxd "${dest}/${name}.bin" > "${dest}/${name}.asc"
