ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = FreeFire

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AlphaFF
AlphaFF_FILES = Tweak.xm
AlphaFF_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AlphaFF_FRAMEWORKS = UIKit WebKit Foundation CoreGraphics
AlphaFF_LIBRARIES = 
AlphaFF_PRIVATE_FRAMEWORKS =

include $(THEOS_MAKE_PATH)/tweak.mk
