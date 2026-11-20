// Build on the PYNQ target with:
//   cc -O2 -fPIC -shared -o libzephyr_arm_barrier.so arm_barrier.c
// The MMIO mapping supplies device ordering; this helper supplies the explicit
// architectural completion barrier required by the software contract.
#if !defined(__arm__) && !defined(__aarch64__)
#error "arm_barrier.c must be compiled for an ARM target"
#endif

void zephyr_dsb_sy(void)
{
    __asm__ __volatile__("dsb sy" ::: "memory");
}
