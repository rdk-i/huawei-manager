# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=huawei-manager
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Must_A_Kim
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/huawei-manager
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Huawei Modem Manager for OpenWrt
  DEPENDS:=+python3 +python3-pip +luci-base +luci-lib-jsonc
  PKGARCH:=all
endef

define Package/huawei-manager/description
  Comprehensive Huawei LTE modem management tool for OpenWrt.
  Features: Dashboard, IP hunting, band selection, APN, USSD, multi-device.
endef

define Package/huawei-manager/conffiles
/etc/config/huawei-manager
endef

define Build/Compile
endef

define Package/huawei-manager/install
	# Create directories
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/bin/huawei-manager
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/huawei-manager

	# Install config files
	$(INSTALL_CONF) ./files/etc/config/huawei-manager $(1)/etc/config/huawei-manager
	$(INSTALL_BIN) ./files/etc/init.d/huawei-manager $(1)/etc/init.d/huawei-manager

	# Install Python scripts
	$(INSTALL_BIN) ./files/usr/bin/huawei-manager/modem_api.py $(1)/usr/bin/huawei-manager/
	$(INSTALL_BIN) ./files/usr/bin/huawei-manager/device_info.py $(1)/usr/bin/huawei-manager/
	$(INSTALL_BIN) ./files/usr/bin/huawei-manager/reconnect_dialup.py $(1)/usr/bin/huawei-manager/
	$(INSTALL_BIN) ./files/usr/bin/huawei-manager/ip_agent_daemon.py $(1)/usr/bin/huawei-manager/
	$(INSTALL_BIN) ./files/usr/bin/huawei-manager/utils.py $(1)/usr/bin/huawei-manager/

	# Install LuCI controller and model
	$(INSTALL_DATA) ./luasrc/controller/huawei-manager.lua $(1)/usr/lib/lua/luci/controller/huawei-manager.lua
	$(INSTALL_DATA) ./luasrc/model/cbi/huawei-manager.lua $(1)/usr/lib/lua/luci/model/cbi/huawei-manager.lua

	# Install views
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/navigation.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/dashboard.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/ip_agent.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/network.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/logs.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/about.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/page_dashboard.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/page_ipagent.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/page_network.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/page_logs.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/page_about.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/page_sms.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/sms.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/config_header.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
	$(INSTALL_DATA) ./luasrc/view/huawei-manager/mobile_css.htm $(1)/usr/lib/lua/luci/view/huawei-manager/
endef

define Package/huawei-manager/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
    # Install huawei-lte-api
    pip3 install huawei-lte-api --quiet 2>/dev/null || true

    # Enable and start service
    /etc/init.d/huawei-manager enable
    /etc/init.d/huawei-manager start

    # Clear LuCI cache
    rm -rf /tmp/luci-modulecache /tmp/luci-indexcache 2>/dev/null || true
}
exit 0
endef

define Package/huawei-manager/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
    /etc/init.d/huawei-manager stop
    /etc/init.d/huawei-manager disable
}
exit 0
endef

$(eval $(call BuildPackage,huawei-manager))
