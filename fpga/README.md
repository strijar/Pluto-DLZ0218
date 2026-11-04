# DLZ0218: PS7 и AD9363 CMOS

Проект под `xc7z020clg400-2`, Vivado 2019.2: проверенная конфигурация PS7
и минимальный ADI радиотракт CMOS 1,8 В. **P8 оставлять на 1,8 В.**
`axi_ad9361` (2R2T), `util_cpack2`/`util_upack2`, RX/TX `axi_dmac`.
Без дополнительных FIR-интерполятора/дециматора Pluto и делителя тактовой
частоты LVDS из FMCOMMS2.

Исходники проекта находятся вне `hdl`. Makefile копирует необходимые исходники
библиотеки в `build/hdl`, собирает IP там и выставляет `ADI_IGNORE_VERSION_CHECK=1`.
HDL 2022_r2_p1 рассчитан на Vivado 2022.2; сборка этого проекта на 2019.2 проверена.

## Сборка

Из корня репозитория, после настройки окружения Vivado:

```sh
make -C fpga project  # проект, PS7 init и XSA без bitstream
make -C fpga          # также синтез, implementation и bitstream
```

Можно указать Vivado явно:

```sh
make -C fpga project VIVADO="$HOME/Xilinx/Vivado/2019.2/bin/vivado"
```

Скрипт заново создаёт проект из Tcl. Правки для воспроизводимой сборки нужно
вносить в исходные Tcl, а не только в GUI. Параллельность: `JOBS=4`.

Результаты:

- `build/dlz0218_sdr.xpr` — проект для GUI;
- `build/export/dlz0218_sdr.xsa` — аппаратная платформа;
- `build/export/ps7_init_gpl.c`, `ps7_init_gpl.h` — для интеграции в U-Boot SPL;
- `build/export/ps7_init.tcl` — для инициализации через инструменты Xilinx;
- `build/export/ps7_parameters.xml`, `ps7_init.html` — фактически сгенерированные настройки;
- `build/export/system.bit` — после полной сборки.

## Конфигурация

`ps7_config.tcl` содержит настройки платы. PS_CLK — 33.333333 МГц,
CPU — около 666.667 МГц. DDR — два D9SHD / MT41K256M16TW-107:P,
32 bit, 15 row / 10 column / 3 bank bits, геометрия 1 ГиБ.

Источник геометрии, внешнего VREF и начальных задержек — вариант A из
архива продавца `zynq7020_i2c_sd_lwip_bram.7z`,
`bram/bram_test.srcs/sources_1/bd/top/hw_handoff/top_bd.tcl`.
Старые сгенерированные init не копируются.

Используется Custom DDR при 533.333 МГц: CL/tRCD/tRP = 8 тактов,
CWL = 6, tRAS = 36 нс, tRC = 51 нс, tFAW = 45 нс.
С этим профилем уже загружены U-Boot и Linux с 1 ГиБ памяти; короткий
mtest в диапазоне `0x3d000000–0x3d004000` прошёл. Все три режима training включены.
BOARD_DELAY = 0.25 нс и DQS_TO_CLK_DELAY = 0 по всем четырём lanes — оценки
из варианта A, не измеренные длины трасс. Полный тест объёма DDR и длительная
проверка стабильности ещё не выполнены.

| Интерфейс | Настройка |
|---|---|
| QSPI | MIO1–6, single CS |
| UART1, консоль | TX48/RX49, 115200; адрес `0xe0001000`, clock 100 МГц |
| SD0 | MIO40–45, CD47, 50 МГц |
| USB0 | ULPI MIO28–39, reset46 |
| Ethernet GEM0 | RGMII MIO16–27, MDC52/MDIO53 |
| Ethernet reset | Внешний PS_PRO_B по схеме; reset GPIO не назначен |

Оба PS MIO банка настроены на 3.3 В по схеме. P8 = 1.8 В относится только
к PL и эту настройку не меняет. Vivado выдаёт **CRITICAL WARNING PS7-6**:
RGMII при 3.3 В не поддерживается, рекомендуются 1.8/2.5 В. Предупреждение
не подавляется. Ethernet проверен: DHCP и ping в U-Boot, сеть и обмен IIO
в Linux работают. Эти проверки не снимают ограничение из документации Xilinx.

## Загрузка через U-Boot

U-Boot SPL собирается в Buildroot с `ps7_init_gpl.c/.h`, экспортированными
из этого проекта. SPL выполняет инициализацию PS и DDR; сам битстрим
не меняет настройки DDR. После изменения PS7 нужно обновить init в
`system/br2_external/board/dlz0218/7020` и пересобрать SPL.

На SD используются отдельные `boot.bin` (SPL) и `u-boot.img`.
U-Boot загружает `system.bit` через `fpga loadb`, затем запускает Linux
через extlinux. При ошибке загрузки битстрима этот путь не запускает ядро.
Подробные команды — в [system/README.md](../system/README.md).

