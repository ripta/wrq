#ifndef AFFINITY_H
#define AFFINITY_H

#include <pthread.h>
#include <stddef.h>

typedef struct {
    unsigned int *cpus;
    size_t count;
} cpu_affinity;

int affinity_parse(const char *, cpu_affinity *);
int affinity_supported(void);
int affinity_set_attr(pthread_attr_t *, unsigned int);
void affinity_free(cpu_affinity *);

#endif /* AFFINITY_H */
