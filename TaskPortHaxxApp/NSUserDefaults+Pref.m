//
//  NSUserDefaults+Pref.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 2/11/25.
//

@import Foundation;
#import "Header.h"

@implementation NSUserDefaults(Pref)
- (void)setSignedPointer:(NSUInteger)signedPointer {
    [self setObject:@(signed_pointer = signedPointer) forKey:@"signedPointer"];
}
- (NSUInteger)signedPointer {
    return signed_pointer = [[self objectForKey:@"signedPointer"] unsignedIntegerValue];
}
- (void)setSignedDiversifier:(uint32_t)signedDiversifier {
    [self setObject:@(signedDiversifier) forKey:@"signedDiversifier"];
}
- (uint32_t)signedDiversifier {
    return [[self objectForKey:@"signedDiversifier"] unsignedIntValue];
}
@end
