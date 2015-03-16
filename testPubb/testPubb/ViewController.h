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



@interface ViewController : UIViewController<XMLHandlerDelegate,UIGestureRecognizerDelegate,UITextViewDelegate,UISearchBarDelegate, NSLayoutManagerDelegate, UIScrollViewDelegate>{
    
    
    IBOutlet UILabel *_pageNumberLbl;
   
    
    XMLHandler *_xmlHandler;
	EpubContent *_ePubContent;
	NSString *_pagesPath;
	NSString *_rootPath;
	NSString *_strFileName;
	int _pageNumber;
    
    NSUInteger textFontSize;
    UIColor* color;
    
    BOOL isNightMode;
    

    CGRect textViewFrame;
    CGSize columnSize;
    BOOL isLandscape;
}


@property (nonatomic, strong)EpubContent *_ePubContent;
@property (nonatomic, strong)NSString *_rootPath;
@property (nonatomic, strong)NSString *_strFileName;

@property (strong, nonatomic) UITextView *textView;
@property (weak, nonatomic) IBOutlet UISearchBar *searchBar;

@property (weak, nonatomic) IBOutlet UIToolbar *topToolbar;

@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;




- (void)unzipAndSaveFile;
- (NSString *)applicationDocumentsDirectory; 
- (void)loadPage;
- (NSString*)getRootFilePath;


- (IBAction)removeHighlightsB;


-(IBAction)plusA:(id)sender;
-(IBAction)minusA:(id)sender;
-(IBAction)day:(id)sender;
-(IBAction)night:(id)sender;

- (IBAction)next:(id)ignored;
- (IBAction)prev:(id)ignored;

@property (nonatomic, strong) NSTextStorage *textStorage;
@property (nonatomic, strong) NSLayoutManager *layoutManager;

@property (nonatomic, strong) UISwipeGestureRecognizer *swipeRight;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipeLeft;



@property (strong, nonatomic) NSArray *textOrigins;
@end
