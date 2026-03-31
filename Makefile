THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:14.5:13.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YOYBypass
YOYBypass_FILES = Tweak.x
YOYBypass_CFLAGS = -fobjc-arc -Wall
YOYBypass_FRAMEWORKS = Foundation
YOYBypass_LIBRARIES = substrate

include $(THEOS)/makefiles/tweak.mk
