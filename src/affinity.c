// Copyright (C) 2012 - Will Glozer.  All rights reserved.

#include "affinity.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

#ifdef __linux__
#include <sched.h>
#endif

int affinity_parse(const char *value, cpu_affinity *affinity) {
    const char *p = value;
    unsigned int *cpus = NULL;
    size_t count = 0;

    if (!value || !*value) return -1;

    while (*p) {
        char *endptr;
        unsigned long first, last;

        if (!isdigit((unsigned char)*p)) goto invalid;
        errno = 0;
        first = strtoul(p, &endptr, 10);
        if (errno || first > UINT_MAX) goto invalid;
        p = endptr;
        last = first;

        if (*p == '-') {
            p++;
            if (!isdigit((unsigned char)*p)) goto invalid;
            errno = 0;
            last = strtoul(p, &endptr, 10);
            if (errno || last > UINT_MAX || last < first) goto invalid;
            p = endptr;
        }

#ifdef __linux__
        if (last >= CPU_SETSIZE) goto invalid;
#endif

        uintmax_t span = (uintmax_t)last - first + 1;
        if (span > (SIZE_MAX / sizeof(*cpus)) - count) goto invalid;

        size_t new_count = count + (size_t)span;
        unsigned int *new_cpus = realloc(cpus, new_count * sizeof(*cpus));
        if (!new_cpus) goto invalid;
        cpus = new_cpus;

        for (uintmax_t offset = 0; offset < span; offset++) {
            cpus[count++] = (unsigned int)(first + offset);
        }

        if (!*p) break;
        if (*p++ != ',' || !*p) goto invalid;
    }

    affinity->cpus = cpus;
    affinity->count = count;
    return 0;

invalid:
    free(cpus);
    return -1;
}

int affinity_supported(void) {
#ifdef __linux__
    return 1;
#else
    return 0;
#endif
}

int affinity_set_attr(pthread_attr_t *attr, unsigned int cpu) {
#ifdef __linux__
    cpu_set_t cpuset;

    if (cpu >= CPU_SETSIZE) return EOVERFLOW;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu, &cpuset);
    return pthread_attr_setaffinity_np(attr, sizeof(cpuset), &cpuset);
#else
    (void)attr;
    (void)cpu;
    return ENOTSUP;
#endif
}

void affinity_free(cpu_affinity *affinity) {
    free(affinity->cpus);
    affinity->cpus = NULL;
    affinity->count = 0;
}
