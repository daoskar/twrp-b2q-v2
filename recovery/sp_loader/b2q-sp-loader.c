#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

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

static void probe_node(const char *path) {
    struct stat st;
    if (lstat(path, &st) != 0) {
        printf("[b2q-sp-loader] node %s stat=missing errno=%d (%s)\n",
               path, errno, strerror(errno));
        return;
    }

    printf("[b2q-sp-loader] node %s mode=%#o type=%s major=%u minor=%u uid=%u gid=%u\n",
           path, (unsigned)(st.st_mode & 07777),
           S_ISCHR(st.st_mode) ? "char" :
           S_ISBLK(st.st_mode) ? "block" :
           S_ISREG(st.st_mode) ? "file" :
           S_ISLNK(st.st_mode) ? "symlink" : "other",
           S_ISCHR(st.st_mode) || S_ISBLK(st.st_mode) ? major(st.st_rdev) : 0,
           S_ISCHR(st.st_mode) || S_ISBLK(st.st_mode) ? minor(st.st_rdev) : 0,
           (unsigned)st.st_uid, (unsigned)st.st_gid);

    errno = 0;
    int fd = open(path, O_RDWR | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) {
        printf("[b2q-sp-loader] node %s open=fail errno=%d (%s)\n",
               path, errno, strerror(errno));
        return;
    }
    printf("[b2q-sp-loader] node %s open=ok fd=%d\n", path, fd);
    close(fd);
}

static void probe_nodes(void) {
    static const char *const nodes[] = {
        "/dev/sp_kernel",
        "/dev/sp_keymaster",
        "/dev/cryptoapp",
        "/dev/asym_cryptoapp",
        "/dev/qsee_ipc_irq_spss",
        "/dev/ion",
    };
    for (size_t i = 0; i < sizeof(nodes) / sizeof(nodes[0]); ++i)
        probe_node(nodes[i]);
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
    bool status_only = (argc == 2 && strcmp(argv[1], "--status") == 0);
    bool probe_only = (argc == 2 && strcmp(argv[1], "--probe-nodes") == 0);
    if (probe_only) {
        probe_nodes();
        return 0;
    }
    if (!status_only && (argc < 3 || argc > 4)) {
        fprintf(stderr, "usage: %s --status | --probe-nodes | <channel> <sig_path> [swap_size]\n", argv[0]);
        return 64;
    }

    const char *channel = status_only ? NULL : argv[1];
    const char *sig_path = status_only ? NULL : argv[2];
    int swap_size = (!status_only && argc == 4) ? atoi(argv[3]) : (256 * 1024);

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

    if (status_only) {
        printf("[b2q-sp-loader] status link_up=%d\n", is_link_up() ? 1 : 0);
        printf("[b2q-sp-loader] status asym_cryptoapp=%d\n", is_loaded("asym_cryptoapp") ? 1 : 0);
        printf("[b2q-sp-loader] status cryptoapp=%d\n", is_loaded("cryptoapp") ? 1 : 0);
        printf("[b2q-sp-loader] status sp_keymaster=%d\n", is_loaded("sp_keymaster") ? 1 : 0);
        dlclose(h);
        return 0;
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
        printf("[b2q-sp-loader] SPU-ready timed out; link is up, continuing with direct app load\n");
    }

    if (wait_app(is_loaded, channel, 1000) == 0) {
        printf("[b2q-sp-loader] %s appeared during stock SPU sequence\n", channel);
        dlclose(h);
        return 0;
    }

    if (ready_rc < 0)
        printf("[b2q-sp-loader] forcing %s load despite SPU-ready timeout\n", channel);
    else
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
