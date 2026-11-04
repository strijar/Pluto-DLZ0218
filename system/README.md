# DLZ0218 Linux

Ядро: ADI Linux, ветка `2023_R2`, Linux 6.1.70, закреплённый commit
`86d61468a7856e952c7ca237f798d86d6abd2e27`:
https://github.com/analogdevicesinc/linux/tree/86d61468a7856e952c7ca237f798d86d6abd2e27

Используется ADI `zynq_xcomm_adv7511_defconfig` с фрагментом
`br2_external/board/dlz0218/linux/adi-ps7.fragment`. Он включает встроенные
драйверы UART, SD, ext4, MACB и Realtek PHY и отключает встраивание большого
набора firmware из ADI defconfig. Device Tree описывает PS7, AD9363 CMOS,
ADI ADC/DDS и два DMA.

## Сборка

Из корня репозитория, при первоначальной настройке либо изменении defconfig:

```sh
env -u LD_LIBRARY_PATH make -C system/buildroot-2024.02 \
    BR2_EXTERNAL=../br2_external O=../output_system dlz0218_defconfig
```

Эта команда заменяет текущую конфигурацию Buildroot сохранённым defconfig.
Не запускайте её поверх несохранённых изменений menuconfig.

Полная сборка из корня репозитория:

```sh
make -C fpga VIVADO="$HOME/Xilinx/Vivado/2019.2/bin/vivado"
cp fpga/build/export/ps7_init_gpl.c fpga/build/export/ps7_init_gpl.h \
    system/br2_external/board/dlz0218/7020/
env -u LD_LIBRARY_PATH make -C system/output_system
```

Для существующего каталога сборки после изменения соответствующих исходников:

```sh
# После обновления PS7 init или исходников U-Boot:
env -u LD_LIBRARY_PATH make -C system/output_system uboot-rebuild
# После изменения DTS:
env -u LD_LIBRARY_PATH make -C system/output_system linux-rebuild
# После изменения фрагмента конфигурации ядра:
env -u LD_LIBRARY_PATH make -C system/output_system linux-reconfigure
# После изменения boot-env.txt:
env -u LD_LIBRARY_PATH make -C system/output_system host-uboot-tools-rebuild
# Сформировать rootfs и SD-образ:
env -u LD_LIBRARY_PATH make -C system/output_system
```

При изменении параметров уже собранного пакета нужна его переконфигурация,
например `libiio-reconfigure`. При удалении пакетов нужна чистая сборка:
Buildroot не удаляет их старые файлы из target автоматически.
`make -C system/output_system clean` удаляет результаты сборки, включая образы;
нужные образы следует заранее сохранить.

Чистая сборка использует toolchain с headers 6.1 из выбранного ADI kernel.
`rootfs-overlay` подключён из `br2_external/board/dlz0218/linux/rootfs-overlay`:
он заменяет `/etc/inittab` и `/etc/issue`, а также содержит
`/etc/ssh/sshd_config`. Последний относится к OpenSSH и не управляет Dropbear.
Overlay задаёт getty на `console`, `tty1` и `tty2`; UART-консоль ядра остаётся
`ttyPS0`. Эти изменения overlay и добавление `mc` появились после исходной
проверки минимального rootfs; их следует учитывать при следующей сборке.

## Загрузка

В `output_system/images` после сборки ядра находятся `uImage` и `dlz0218.dtb`.
Полная сборка дополнительно создаёт rootfs и `sdcard.img`:

- раздел 1 FAT, bootable: `boot.bin` (SPL), `u-boot.img`, `uImage`,
  `dlz0218.dtb`, `system.bit`, `extlinux/extlinux.conf`, `uboot-env.bin`;
- раздел 2 ext4: корневая файловая система;
- раздел 3 FAT: DATA (сохранён из исходной конфигурации).

`system.bit` загружается командой `fpga loadb` перед extlinux/boot script.
При ошибке загрузки PL этот путь не запускает Linux с радиоустройствами.
Post-build берёт битстрим из `fpga/build/export/system.bit`; для другого
пути можно передать `DLZ0218_BITSTREAM`.

На рабочей SD замените **boot.bin, u-boot.img, uImage, dlz0218.dtb,
system.bit, uboot-env.bin и extlinux/extlinux.conf**, если обновляете всю
аппаратно-программную сборку. При переходе с PS-only проекта новый SPL
обязателен: он включает SPI0 и FCLK0/FCLK1 для радиотракта.
`uboot-env.bin` заменяет сохранённые настройки; перед заменой сохраните свой файл,
если в нём есть нужные IP/MAC/другие изменения.

Для ручного запуска с новым SPL:

```text
load mmc 0:1 0x04000000 system.bit
fpga loadb 0 0x04000000 ${filesize}
# Продолжать только после успешной конфигурации FPGA.
load mmc 0:1 0x02000000 uImage
load mmc 0:1 0x01f00000 dlz0218.dtb
setenv bootargs console=ttyPS0,115200 earlycon root=/dev/mmcblk0p2 rootfstype=ext4 rw rootwait
bootm 0x02000000 - 0x01f00000
```

