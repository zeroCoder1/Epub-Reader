

#import <Foundation/Foundation.h>

@interface EpubContent : NSObject {

	NSMutableDictionary *_manifest;
	NSMutableArray *_spine;
}

@property (nonatomic, strong) NSMutableDictionary *_manifest;
@property (nonatomic, strong) NSMutableArray *_spine;

@end
