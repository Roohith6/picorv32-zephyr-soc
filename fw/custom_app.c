#define UART_BASE       0x10000000
#define UART_TX_DATA    (*(volatile unsigned int *)(UART_BASE + 0x0))
#define UART_TX_STATUS  (*(volatile unsigned int *)(UART_BASE + 0x4))

#define GPIO_BASE       0x20000000
#define GPIO_DATA       (*(volatile unsigned int *)(GPIO_BASE + 0x0))

#define TIMER_BASE      0x30000000
#define TIMER_COUNT     (*(volatile unsigned int *)(TIMER_BASE + 0x0))

static void uart_putc(char c) {
    while (!(UART_TX_STATUS & 1)) {
        /* wait until tx_ready */
    }
    UART_TX_DATA = (unsigned int)c;
}

static void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s);
        s++;
    }
}

/* A simple delay function that uses our custom hardware Timer! */
static void delay_cycles(unsigned int cycles) {
    unsigned int start = TIMER_COUNT;
    while ((TIMER_COUNT - start) < cycles) {
        /* Wait */
    }
}

int main(void) {
    uart_puts("--------------------------------\n");
    uart_puts("Hello from Custom C Firmware!\n");
    uart_puts("--------------------------------\n");
    
    uart_puts("Blinking GPIO pins...\n");

    for (int i = 1; i <= 3; i++) {
        GPIO_DATA = 0xFF; /* Turn all LEDs ON */
        delay_cycles(200); 
        
        GPIO_DATA = 0x00; /* Turn all LEDs OFF */
        delay_cycles(200);
    }

    uart_puts("Done blinking. Halting CPU.\n");

    for (;;) {
        /* halt here forever */
    }

    return 0;
}
