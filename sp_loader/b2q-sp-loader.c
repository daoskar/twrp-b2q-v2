#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef int (*spcom_load_app_fn)(const char *ch_name, const char *file_path,
                                 uint32_t swap_size);
typedef bool (*spcom_is_app_loaded_fn)(const char *ch_name);
typedef bool (*spcom_link_up_fn)(void);

static void copy_symbol(void *handle, const char *name, void *out, size_t out_size) {
    void *sym = dlsym(handle, name);
    memset(out, 0, out_size);
    if (sym != NULL) {
        const size_t n = out_size < sizeof(sym) ? out_size : sizeof(sym);
        memcpy(out, &sym, n);
    }
}

static void sleep_ms(long milliseconds) {
    struct timespec req = {
        .tv_sec = milliseconds / 1000,
        .tv_nsec = (milliseconds % 1000) * 1000000L,
    };
    while (nanosleep(&req, &req) != 0 && errno == EINTR) {
    }
}

static bool channel_ready(spcom_is_app_loaded_fn is_loaded, const char *channel) {
    if (is_loaded != NULL && is_loaded(channel)) {
        return true;
    }

    char node[160];
    const int n = snprintf(node, sizeof(node), "/dev/%s", channel);
    return n > 0 && (size_t)n < sizeof(node) && access(node, F_OK) == 0;
}

int main(int argc, char **argv) {
    if (argc < 3 || argc > 4) {
        fprintf(stderr, "usage: %s <channel> <signed-app.sig> [swap_size]\n", argv[0]);
        return 64;
    }

    const char *channel = argv[1];
    const char *image = argv[2];
    uint32_t swap_size = 262144U;

    if (channel[0] == '\0' || strchr(channel, '/') != NULL) {
        fprintf(stderr, "invalid channel: %s\n", channel);
        return 65;
    }
    if (access(image, R_OK) != 0) {
        fprintf(stderr, "image not readable: %s: %s\n", image, strerror(errno));
        return 66;
    }

    if (argc == 4) {
        char *end = NULL;
        errno = 0;
        unsigned long value = strtoul(argv[3], &end, 0);
        if (errno != 0 || end == argv[3] || *end != '\0' || value > UINT32_MAX) {
            fprintf(stderr, "invalid swap_size: %s\n", argv[3]);
            return 67;
        }
        swap_size = (uint32_t)value;
    }

    void *handle = dlopen("/vendor/lib64/libspcom.so", RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        fprintf(stderr, "dlopen /vendor/lib64/libspcom.so failed: %s\n", dlerror());
        handle = dlopen("libspcom.so", RTLD_NOW | RTLD_LOCAL);
    }
    if (handle == NULL) {
        fprintf(stderr, "dlopen libspcom.so failed: %s\n", dlerror());
        return 68;
    }

    spcom_load_app_fn load_app = NULL;
    spcom_is_app_loaded_fn is_loaded = NULL;
    spcom_link_up_fn link_up = NULL;
    copy_symbol(handle, "spcom_load_app", &load_app, sizeof(load_app));
    copy_symbol(handle, "spcom_is_app_loaded", &is_loaded, sizeof(is_loaded));
    copy_symbol(handle, "spcom_is_sp_subsystem_link_up", &link_up, sizeof(link_up));

    if (load_app == NULL) {
        fprintf(stderr, "libspcom: missing spcom_load_app\n");
        dlclose(handle);
        return 69;
    }

    printf("[b2q-sp-loader] channel=%s image=%s swap=%u\n",
           channel, image, swap_size);
    if (link_up != NULL) {
        printf("[b2q-sp-loader] link_up=%d\n", link_up() ? 1 : 0);
    }

    if (channel_ready(is_loaded, channel)) {
        printf("[b2q-sp-loader] already loaded: %s\n", channel);
        dlclose(handle);
        return 0;
    }

    /*
     * Newer Qualcomm libspcom variants accept a third swap-size argument.
     * On AArch64, older two-argument implementations ignore the extra x2
     * argument, which lets this helper work with both ABI variants.
     */
    const int rc = load_app(channel, image, swap_size);
    printf("[b2q-sp-loader] spcom_load_app rc=%d\n", rc);
    fflush(stdout);

    for (int i = 0; i < 500; ++i) {
        if (channel_ready(is_loaded, channel)) {
            printf("[b2q-sp-loader] loaded: %s after %d ms\n", channel, i * 10);
            dlclose(handle);
            return 0;
        }
        sleep_ms(10);
    }

    fprintf(stderr,
            "[b2q-sp-loader] channel did not appear: %s (load rc=%d)\n",
            channel, rc);
    dlclose(handle);
    return rc != 0 ? 70 : 71;
}
