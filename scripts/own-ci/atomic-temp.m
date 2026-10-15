#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

static NSURL *(*original_url)(id, SEL, NSSearchPathDirectory, NSSearchPathDomainMask, NSURL *, BOOL, NSError **);
static char private_temporary[PATH_MAX];
static NSString *private_root;

static NSString *private_temporary_path(void) {
    return [[NSString stringWithUTF8String:private_temporary] stringByAppendingString:@"/"];
}

static NSURL *private_temporary_url(id object, SEL selector) {
    (void)object;
    (void)selector;
    return [NSURL fileURLWithFileSystemRepresentation:private_temporary isDirectory:YES relativeToURL:nil];
}

__attribute__((used)) static const struct { const void *replacement; const void *original; }
interposed_temporary __attribute__((section("__DATA,__interpose"))) = { (const void *)private_temporary_path, (const void *)NSTemporaryDirectory };

static NSURL *private_url(id object, SEL selector, NSSearchPathDirectory directory, NSSearchPathDomainMask domain, NSURL *appropriate, BOOL create, NSError **error) {
    if (directory != NSItemReplacementDirectory) return original_url(object, selector, directory, domain, appropriate, create, error);
    char resolved[PATH_MAX];
    NSString *target = nil;
    if (appropriate.isFileURL) {
        const char *path = appropriate.path.fileSystemRepresentation;
        if (realpath(path, resolved)) {
            target = [NSString stringWithUTF8String:resolved];
        } else if (errno == ENOENT && realpath(appropriate.path.stringByDeletingLastPathComponent.fileSystemRepresentation, resolved)) {
            target = [[NSString stringWithUTF8String:resolved] stringByAppendingPathComponent:appropriate.path.lastPathComponent];
        }
    }
    struct stat destination, temporary;
    BOOL inside = target && ([target isEqualToString:private_root] || [target hasPrefix:[private_root stringByAppendingString:@"/"]]);
    if (!inside || stat(target.stringByDeletingLastPathComponent.fileSystemRepresentation, &destination) || stat(private_temporary, &temporary) || destination.st_dev != temporary.st_dev) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EPERM userInfo:@{@"target":target ?: @"<no file URL>", @"root":private_root}];
        return nil;
    }
    char pattern[PATH_MAX];
    int length = snprintf(pattern, sizeof(pattern), "%s/atomic.XXXXXX", private_temporary);
    if (length < 0 || (size_t)length >= sizeof(pattern) || !mkdtemp(pattern)) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno ?: EINVAL userInfo:nil];
        return nil;
    }
    return [NSURL fileURLWithFileSystemRepresentation:pattern isDirectory:YES relativeToURL:nil];
}

__attribute__((constructor)) static void configure_private_temporary(void) {
    const char *temporary = getenv("TMPDIR");
    struct stat metadata;
    if (!temporary || !realpath(temporary, private_temporary) || stat(private_temporary, &metadata) || !S_ISDIR(metadata.st_mode) || metadata.st_uid != getuid() || (metadata.st_mode & 0077)) abort();
    NSString *path = [NSString stringWithUTF8String:private_temporary];
    if (![path.lastPathComponent isEqualToString:@"tmp"]) abort();
    private_root = [path.stringByDeletingLastPathComponent copy];
    Class cls = object_getClass([NSFileManager defaultManager]);
    Method temporary_method = class_getInstanceMethod(cls, @selector(temporaryDirectory));
    if (!temporary_method) abort();
    method_setImplementation(temporary_method, (IMP)private_temporary_url);
    SEL selector = @selector(URLForDirectory:inDomain:appropriateForURL:create:error:);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) abort();
    original_url = (void *)method_getImplementation(method);
    method_setImplementation(method, (IMP)private_url);
}
