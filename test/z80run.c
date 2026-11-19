// z80run: load a raw binary at ORG, run from ENTRY until it returns to FFFFh
// (pushed as the return address), dump the 64 KB of memory.
// usage: z80run file.bin org entry dump.bin [max_cycles]
#include <stdio.h>
#include <stdlib.h>
#include "z80.h"
static z80 cpu; static uint8_t mem[65536];
static uint8_t rd(void *u, uint16_t a) { (void)u; return mem[a]; }
static void wr(void *u, uint16_t a, uint8_t v) { (void)u; mem[a] = v; }
static uint8_t pin(z80 *z, uint8_t p) { (void)z; (void)p; return 0xFF; }
static void pout(z80 *z, uint8_t p, uint8_t v) { (void)z; (void)p; (void)v; }
int main(int argc, char **argv)
{
    if (argc < 5) return 2;
    FILE *f = fopen(argv[1], "rb"); unsigned org = strtoul(argv[2], 0, 16);
    fread(mem + org, 1, 65536 - org, f); fclose(f);
    unsigned long max = argc > 5 ? strtoul(argv[5], 0, 10) : 2000000000ul;
    z80_init(&cpu); cpu.read_byte = rd; cpu.write_byte = wr; cpu.port_in = pin; cpu.port_out = pout;
    cpu.sp = 0xF000; mem[0xF000] = 0xFF; mem[0xF001] = 0xFF;
    cpu.pc = (uint16_t)strtoul(argv[3], 0, 16);
    while (cpu.pc != 0xFFFF && cpu.cyc < max) z80_step(&cpu);
    printf("%s after %lu cycles\n", cpu.pc == 0xFFFF ? "returned" : "TIME OUT", (unsigned long)cpu.cyc);
    f = fopen(argv[4], "wb"); fwrite(mem, 1, 65536, f); fclose(f);
    return cpu.pc != 0xFFFF;
}
