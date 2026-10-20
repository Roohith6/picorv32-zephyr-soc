/* main_gpio.c
 * Writes a test pattern to GPIO and holds it there.
 */

#define GPIO_BASE 0x20000000
#define GPIO_DATA (*(volatile unsigned int *)(GPIO_BASE + 0x0))

int main(void)
{
    GPIO_DATA = 0xAA;   /* 10101010 -- easy to visually verify */

    for (;;) {
        /* hold forever */
    }

    return 0;
}