DDR определена как 1 ГиБ. Ethernet PHY работает по MDIO address 0 с
`rgmii-id`; reset GPIO не назначен, поскольку сброс подключён к PS_PRO_B.

## Радиотракт

`radio_bd.tcl` включает GP0, HP1/HP2, FCLK0=100 МГц, FCLK1=200 МГц,
SPI0 через EMIO и GPIO EMIO. DDR/MIO остаются из `ps7_config.tcl`.

| Узел | Адрес / IRQ |
|---|---|
| AD9361 ADC/control | 0x79020000 |
| AD9361 DDS | 0x79024000 |
| RX DMA, HP1 | 0x7c400000, GIC SPI 57 |
| TX DMA, HP2 | 0x7c420000, GIC SPI 56 |

GPIO Linux 54=RESET, 55=EN_AGC, 56=up_enable, 57=up_txnrx,
58=SW_RX, 59=SW_TX. Последние два в DTS заняты gpio-hog: SW_RX=1, SW_TX=0.
В этом состоянии проверены отдельный RF-вход RX1 и передача TX1 с захватом
на RX1 через внешний аттенюатор 30 дБ. Для этих тестов GPIO не переключались.

В `system_constr.xdc` распиновка сверена по страницам 3 и 7 схемы:
RX bits 0..11 = RX_D0_N/P ... RX_D5_N/P;
TX bits 0..11 = TX_D5_P/N ... TX_D0_P/N.
FB_CLK_N и TX_FRAME_N удерживаются в нуле в CMOS; DATA_CLK_N/RX_FRAME_N
не используются. CTRL_IN[3:0]=0. SPI DI/DO указаны относительно AD9363.

CMOS использует DDR, полные 12 бит и swap-ports (P0=TX, P1=RX).
Начальная частота выборок 30,72 Мвыб/с, интерфейс 61,44 МГц в 2R2T.
Опорный генератор радиочипа — 40 МГц. Драйвер выполняет RX/TX digital tuning.
Период RX clock задан в XDC; внешние задержки дорожек не измерены, поэтому
успех implementation не доказывает запас тайминга интерфейса на реальной плате.

После генерации проекта обязательно обновить `ps7_init_gpl.c/.h` в
`system/br2_external/board/dlz0218/7020` и пересобрать U-Boot SPL:
старый PS-only init не включает нужные SPI/FCLK. Инструкция —
[system/README.md](../system/README.md).

## Проверка сборки 2026-11-04

Vivado 2019.2: synthesis, placement, routing и write_bitstream завершены.
Routed WNS +1,706 нс, WHS +0,050 нс, DRC 0 ошибок.
Отчёт отмечает 13 входов без input delay и 16 выходов без output delay:
цифры slack относятся к ограниченным внутренним путям, а не к полной
проверке внешнего CMOS-интерфейса.

## Аппаратные проверки 2026-11-04

- U-Boot и ADI Linux загружаются с SD; видна память 1 ГиБ, Ethernet работает.
- AD9363 успешно инициализируется, RX/TX digital tuning завершён без ошибок.
- Локальный и сетевой захват RX через DMA проверены: 65536 отсчётов по
  четырём 16-битным компонентам I/Q дают 524288 байт.
- На RX1 принят внешний тон 868 МГц с заданным на генераторе уровнем −96 dBm.
  При RX LO 867 МГц пик наблюдался около 868,002 МГц, на 39,6 дБ выше
  медианного шума в FFT-бине 937,5 Гц. Это не широкополосный SNR и не
  калиброванное измерение мощности на RF-входе.
- При соединении TX1 с RX1 через аттенюатор 30 дБ приняты DDS-тоны
  868 и 869 МГц. Изменение ослабления TX с 40 до 50 дБ уменьшило уровень
  пика на 10,18 дБ при фиксированном усилении RX1 45 дБ.
- Циклический IQ-тон 868,5 МГц передан через TX DMA и принят на RX1.
  Насыщения RX в этих тестах не было.

## Видеовыход 800×600

`video_bd.tcl` добавляет видео к SDR-проекту:
DDR → PS HP0 → AXI VDMA MM2S → AXIS FIFO → `axi_video_to_rgb` → `rgb2hdmi` (Digilent PHY) → HDMI-разъём. Адрес регистров VDMA — `0x43000000`, окно 64 КиБ.
HP1/HP2 и адреса радиотракта сохранены. VDMA использует AXI memory 64 bit
при 100 МГц и AXIS RGB888 при 40 МГц; пересечение доменов выполняет VDMA.
FIFO глубиной 2048 пикселей работает в домене 40 МГц.

