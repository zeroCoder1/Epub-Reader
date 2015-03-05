//
//  ViewController.h
//  testPubb
//
//  Created by Shrutesh on 07/02/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "EpubContent.h"
#import "XMLHandler.h"
#import <QuartzCore/QuartzCore.h>

@interface ViewController : UIViewController<XMLHandlerDelegate,UIGestureRecognizerDelegate,UIWebViewDelegate,UISearchBarDelegate>{
    
    
    IBOutlet UILabel *_pageNumberLbl;
   
    
    XMLHandler *_xmlHandler;
	EpubContent *_ePubContent;
	NSString *_pagesPath;
	NSString *_rootPath;
	NSString *_strFileName;
	int _pageNumber;
    
    NSUInteger textFontSize;
    UIColor* color;
    
    BOOL isInverted;
}


@property (nonatomic, strong)EpubContent *_ePubContent;
@property (nonatomic, strong)NSString *_rootPath;
@property (nonatomic, strong)NSString *_strFileName;

@property (strong, nonatomic) IBOutlet UITextView *textView;



- (void)unzipAndSaveFile;
- (NSString *)applicationDocumentsDirectory; 
- (void)loadPage;
- (NSString*)getRootFilePath;

- (NSInteger)stringHighlight:(NSString*)str;
- (IBAction)removeHighlightsB;


-(IBAction)plusA:(id)sender;
-(IBAction)minusA:(id)sender;
-(IBAction)day:(id)sender;
-(IBAction)night:(id)sender;

- (IBAction)next:(id)ignored;
- (IBAction)prev:(id)ignored;


@end
