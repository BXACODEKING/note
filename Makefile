##########################################
#            hongdian app                #
##########################################
#define hardware&software platform
HD_PLATFORM ?= $(COMPILE_TYPE)

ifeq ($(HD_PLATFORM),)
error:
	echo"must setup HD_PLATFORM"
endif

HD_TOPDIR = $(shell pwd)
include $(HD_TOPDIR)/../../../rules.mk
include config.mk

COMPILE_PATCH=yes
COMPILE_VERSION ?=0.0.1
COMPILE_TIME ?= $(shell date +%y%m%d-%H%M%S)
PATCH_DATE ?= `date +%y%m%d`

#补丁版本号相同
ifeq ($(COMPILE_PATCH), yes)
COMPILE_PATCH_VERSION=$(COMPILE_VERSION).1_$(PATCH_DATE)
CFLAGS += -DBIN_VERSION=\\\"$(COMPILE_PATCH_VERSION)\\\"
endif

BDIR = $(HD_TOPDIR)/../../../build_dir/target-arm_cortex-a7_uClibc-1.0.14_eabi
CURL_DIR = $(BDIR)/curl-7.40.0/ipkg-install
CURL_INC_DIR = $(CURL_DIR)/usr/include
CURL_LIB_DIR = $(CURL_DIR)/usr/lib
UCI_LIB_DIR =  $(BDIR)/uci-2015-08-27.1/ipkg-install/usr/lib
OPENSSL_DIR = $(BDIR)/openssl-1.0.2h/ipkg-install
OPENSSL_INC_DIR = $(OPENSSL_DIR)/usr/include
OPENSSL_LIB_DIR = $(OPENSSL_DIR)/usr/lib
PCAP_DIR = $(BDIR)/libpcap-1.5.3/ipkg-install/
PCAP_INC_DIR = $(PCAP_DIR)/usr/include
PCAP_LIB_DIR = $(PCAP_DIR)/usr/lib
HDAPPDIR:=$(HD_TOPDIR)/app
DESTROOT ?= $(HD_TOPDIR)/build
DESTBIN ?= $(HD_TOPDIR)/build/usr/sbin
DESTETC ?= $(HD_TOPDIR)/build/etc
DESTLIB ?= $(HD_TOPDIR)/build/lib

FLAGFILE =  $(HD_TOPDIR)/../../../patch_static_flag

# CFLAGS += -DHD_$(HD_PLATFORM) -DCOMPILE_VERSION=\\\"$(COMPILE_VERSION)\\\" -DCOMPILE_TIME=\\\"$(COMPILE_TIME)\\\"
CFLAGS += $(TARGET_CPPFLAGS) -I$(HD_TOPDIR)/include -I$(HD_TOPDIR)/include/hd -I$(HD_TOPDIR)/include/platform -I$(CURL_INC_DIR) -I$(OPENSSL_INC_DIR) -I$(HD_TOPDIR)/include/user-open -I$(HD_TOPDIR)/include/hd_cci

exist = $(shell if [ -f $(FLAGFILE) ]; then echo "exist"; else echo "notexist"; fi;)

ifeq (${exist},exist)
LDFLAGS += $(TARGET_LDFLAGS) $(HD_TOPDIR)/lib/platform/libplat.a $(HD_TOPDIR)/lib/hd/libhdg3.a -L$(OPENSSL_LIB_DIR) -L$(CURL_LIB_DIR)  -L$(UCI_LIB_DIR) -L$(HD_TOPDIR)/lib/user-open $(HD_TOPDIR)/lib/hd_cci/libhdcci.a -lcrypt -lssl -lcurl  -luci -luser
else
LDFLAGS += $(TARGET_LDFLAGS) -L$(HD_TOPDIR)/lib/hd -L$(HD_TOPDIR)/lib/platform -L$(OPENSSL_LIB_DIR) -L$(CURL_LIB_DIR)  -L$(UCI_LIB_DIR) -L$(HD_TOPDIR)/lib/user-open -L$(HD_TOPDIR)/lib/hd_cci -lhdg3 -lplat -lcrypt -lssl -lcurl  -luci -luser -lhdcci
endif

CFLAGS += -O2

HD_STRONGSWAN=0
HD_OPENSWAN=1
ifdef CONFIG_PACKAGE_strongswan
HD_STRONGSWAN=1
HD_OPENSWAN=0
endif
export HD_PLATFORM SOFT_PLATFORM COMPILE_VERSION COMPILE_TIME COMPILE_PATCH PATCH_DATE HD_STRONGSWAN HD_OPENSWAN
export CROSS_COMPILE CC AR AS LD NM RANLIB STRIP HOST
export LDFLAGS CFLAGS 
export HDAPPDIR DESTROOT DESTBIN DESTETC DESTLIB
export PCAP_INC_DIR PCAP_LIB_DIR FLAGFILE
export INSTROOT = $(BDIR)/root-ipq/

subdir = defconfig binary lib cbb app
all: user

user:
	echo $(LDFLAGS)
	for i in $(subdir) ; do \
		if [ "$$i" == "app" ];then \
			CFLAGS='$(CFLAGS) -DHD_$(HD_PLATFORM) -DCOMPILE_VERSION=\\\"$(COMPILE_VERSION)\\\" -DCOMPILE_TIME=\\\"$(COMPILE_TIME)\\\" ' $(MAKE) -C $$i  || exit $?; \
		else \
			CFLAGS='$(CFLAGS) -DHD_$(HD_PLATFORM) -DCOMPILE_VERSION=\"$(COMPILE_VERSION)\" -DCOMPILE_TIME=\"$(COMPILE_TIME)\" ' $(MAKE) -C $$i  || exit $?; \
		fi \
	done

install:
	for i in $(subdir) ; do \
		$(MAKE) -C $$i install || exit $? ; \
	done

clean:
	for i in $(subdir) ; do \
		echo "make -C $i clean"; \
		$(MAKE) -C $$i clean || exit $? ; \
	done

.PHONY: all clean user install
