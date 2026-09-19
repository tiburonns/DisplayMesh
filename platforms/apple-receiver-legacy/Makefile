ARCHS = armv7
TARGET = iphone:clang:9.3:9.0
INSTALL_TARGET_PROCESSES = DisplayMeshLegacy

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = DisplayMeshLegacy

DisplayMeshLegacy_FILES = \
	Sources/main.m \
	Sources/DMLegacyAppDelegate.m \
	Sources/DMLegacyFrameCodec.m \
	Sources/DMLegacyListener.m \
	Sources/DMLegacyTouchView.m \
	Sources/DMLegacyViewController.m
DisplayMeshLegacy_FRAMEWORKS = Foundation UIKit CoreGraphics ImageIO
DisplayMeshLegacy_CFLAGS = -fobjc-arc -Wno-error=deprecated-module-dot-map

include $(THEOS_MAKE_PATH)/application.mk
