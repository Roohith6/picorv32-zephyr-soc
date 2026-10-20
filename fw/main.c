/* main.c
 * First C program: proves the full compile -> link -> run pipeline
 * works, using UART to send a short, visibly checkable string.
 */

#define UART_BASE       0x10000000
#define UART_TX_DATA    (*(volatile unsigned int *)(UART_BASE + 0x0))
#define UART_TX_STATUS  (*(volatile unsigned int *)(UART_BASE + 0x4))

static void uart_putc(char c)
{
    while (!(UART_TX_STATUS & 1)) {
        /* wait until tx_ready */
    }
    UART_TX_DATA = (unsigned int)c;
}

static void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s);
        s++;
    }
}

int main(void)
{
    uart_puts("Hi");

    for (;;) {
        /* halt here forever */
    }

    return 0;
}
