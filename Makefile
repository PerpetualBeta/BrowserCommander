# Browser Commander — keyboard-driven browser switcher.
#
# Release pipeline delegated to the shared `release.mk` from
# PerpetualBeta/jorvik-release. SPM project, embedded Sparkle,
# dual-ship (.zip + .pkg).

BUNDLE_NAME      := BrowserCommander
BUNDLE_TYPE      := app
PRODUCT_NAME     := BrowserCommander.app
BUNDLE_ID        := cc.jorviksoftware.BrowserCommander
BUILD_SYSTEM     := spm
SPM_PRODUCT      := BrowserCommander

PACKAGE_TYPE     := zip
ALSO_SHIP_PKG    := true
EMBEDDED_FRAMEWORKS := Sparkle
ENTITLEMENTS     := BrowserCommander.entitlements

include ../jorvik-release/release.mk
