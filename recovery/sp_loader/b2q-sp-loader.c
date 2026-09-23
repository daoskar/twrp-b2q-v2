#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef bool (*spcom_is_app_loaded_fn)(const char *);
typedef bool (*spcom_is_sp_subsystem_link_up_fn)(void);
typedef int (*spcom_wait_for_spu_ready_fn)(uint32_t);
typedef int (*spcom_load_app_fn)(const char *, const char *, size_t);

static int wait_link(spcom_is_sp_subsystem_link_up_fn is_link_up, int timeout_ms) {
    for (int elapsed = 0; elapsed < timeout_ms; elapsed += 50) {
        if (is_link_up())
            return 0;
        usleep(50 * 1000);
    }
    return -1;
}

static int wait_app(spcom_is_app_loaded_fn is_loaded, const char *name, int timeout_ms) {
    for (int elapsed = 0; elapsed < timeout_ms; elapsed += 50) {
        if (is_loaded(name))
            return 0;
        usleep(50 * 1000);
    }
    return -1;
}

int main(int argc, char **argv) {
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "usage: %s <channel> <sig_path> [swap_size]\n", argv[0]);
        return 64;
    }

    const char *channel = argv[1];
    const char *sig_path = argv[2];
    int swap_size = (argc == 4) ? atoi(argv[3]) : (256 * 1024);

    void *h = dlopen("/vendor/lib64/libspcom.so", RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        fprintf(stderr, "[b2q-sp-loader] dlopen libspcom failed: %s\n", dlerror());
        return 65;
    }

    spcom_is_app_loaded_fn is_loaded =
        (spcom_is_app_loaded_fn)dlsym(h, "spcom_is_app_loaded");
    spcom_is_sp_subsystem_link_up_fn is_link_up =
        (spcom_is_sp_subsystem_link_up_fn)dlsym(h, "spcom_is_sp_subsystem_link_up");
    spcom_wait_for_spu_ready_fn wait_spu_ready =
        (spcom_wait_for_spu_ready_fn)dlsym(h, "spcom_wait_for_spu_ready");
    spcom_load_app_fn load_app =
        (spcom_load_app_fn)dlsym(h, "spcom_load_app");

    if (!is_loaded || !is_link_up || !wait_spu_ready || !load_app) {
        fprintf(stderr, "[b2q-sp-loader] missing libspcom symbols: loaded=%p link=%p spu_ready=%p load=%p\n",
                (void *)is_loaded, (void *)is_link_up, (void *)wait_spu_ready, (void *)load_app);
        dlclose(h);
        return 66;
    }

    printf("[b2q-sp-loader] channel=%s sig=%s swap=%d\n",
           channel, sig_path, swap_size);

    if (wait_link(is_link_up, 15000) != 0) {
        fprintf(stderr, "[b2q-sp-loader] SP link did not become ready\n");
        dlclose(h);
        return 67;
    }
    printf("[b2q-sp-loader] SP link ready\n");

    if (wait_app(is_loaded, channel, 1000) == 0) {
        printf("[b2q-sp-loader] %s already loaded before SPU-ready wait\n", channel);
        dlclose(h);
        return 0;
    }

    printf("[b2q-sp-loader] waiting for stock spdaemon SPU-ready handshake\n");
    int ready_rc = wait_spu_ready(90);
    printf("[b2q-sp-loader] spcom_wait_for_spu_ready rc=%d", ready_rc);
    if (ready_rc < 0 && -ready_rc > 0 && -ready_rc < 256)
        printf(" (%s)", strerror(-ready_rc));
    printf("\n");
    if (ready_rc < 0) {
        dlclose(h);
        return 70;
    }

    if (wait_app(is_loaded, channel, 1000) == 0) {
        printf("[b2q-sp-loader] %s appeared during stock SPU sequence\n", channel);
        dlclose(h);
        return 0;
    }

    printf("[b2q-sp-loader] stock SPU sequence completed without %s; forcing app load\n", channel);
    int rc = load_app(channel, sig_path, (size_t)swap_size);
    printf("[b2q-sp-loader] spcom_load_app(%s) rc=%d", channel, rc);
    if (rc < 0 && -rc > 0 && -rc < 256)
        printf(" (%s)", strerror(-rc));
    printf("\n");
    if (rc < 0) {
        if (wait_app(is_loaded, channel, 5000) == 0) {
            printf("[b2q-sp-loader] %s appeared after load error; treating as ready\n", channel);
            dlclose(h);
            return 0;
        }
        dlclose(h);
        return 68;
    }

    if (wait_app(is_loaded, channel, 15000) != 0) {
        fprintf(stderr, "[b2q-sp-loader] %s did not become loaded\n", channel);
        dlclose(h);
        return 69;
    }

    printf("[b2q-sp-loader] %s loaded\n", channel);
    dlclose(h);
    return 0;
}
