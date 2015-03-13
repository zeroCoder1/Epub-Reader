//
//  EpubContent.h
//  testPubb
//
//  Created by Shrutesh on 07/02/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//



#import <Foundation/Foundation.h>

@interface EpubContent : NSObject {

	NSMutableDictionary *_manifest;
	NSMutableArray *_spine;
}

@property (nonatomic, retain) NSMutableDictionary *_manifest;
@property (nonatomic, retain) NSMutableArray *_spine; 



@end
