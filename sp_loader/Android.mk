LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := b2q-sp-loader
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := b2q-sp-loader.c
LOCAL_SHARED_LIBRARIES := libdl
LOCAL_CFLAGS += -Wall -Wextra -std=c11
include $(BUILD_EXECUTABLE)
