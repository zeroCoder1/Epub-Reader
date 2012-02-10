

#import "XMLHandler.h"


@implementation XMLHandler
@synthesize delegate;

- (void)parseXMLFileAt:(NSString*)strPath{

	_parser=[[NSXMLParser alloc] initWithContentsOfURL:[NSURL fileURLWithPath:strPath]];
	_parser.delegate=self;
	[_parser parse];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
	
	NSLog(@"Error Occured : %@",[parseError description]);

}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict{
	
	if ([elementName isEqualToString:@"rootfile"]) {
		
		_rootPath=[attributeDict valueForKey:@"full-path"];
		if ((delegate!=nil)&&([delegate respondsToSelector:@selector(foundRootPath:)])) {
			
			[delegate foundRootPath:_rootPath];
		}
	}
	
	if ([elementName isEqualToString:@"package"]){
	
		_epubContent=[[EpubContent alloc] init];
	}
	
	if ([elementName isEqualToString:@"manifest"]) {
		
		_itemdictionary=[[NSMutableDictionary alloc] init];
	}
	
	if ([elementName isEqualToString:@"item"]) {
		
		[_itemdictionary setValue:[attributeDict valueForKey:@"href"] forKey:[attributeDict valueForKey:@"id"]];
	}
	
	if ([elementName isEqualToString:@"spine"]) {
		
		_spinearray=[[NSMutableArray alloc] init];
	}
	
	if ([elementName isEqualToString:@"itemref"]) {
		
		[_spinearray addObject:[attributeDict valueForKey:@"idref"]];
	}
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string{
	
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName{     
	
		if ([elementName isEqualToString:@"manifest"]) {
			
			_epubContent._manifest=_itemdictionary;
		}
		if ([elementName isEqualToString:@"spine"]) {
			
			_epubContent._spine=_spinearray;
		}
	
		if ([elementName isEqualToString:@"package"]) {
		
            if ((delegate!=nil)&&([delegate respondsToSelector:@selector(finishedParsing:)])) {
                
                [delegate finishedParsing:_epubContent];
            }

		}

}

- (void)parserDidEndDocument:(NSXMLParser *)parser {
	
   }

@end
