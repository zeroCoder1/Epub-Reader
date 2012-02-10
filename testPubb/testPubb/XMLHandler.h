

#import <Foundation/Foundation.h>
#import "EpubContent.h"

@protocol XMLHandlerDelegate <NSObject>

@optional
- (void)foundRootPath:(NSString*)rootPath;
- (void)finishedParsing:(EpubContent*)ePubContents;
@end


@interface XMLHandler : NSObject <NSXMLParserDelegate>{

	NSXMLParser *_parser;
	NSString *_rootPath;
	id<XMLHandlerDelegate> delegate;
	EpubContent *_epubContent;
	NSMutableDictionary *_itemdictionary;
	NSMutableArray *_spinearray;
}

@property (nonatomic, retain) id<XMLHandlerDelegate> delegate;
- (void)parseXMLFileAt:(NSString*)strPath;
@end
