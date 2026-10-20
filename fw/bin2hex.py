#!/usr/bin/env python3
"""
bin2hex.py -- pack a little-endian RV32 binary into one 32-bit hex
word per line, matching picorv32_ram's word-indexed mem[] array for
$readmemh. Pads the final word with zero bytes if the binary isn't
a multiple of 4 bytes.

Usage: python3 bin2hex.py test.bin test.hex
"""
import sys

def main():
    if len(sys.argv) != 3:
        print("usage: bin2hex.py <input.bin> <output.hex>")
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        data = f.read()

    # Pad to a multiple of 4 bytes
    pad = (-len(data)) % 4
    data += b"\x00" * pad

    with open(sys.argv[2], "w") as out:
        for i in range(0, len(data), 4):
            word = data[i:i+4]
            # little-endian: last byte read is most significant
            value = int.from_bytes(word, byteorder="little")
            out.write(f"{value:08x}\n")

    print(f"Wrote {len(data)//4} words to {sys.argv[2]}")

if __name__ == "__main__":
    main()
