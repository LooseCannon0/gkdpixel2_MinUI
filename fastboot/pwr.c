// pwr — minimal power control for a PID-1 shell environment with no init system.
// Calls the reboot(2) syscall directly: the same final step systemd performs.
// Usage: pwr off | pwr reboot
#include <unistd.h>
#include <string.h>
#include <sys/reboot.h>
#include <linux/reboot.h>

int main(int argc, char** argv) {
    sync();
    if (argc > 1 && !strcmp(argv[1], "reboot"))
        reboot(LINUX_REBOOT_CMD_RESTART);
    else
        reboot(LINUX_REBOOT_CMD_POWER_OFF);
    // If the syscall returns, it failed; let the caller fall back.
    return 1;
}
