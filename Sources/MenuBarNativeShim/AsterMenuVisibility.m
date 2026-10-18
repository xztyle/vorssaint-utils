// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (Thaw) © 2026 Toni Förster
// Adapted for Aster from Thaw revision 7a4ce9fd68c1ba614d409000afef3d18d4b2db3d.

#import "AsterMenuVisibility.h"
#import <dlfcn.h>
#import <os/log.h>

@interface MBAssessmentModeConfiguration : NSObject
- (instancetype)initWithAllowedSystemItems:(NSArray<NSNumber *> *)items
                 allowedBundleIdentifiers:(NSArray<NSString *> *)bundles;
@end
@interface MBAssessmentModeAssertion : NSObject
- (void)activateWithConfiguration:(id)configuration completionHandler:(void (^)(NSError *))completion;
- (void)invalidate;
@end

static BOOL LoadMenuBarClient(void) {
    static dispatch_once_t once;
    static BOOL loaded;
    dispatch_once(&once, ^{
        loaded = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW) != NULL;
    });
    return loaded;
}

BOOL AsterMenuVisibilityAvailable(void) {
    return LoadMenuBarClient() && NSClassFromString(@"MBAssessmentModeConfiguration") != nil &&
        NSClassFromString(@"MBAssessmentModeAssertion") != nil;
}

static MBAssessmentModeAssertion *CreateAssertion(NSArray *bundles, NSArray *items, void (^failure)(void)) {
    Class configClass = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
    id config = [[configClass alloc] initWithAllowedSystemItems:items allowedBundleIdentifiers:bundles];
    if (!config) return nil;
    MBAssessmentModeAssertion *assertion = [[assertionClass alloc] init];
    if (!assertion) return nil;
    [assertion activateWithConfiguration:config completionHandler:^(NSError *error) {
        if (error) {
            os_log_error(OS_LOG_DEFAULT, "Aster menu visibility failed: %{public}@ (%ld)", error.domain, (long)error.code);
            if (failure) dispatch_async(dispatch_get_main_queue(), failure);
        }
    }];
    return assertion;
}

void *AsterMenuVisibilityActivate(NSArray<NSString *> *bundles, NSArray<NSNumber *> *items, void (^onFailure)(void)) {
    if (!AsterMenuVisibilityAvailable()) return NULL;
    @try {
        id assertion = CreateAssertion(bundles, items, onFailure ? [onFailure copy] : nil);
        return assertion ? (void *)CFBridgingRetain(assertion) : NULL;
    } @catch (NSException *exception) {
        os_log_error(OS_LOG_DEFAULT, "Aster menu visibility exception: %{public}@", exception.name);
        return NULL;
    }
}

void AsterMenuVisibilityInvalidate(void *handle) {
    if (!handle) return;
    MBAssessmentModeAssertion *assertion = (MBAssessmentModeAssertion *)CFBridgingRelease(handle);
    @try { [assertion invalidate]; } @catch (NSException *exception) {}
}