UART физически UART1 (MIO48/49), но alias `serial0` даёт Linux имя `ttyPS0`.
Ethernet — GEM0, RTL8211E по MDIO address 0, `rgmii-id`, как в проверенном
U-Boot. Сброс PHY подключён к PS_PRO_B, фиктивного reset GPIO нет.
USB и QSPI в Linux пока не включены; их настройку добавим отдельно.

PS7 уже проверен на плате: Linux загружается, Ethernet работает, видна память 1 ГиБ.
AD9363, digital tuning, локальный/сетевой RX и TX через DDS/DMA также проверены.
Команды для диагностики после загрузки:

```sh
dmesg | grep -Ei 'ad936|axi|dma|spi|error|fail'
for d in /sys/bus/iio/devices/iio:device*; do echo "$d: $(cat "$d/name")"; done
```

Ожидаются `ad9361-phy`, `cf-ad9361-lpc`, `cf-ad9361-dds-core-lpc`.
Эти устройства успешно обнаружены. RF-переключатели первого канала
заданы через gpio-hog: SW_RX=1, SW_TX=0. В этом состоянии проверены приём
на RX1 и тест TX1 → внешний аттенюатор 30 дБ → RX1.

`adi-ad9361-defaults.dtsi` — радионастройки из `adi-fmcomms2.dtsi` закреплённого
ADI Linux, без FMC I2C-периферии. Параметры платы и CMOS находятся в
`dlz0218-radio.dtsi`. RESET имеет GPIO_ACTIVE_HIGH намеренно: этот драйвер
сам выставляет уровни 0 → 1; инверсия флага оставила бы чип в сбросе.

## Rootfs с IIO-сервером

Минимальный `dlz0218_defconfig` включает libiio 0.25, `iiod`, утилиты
`iio_info`/`iio_attr`/`iio_readdev`/`iio_writedev`, libaio, SSH Dropbear,
`ethtool`, libgpiod с утилитами и BusyBox (включая `timeout`, `ip`, `ping`,
`netstat`, DHCP). Сохранён eudev для создания устройств.
Штатный `/etc/init.d/S99iiod` запускает сервер при загрузке с `-D`
(демультиплексирование каналов на сервере). Ethernet получает адрес по DHCP.

На плате:

```sh
ip addr show eth0
/etc/init.d/S99iiod restart
netstat -lnt | grep ':30431'
iio_info -u local:
```

Последний проверенный адрес платы — `192.168.1.232` (DHCP, может измениться).
На компьютере с libiio:

```sh
iio_info -u ip:192.168.1.232
iio_readdev -u ip:192.168.1.232 -b 4096 -s 65536 cf-ad9361-lpc \
    voltage0 voltage1 voltage2 voltage3 > rx.bin
wc -c rx.bin
```

Для четырёх 16-битных I/Q-компонент ожидается 524288 байт.
Приём такого объёма проверен и локально, и по Ethernet через `iiod`.
Клиент libiio 0.26 успешно работает с сервером 0.25.

После полной сборки `output_system/images/sdcard.img` содержит все три раздела.
Если загрузочный раздел уже обновлён и работает, можно заменить только второй
раздел образом `rootfs.ext4`, оставив BOOT/DATA прежними. Это заменит содержимое
старого rootfs. Размер раздела должен быть не меньше 1 ГиБ. Сервисы SSH и iiod
запускаются автоматически; вручную переносить библиотеки на старый rootfs не нужно.

Проверка минимальной сборки 2026-11-04: полная сборка Buildroot завершена;
`e2fsck -fn rootfs.ext4` прошёл без ошибок. ARM `iiod --version` и
`iio_info --version` проверены через QEMU (0.25, backends local/xml/ip).
В ext4 присутствуют исполняемый iiod и `/etc/init.d/S99iiod`.
Этот rootfs загружен на физической плате, сервер доступен по Ethernet,
сетевой захват RX и передача IQ через TX DMA проверены.

## Результаты проверки радиотракта

При 30,72 Мвыб/с на RX1 принят внешний сигнал 868 МГц с заданным на
генераторе уровнем −96 dBm. При RX LO 867 МГц пик оказался около
868,002 МГц. Превышение над шумом в FFT-бине 937,5 Гц — около 39,6 дБ;
абсолютная мощность на RF-входе не калибровалась.

С TX1, соединённым с RX1 через аттенюатор 30 дБ, проверены DDS-тоны
868/869 МГц и циклический IQ-тон 868,5 МГц через TX DMA.
Дополнительные 10 дБ ослабления TX дали снижение принятого уровня на 10,18 дБ.
Длительная непрерывная передача без потерь пока не проверена.
