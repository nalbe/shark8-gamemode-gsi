/*
 * powercli - MTK power/performance hint driver for Blackview Shark 8 (mt6789, GSI).
 *
 * Talks to the running vendor.mediatek.hardware.mtkpower@1.0 service (pid of
 * /vendor/bin/hw/vendor.mediatek.hardware.mtkpower@1.0-service) through the
 * stock HIDL client wrapper /vendor/lib64/libpowerhalwrap_vendor.so.
 *
 * No daemon, no policy: this only feeds the vendor engine the triggers that the
 * stock MTK framework used to send (app state, named power hints).
 *
 * Build:
 *   clang --target=aarch64-linux-android21 --sysroot=<ndk>/toolchains/llvm/prebuilt/windows-x86_64/sysroot \
 *         -fPIE -pie -O2 -o powercli powercli.c -ldl
 *
 * Usage:
 *   powercli ver
 *   powercli hint <id> <ms>              # PowerHal_Wrap_mtkPowerHint
 *   powercli cus  <id> <ms>              # PowerHal_Wrap_mtkCusPowerHint
 *   powercli notify <pkg> <act> [pid] [state] [uid]
 *
 * notify arg order is the HIDL IMtkPower::notifyAppState order
 * (pack, act, pid, state, uid); state == 1 means "app resumed / foreground".
 */

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WRAP_LIB "/vendor/lib64/libpowerhalwrap_vendor.so"

typedef int (*fn_hint)(int, int);
typedef int (*fn_notify)(const char *, const char *, int, int, int);

static void *wrap;

static void *getsym(const char *name) {
    void *p = dlsym(wrap, name);
    if (p == NULL)
        fprintf(stderr, "powercli: missing symbol %s (%s)\n", name, dlerror());
    return p;
}

static void usage(void) {
    fprintf(stderr,
            "usage:\n"
            "  powercli ver\n"
            "  powercli hint <id> <ms>\n"
            "  powercli cus <id> <ms>\n"
            "  powercli notify <pkg> <act> [pid] [state] [uid]\n");
}

int main(int argc, char **argv) {
    if (argc < 2) {
        usage();
        return 2;
    }

    wrap = dlopen(WRAP_LIB, RTLD_NOW);
    if (wrap == NULL) {
        fprintf(stderr, "powercli: dlopen %s: %s\n", WRAP_LIB, dlerror());
        return 1;
    }

    if (strcmp(argv[1], "ver") == 0) {
        static const char *names[] = {
            "PowerHal_Wrap_mtkPowerHint",
            "PowerHal_Wrap_mtkCusPowerHint",
            "PowerHal_Wrap_notifyAppState",
            "PowerHal_Wrap_setSysInfo",
            "PowerHal_Wrap_querySysInfo",
            "PowerHal_Wrap_scnReg",
            "PowerHal_Wrap_scnConfig",
            "PowerHal_Wrap_scnEnable",
        };
        unsigned i;
        printf("wrap lib: %s\n", WRAP_LIB);
        for (i = 0; i < sizeof(names) / sizeof(names[0]); i++)
            printf("  %-32s %p\n", names[i], dlsym(wrap, names[i]));
        return 0;
    }

    if (strcmp(argv[1], "hint") == 0 || strcmp(argv[1], "cus") == 0) {
        int id, ms, rc;
        fn_hint f;
        if (argc < 4) {
            usage();
            return 2;
        }
        f = (fn_hint)getsym(strcmp(argv[1], "hint") == 0
                                ? "PowerHal_Wrap_mtkPowerHint"
                                : "PowerHal_Wrap_mtkCusPowerHint");
        if (f == NULL)
            return 1;
        id = atoi(argv[2]);
        ms = atoi(argv[3]);
        rc = f(id, ms);
        printf("%s id=%d ms=%d rc=%d\n", argv[1], id, ms, rc);
        return 0;
    }

    if (strcmp(argv[1], "notify") == 0) {
        const char *pkg, *act;
        int state, pid, uid, rc;
        fn_notify f;
        if (argc < 4) {
            usage();
            return 2;
        }
        f = (fn_notify)getsym("PowerHal_Wrap_notifyAppState");
        if (f == NULL)
            return 1;
        pkg = argv[2];
        act = argv[3];
        pid = argc > 4 ? atoi(argv[4]) : 0;
        state = argc > 5 ? atoi(argv[5]) : 1;
        uid = argc > 6 ? atoi(argv[6]) : 0;
        rc = f(pkg, act, pid, state, uid);
        printf("notify pkg=%s act=%s pid=%d state=%d uid=%d rc=%d\n",
               pkg, act, pid, state, uid, rc);
        return 0;
    }

    fprintf(stderr, "powercli: unknown command %s\n", argv[1]);
    usage();
    return 2;
}
