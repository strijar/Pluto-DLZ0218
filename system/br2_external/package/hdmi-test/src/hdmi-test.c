// SPDX-License-Identifier: MIT
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "/dev/fb0";
    struct fb_fix_screeninfo fix;
    struct fb_var_screeninfo var;

    static const uint32_t bars[] = {
        0xffffff, 0xffff00, 0x00ffff, 0x00ff00,
        0xff00ff, 0xff0000, 0x0000ff, 0x000000
    };

    int fd = open(path, O_RDWR);

    if (fd < 0) { perror(path); return 1; }
    if (ioctl(fd, FBIOGET_FSCREENINFO, &fix) ||
        ioctl(fd, FBIOGET_VSCREENINFO, &var)) {
        perror("framebuffer info"); close(fd); return 1;
    }

    if (var.xres != 800 || var.yres != 600 || var.bits_per_pixel != 24 ||
        var.red.offset != 16 || var.green.offset != 8 || var.blue.offset != 0 ||
        fix.line_length < 2400 || fix.smem_len < fix.line_length * 600) {
        fprintf(stderr, "Expected 800x600 packed RGB888 framebuffer\n");
        close(fd); return 1;
    }

    uint8_t *fb = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);

    if (fb == MAP_FAILED) { perror("mmap"); close(fd); return 1; }

    for (unsigned y = 0; y < 600; ++y)
        for (unsigned x = 0; x < 800; ++x) {
            uint32_t c = bars[x / 100];
            if (x == 0 || x == 799 || y == 0 || y == 599) c = 0xffffff;
            uint8_t *p = fb + y * fix.line_length + x * 3;
            p[0] = c; p[1] = c >> 8; p[2] = c >> 16;
        }

    munmap(fb, fix.smem_len);
    close(fd);
    puts("800x600: white yellow cyan green magenta red blue black; white 1px border");

    return 0;
}