Режим фиксирован: 800×600, H=800/40/128/88, V=600/1/4/23,
положительные HSYNC/VSYNC, 40 МГц pixel clock. Clock Wizard получает
FCLK0=100 МГц и создаёт согласованные 40/200 МГц для OSERDES DDR 10:1.
Добавлены HDMI Data Islands, InfoFrames и тестовый тон 1 кГц из PL;
подробнее — [HDMI IP](ip/hdmi_tx/README.md).

VHDL `video_timing_gen` входит в упакованный `axi_video_to_rgb`.
`make -C fpga video-ip` создаёт `build/ip/video_out/component.xml` и
сопутствующие файлы; цели `project` и полной сборки делают это автоматически.
Для импорта в другой BD добавить репозитории `build/ip`, `vendor` и
`ip/interfaces`. В качестве полного примера подключения служат
`system_bd.tcl` и `video_bd.tcl`.

Адаптер ждёт SOF и начала растра, проверяет EOL на каждом 800-м пикселе.
В blanking действует backpressure. При underflow или ошибке маркеров
остаток кадра чёрный, затем адаптер ищет следующий SOF. HSYNC/VSYNC/DE
продолжают идти без остановки. Выход `fault` — sticky-индикатор для ILA,
в текущем BD программно не читается. RGB и синхросигналы регистрируются
вместе с координатами растра. `rgb2hdmi` принимает обычное RGB[23:0];
framebuffer в памяти содержит байты B,G,R.

```sh
make -C fpga test
make -C fpga VIVADO=~/Xilinx/Vivado/2019.2/bin/vivado
```

Физическое изображение проверяется отдельно после загрузки новой системы:

```sh
cat /sys/class/graphics/fb0/virtual_size
hdmi-test
```

Ожидается `800,600`, восемь полос (белая, жёлтая, голубая, зелёная,
пурпурная, красная, синяя, чёрная) и белая рамка толщиной один пиксель.
Проверить видимость всех четырёх краёв и отсутствие сдвигов при одновременной
работе SDR RX/TX. Один framebuffer допускает tearing при обновлении GUI.

### Проверка сборки видео 2026-11-04

GHDL: восемь кадров, проверки пройдены. Vivado 2019.2: BD, synthesis,
implementation и bitstream собраны. Routed WNS +2,284 нс, WHS +0,043 нс;
неограниченных внутренних endpoints нет. Общие ресурсы SDR+video:
13209 LUT, 20518 FF, 8,5 BRAM tiles, 28 DSP.
DRC: 0 ошибок, 2 предупреждения REQP-1839/1840 о reset внутри стандартного
VDMA и 26 advisory. Предупреждения не подавлены. Остаются 13 входов и
20 выходов без external delay; внутренний timing не заменяет проверку
радиоинтерфейса и HDMI на плате. Существующее PS7-предупреждение о RGMII
3,3 В также сохраняется.

Buildroot: ядро 6.1.70-adi-dlz0218, DTB, U-Boot/SPL, hdmi-test и sdcard.img
собраны. Пользователь подтвердил на плате загрузочную консоль и полосы
`hdmi-test`; проверка HDMI-аудио относится к следующему этапу.

### HDMI-аудио: ALSA / PL330

Текущий BD использует `axi_hdmi_audio` по адресу `0x43c00000`, PS DMA0_REQ/
DMA0_ACK и GP0. Радио DMA и HP-порты не изменены. Буфер на 256 стереопар
передаёт PCM из домена 100 МГц в домен pixel clock 40 МГц. Частота чтения
48 кГц; при остановке или пустом буфере передаётся тишина. В `rgb2hdmi`
тестовый источник сохранён за generic `TEST_TONE`, по умолчанию false.

```sh
make -C fpga test-audio
make -C fpga VIVADO=~/Xilinx/Vivado/2019.2/bin/vivado
```

Симуляция проверяет независимые AW/W, AXI backpressure, PL330 SINGLE/FLUSH,
заполнение и оборот FIFO, порядок PCM16 L/R, тишину, сброс и повторный запуск.
HDMI-пакетизатор не изменён относительно проверенного этапа с тоном.
Подробности ABI и CDC — [COMPATIBILITY.md](ip/hdmi_audio/COMPATIBILITY.md);
команды проверки на плате — [system/README.md](../system/README.md#hdmi-alsa).
Новый тракт ALSA пока проверен сборкой и симуляцией, но не на плате.
Локальная копия проверенного битстрима с автономным тоном:
`build/export/system-hdmi-tone.bit`.

Итоговая ALSA-сборка 2026-11-04: WNS +1,110 нс, WHS +0,016 нс;
13656 LUT, 20933 FF, 9 BRAM, 28 DSP. DRC без ошибок, два прежних
предупреждения VDMA. Ограничения Gray-переходов выполнены; замечания CDC
для намеренного объединения асинхронных сбросов разобраны в COMPATIBILITY.md.
Полный `system/output_system/images/sdcard.img` пересобран с этим битстримом.
