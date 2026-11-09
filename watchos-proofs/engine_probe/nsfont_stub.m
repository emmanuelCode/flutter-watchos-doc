// Stand-in for the one AppKit class the macOS engine build touches at text-layout time.
// txt::GetDefaultFontFamilies() (macOS build) does roughly: [[NSFont systemFontOfSize:14] familyName].
// AppKit does not exist on watchOS, so the retagged engine would message a zeroed fake class and crash.
// This is a workaround for the retagged-binary experiment only, not part of any real port.
#import <Foundation/Foundation.h>

@interface NSFont : NSObject
+ (instancetype)systemFontOfSize:(double)size;
- (NSString *)familyName;
@end

@implementation NSFont
+ (instancetype)systemFontOfSize:(double)size { return [[NSFont alloc] init]; }
- (NSString *)familyName { return @"Helvetica"; }
@end
