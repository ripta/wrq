#include "affinity.h"

#include <assert.h>
#include <stddef.h>

static void check_list(const char *value, const unsigned int *expected,
        size_t expected_count) {
    cpu_affinity affinity = { 0 };

    assert(affinity_parse(value, &affinity) == 0);
    assert(affinity.count == expected_count);
    for (size_t i = 0; i < expected_count; i++) {
        assert(affinity.cpus[i] == expected[i]);
    }
    affinity_free(&affinity);
}

int main(void) {
    const unsigned int list[] = { 0, 1, 7, 8 };
    const unsigned int range[] = { 0, 1, 2, 3 };
    const unsigned int mixed[] = { 1, 3, 4, 5, 8 };
    const char *invalid[] = {
        "", ",1", "1,", "1,,2", "-1", "+1", "1-", "3-1", "1 2", "1-2-3"
    };

    check_list("0,1,7,8", list, sizeof(list) / sizeof(list[0]));
    check_list("0-3", range, sizeof(range) / sizeof(range[0]));
    check_list("1,3-5,8", mixed, sizeof(mixed) / sizeof(mixed[0]));

    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        cpu_affinity affinity = { 0 };
        assert(affinity_parse(invalid[i], &affinity) == -1);
    }

    return 0;
}
