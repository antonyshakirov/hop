#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "build")) return 64;
    const char *library = getenv("HOP_PRIVATE_ATOMIC_LIBRARY");
    const char *previous = getenv("DYLD_INSERT_LIBRARIES");
    if (!library || library[0] != '/') return 70;
    const char *tracer = getenv("SEMMLE_PRELOAD_libtrace");
    if (!previous && tracer) previous = tracer;
    size_t length = strlen(library) + (previous ? strlen(previous) + 1 : 0) + 1;
    char *value = malloc(length);
    if (!value) return 70;
    snprintf(value, length, "%s%s%s", library, previous ? ":" : "", previous ? previous : "");
    if (setenv("DYLD_INSERT_LIBRARIES", value, 1)) return 70;
    const char *build = getenv("HOP_PRIVATE_SWIFT_BUILD");
    if (!build || build[0] != '/') return 70;
    argv[1] = (char *)build;
    execv(argv[1], argv + 1);
    perror("swift launcher");
    return 70;
}
