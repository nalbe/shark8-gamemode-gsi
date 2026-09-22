/* focuslog.c - minimal foreground-focus event reader for the Shark 8 GSI.
 *
 * logcat is a full log formatter: it reads the whole events buffer, decodes
 * every tag, formats text for all of it and only then applies -s filters. For
 * the gamemode trigger we need exactly one thing out of that buffer - the
 * WindowManager input_focus events - so this reads the logd socket through
 * liblog's reader API directly, looks for the two phrases that only those
 * events contain, and prints one short line per focus change:
 *
 *   entering <pkg>/<activity>
 *   leaving  <pkg>/<activity>
 *
 * No fork, no exec, no text formatting, no FIFO needed on our side; RSS is a
 * couple hundred KB. The reader starts at the current time
 * (android_logger_list_alloc_time), so the pre-existing buffer - which on this
 * device is mostly auditd avc spam - is never replayed.
 *
 * Build: see scripts/build.ps1 (aarch64, API 21, links -ldl only).
 */

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define LOG_ID_EVENTS 2
#define LOGGER_ENTRY_MAX_PAYLOAD 4068

/* struct logger_entry_v4 as served by liblog's reader API */
struct log_msg {
    uint16_t len;
    uint16_t hdr_size;
    int32_t pid;
    uint32_t tid;
    uint32_t sec;
    uint32_t nsec;
    uint32_t lid;
    uint32_t uid;
    unsigned char buf[LOGGER_ENTRY_MAX_PAYLOAD];
};

/* struct log_time, passed by value */
struct log_time {
    uint32_t tv_sec;
    uint32_t tv_nsec;
};

typedef void *(*fn_alloc_time)(int, struct log_time, int);
typedef void *(*fn_open)(void *, int);
typedef int (*fn_read)(void *, struct log_msg *);
typedef void (*fn_free)(void *);

int main(int argc, char **argv)
{
    int verbose = 0;
    int raw = 0;
    if (argc > 1 && !strcmp(argv[1], "-v")) {
        verbose = 1;
    } else if (argc > 1 && !strcmp(argv[1], "-x")) {
        raw = 1;                /* dump the payload of every focus event */
    }

    void *lib = dlopen("liblog.so", RTLD_NOW);
    if (!lib) {
        fprintf(stderr, "focuslog: dlopen liblog.so: %s\n", dlerror());
        return 1;
    }
    fn_alloc_time p_alloc = (fn_alloc_time)dlsym(lib, "android_logger_list_alloc_time");
    fn_open p_open = (fn_open)dlsym(lib, "android_logger_open");
    fn_read p_read = (fn_read)dlsym(lib, "android_logger_list_read");
    fn_free p_free = (fn_free)dlsym(lib, "android_logger_list_free");
    if (!p_alloc || !p_open || !p_read || !p_free) {
        fprintf(stderr, "focuslog: liblog reader API missing\n");
        return 1;
    }

    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    struct log_time start = { (uint32_t)now.tv_sec, (uint32_t)now.tv_nsec };

    void *list = p_alloc(0 /* blocking */, start, 0);
    if (!list) {
        fprintf(stderr, "focuslog: cannot open log reader\n");
        return 1;
    }
    if (!p_open(list, LOG_ID_EVENTS)) {
        fprintf(stderr, "focuslog: cannot open events buffer\n");
        p_free(list);
        return 1;
    }

    /* line buffered: the caller reads this through a pipe/FIFO */
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (verbose) {
        fprintf(stderr, "focuslog: streaming events from %u.%09u\n",
                start.tv_sec, start.tv_nsec);
    }

    static struct log_msg msg;
    for (;;) {
        int n = p_read(list, &msg);
        if (n == 0) {
            continue;               /* no data yet */
        }
        if (n < 0) {
            fprintf(stderr, "focuslog: read failed (%d)\n", n);
            break;
        }
        uint16_t len = msg.len;
        if (len == 0 || len > LOGGER_ENTRY_MAX_PAYLOAD) {
            continue;
        }
        /* NUL-terminate a copy of the payload so the scan is bounded */
        static char payload[LOGGER_ENTRY_MAX_PAYLOAD + 1];
        memcpy(payload, msg.buf, len);
        payload[len] = '\0';

        if (raw) {
            printf("RAW n=%d len=%u hdr=%u pid=%d lid=%u uid=%u ", n, len,
                   msg.hdr_size, msg.pid, msg.lid, msg.uid);
            uint16_t lim = len < 200 ? len : 200;
            for (uint16_t i = 0; i < lim; i++) {
                unsigned char c = (unsigned char)payload[i];
                if (c >= 32 && c < 127) {
                    putchar(c);
                } else {
                    printf("\\x%02x", c);
                }
            }
            putchar('\n');
            fflush(stdout);
        }

        /* The payload is binary: tag id, type bytes and length prefixes carry
         * NULs, so strstr/strchr would stop before the text. Everything below
         * is length bounded. */
        const char *ev = NULL;
        const char *p = memmem(payload, len, "Focus entering ", 15);
        if (p) {
            ev = "entering";
            p += 15;
        } else {
            p = memmem(payload, len, "Focus leaving ", 14);
            if (p) {
                ev = "leaving";
                p += 14;
            }
        }
        if (!ev) {
            continue;
        }

        /* "<hash> <pkg>/<activity> (server)" */
        const char *sp = memchr(p, ' ', (size_t)(payload + len - p));
        if (!sp) {
            continue;
        }
        const char *comp = sp + 1;
        size_t crest = (size_t)(payload + len - comp);
        const char *end = memchr(comp, ' ', crest);
        if (!end) {
            continue;
        }
        size_t clen = (size_t)(end - comp);
        if (clen == 0 || clen > 255 || !memchr(comp, '/', clen)) {
            continue;
        }
        /* only window-server focus, not client-side windows */
        if (crest < 9 || memcmp(end, " (server)", 9) != 0) {
            continue;
        }

        printf("%s %.*s\n", ev, (int)clen, comp);
        fflush(stdout);
    }

    p_free(list);
    dlclose(lib);
    return 0;
}
