/* main.c
 * Deliberately minimal for the first Zephyr build attempt on this
 * SoC -- no printk/console calls, since no UART driver exists yet
 * (only the devicetree binding). This isolates one thing at a time:
 * does the SoC/board/devicetree/Kconfig chain even resolve and link,
 * before adding driver complexity on top.
 */

int main(void)
{
	while (1) {
		/* nothing yet */
	}

	return 0;
}
