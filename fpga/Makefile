VIVADO ?= vivado
JOBS ?= 4
HDL_DIR := $(abspath ../hdl)
STAGE := $(abspath build/hdl)

export JOBS
export ADI_IGNORE_VERSION_CHECK := 1

.PHONY: all project ip video-ip hdmi-ip audio-ip

all: ip video-ip hdmi-ip audio-ip
	$(VIVADO) -mode batch -notrace -log build/vivado.log -journal build/vivado.jou -source system_project.tcl -tclargs build

project: ip video-ip hdmi-ip audio-ip
	$(VIVADO) -mode batch -notrace -log build/vivado.log -journal build/vivado.jou -source system_project.tcl -tclargs project

# Build ADI IP in a private staging tree, keeping the hdl submodule untouched.

ip:
	mkdir -p $(STAGE)/projects
	rsync -a $(HDL_DIR)/library $(HDL_DIR)/scripts $(HDL_DIR)/quiet.mk $(STAGE)/
	rsync -a $(HDL_DIR)/projects/scripts $(STAGE)/projects/
	@for lib in axi_ad9361 axi_dmac util_pack/util_cpack2 util_pack/util_upack2; do \
		ADI_HDL_DIR=$(STAGE) $(MAKE) -C $(STAGE)/library/$$lib xilinx VIVADO='$(VIVADO) -mode batch -source' || exit $$?; \
	done

video-ip:
	mkdir -p build/ip
	$(VIVADO) -mode batch -notrace -log build/video-package.log -journal build/video-package.jou -source ip/video_out/package_ip.tcl -tclargs build/ip/video_out

hdmi-ip:
	mkdir -p build/ip
	$(VIVADO) -mode batch -notrace -log build/hdmi-package.log -journal build/hdmi-package.jou -source ip/hdmi_tx/package_ip.tcl -tclargs build/ip/hdmi_tx

audio-ip:
	mkdir -p build/ip
	$(VIVADO) -mode batch -notrace -log build/audio-package.log -journal build/audio-package.jou -source ip/hdmi_audio/package_ip.tcl -tclargs build/ip/hdmi_audio
