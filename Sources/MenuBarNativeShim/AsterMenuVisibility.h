// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (Ice) © 2023–2025 Jordan Baird
// Copyright (Thaw) © 2026 Toni Förster
// Adapted for Aster from Thaw revision 7a4ce9fd68c1ba614d409000afef3d18d4b2db3d.

#import <Foundation/Foundation.h>

BOOL AsterMenuVisibilityAvailable(void);
void *_Nullable AsterMenuVisibilityActivate(NSArray<NSString *> *_Nonnull bundles,
    NSArray<NSNumber *> *_Nonnull systemItems, void (^_Nullable onFailure)(void));
void AsterMenuVisibilityInvalidate(void *_Nullable handle);
