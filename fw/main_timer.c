/* main_timer.c
 * Reads the free-running timer, burns some cycles in a loop, reads it
 * again, and stores both values to RAM so the testbench can check
 * that the counter genuinely advanced (not just left at a constant).
 */

#define TIMER_BASE  0x30000000
#define TIMER_COUNT (*(volatile unsigned int *)(TIMER_BASE + 0x0))

#define RESULT0 (*(volatile unsigned int *)(0x00000100))
#define RESULT1 (*(volatile unsigned int *)(0x00000104))

int main(void)
{
    unsigned int t0, t1;
    volatile int i;

    t0 = TIMER_COUNT;

    for (i = 0; i < 50; i++) {
        /* busy-loop delay */
    }

    t1 = TIMER_COUNT;

    RESULT0 = t0;
    RESULT1 = t1;

    for (;;) {
        /* halt here forever */
    }

    return 0;
}
