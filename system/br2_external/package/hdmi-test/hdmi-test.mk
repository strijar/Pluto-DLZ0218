HDMI_TEST_VERSION = 1
HDMI_TEST_SITE = $(BR2_EXTERNAL_SYSTEM_PATH)/package/hdmi-test/src
HDMI_TEST_SITE_METHOD = local
HDMI_TEST_LICENSE = MIT
HDMI_TEST_LICENSE_FILES = LICENSE

define HDMI_TEST_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -Wall -Wextra $(@D)/hdmi-test.c $(TARGET_LDFLAGS) -o $(@D)/hdmi-test
endef

define HDMI_TEST_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/hdmi-test $(TARGET_DIR)/usr/bin/hdmi-test
endef

$(eval $(generic-package))
