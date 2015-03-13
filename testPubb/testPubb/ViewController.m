//
//  ViewController.m
//  testPubb
//
//  Created by Shrutesh on 07/02/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "ViewController.h"
#import "SSZipArchive.h"




@implementation ViewController
@synthesize _ePubContent;
@synthesize _rootPath;
@synthesize _strFileName;


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    [_textView setBackgroundColor:[UIColor whiteColor]];
    [self unzipAndSaveFile];
	_xmlHandler=[[XMLHandler alloc] init];
	_xmlHandler.delegate=self;
	[_xmlHandler parseXMLFileAt:[self getRootFilePath]];
    
    
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self  action:@selector(swipeRightAction:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRight.delegate = self;
    [_textView addGestureRecognizer:swipeRight];
    
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeftAction:)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeft.delegate = self;
    [_textView addGestureRecognizer:swipeLeft];

    textFontSize = 14;
    _textView.textColor = color;
     isNightMode = NO;
    
    
}



/*Function Name : unzipAndSaveFile
 *Return Type   : void
 *Parameters    : nil
 *Purpose       : To unzip the epub file to documents directory
 */

- (void)unzipAndSaveFile{
	
    NSString *zipPath = [[NSBundle mainBundle] pathForResource:_strFileName ofType:@"epub"];
    NSString *destinationPath = [NSString stringWithFormat:@"%@/UnzippedEpub",[self applicationDocumentsDirectory]];
    [SSZipArchive unzipFileAtPath:zipPath toDestination:destinationPath overwrite:YES password:nil error:nil];

}

/*Function Name : applicationDocumentsDirectory
 *Return Type   : NSString - Returns the path to documents directory
 *Parameters    : nil
 *Purpose       : To find the path to documents directory
 */

- (NSString *)applicationDocumentsDirectory {
	
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

/*Function Name : getRootFilePath
 *Return Type   : NSString - Returns the path to container.xml
 *Parameters    : nil
 *Purpose       : To find the path to container.xml.This file contains the file name which holds the epub informations
 */

- (NSString*)getRootFilePath{
	
	//check whether root file path exists
	NSFileManager *filemanager=[[NSFileManager alloc] init];
	NSString *strFilePath=[NSString stringWithFormat:@"%@/UnzippedEpub/META-INF/container.xml",[self applicationDocumentsDirectory]];
	if ([filemanager fileExistsAtPath:strFilePath]) {
		
		//valid ePub
		NSLog(@"Parse now");

		return strFilePath;


        
	}
	else {
		
		//Invalid ePub file
		UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"Error"
													  message:@"Root File not Valid"
													 delegate:self
											cancelButtonTitle:@"OK"
											otherButtonTitles:nil];
		[alert show];
		 alert=nil;
		
	}
    filemanager=nil;
	return @"";
}


#pragma mark XMLHandler Delegate Methods

- (void)foundRootPath:(NSString*)rootPath{
	
	//Found the path of *.opf file
	
	//get the full path of opf file
	NSString *strOpfFilePath=[NSString stringWithFormat:@"%@/UnzippedEpub/%@",[self applicationDocumentsDirectory],rootPath];
	NSFileManager *filemanager=[[NSFileManager alloc] init];
	
	self._rootPath=[strOpfFilePath stringByReplacingOccurrencesOfString:[strOpfFilePath lastPathComponent] withString:@""];
	
	if ([filemanager fileExistsAtPath:strOpfFilePath]) {
		
		//Now start parse this file
		[_xmlHandler parseXMLFileAt:strOpfFilePath];
	}
	else {
		
		UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"Error"
													  message:@"OPF File not found"
													 delegate:self
											cancelButtonTitle:@"OK"
											otherButtonTitles:nil];
		[alert show];
		alert=nil;
	}
	filemanager=nil;
	
}


- (void)finishedParsing:(EpubContent*)ePubContents{
    
	_pagesPath=[NSString stringWithFormat:@"%@/%@",self._rootPath,[ePubContents._manifest valueForKey:[ePubContents._spine objectAtIndex:0]]];
	self._ePubContent=ePubContents;
	_pageNumber=0;
	[self loadPage];
}

/*Function Name : loadPage
 *Return Type   : void 
 *Parameters    : nil
 *Purpose       : To load actual pages to webview
 */

- (void)loadPage{
   
	
	_pagesPath=[NSString stringWithFormat:@"%@/%@",self._rootPath,[self._ePubContent._manifest valueForKey:[self._ePubContent._spine objectAtIndex:_pageNumber]]];
	//[_webview loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:_pagesPath]]];
	//set page number
    NSString* htmlString = [[NSString alloc] initWithData:[NSData dataWithContentsOfURL:[NSURL fileURLWithPath:_pagesPath]] encoding:NSUTF8StringEncoding];

    dispatch_async(dispatch_get_main_queue(), ^{
//        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithData:[htmlString dataUsingEncoding:NSUnicodeStringEncoding] options:@{ NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType } documentAttributes:nil error:nil];
//        _textView.attributedText = attributedString;
//        _textView.font = [UIFont systemFontOfSize:textFontSize];
//        _textView.textColor = color;
        
        _textStorage = [[NSTextStorage alloc]initWithData:[htmlString dataUsingEncoding:NSUnicodeStringEncoding] options:@{ NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType } documentAttributes:nil error:nil];
        
        _layoutManager = [[NSLayoutManager alloc]init];
        [_textStorage addLayoutManager:_layoutManager];
        [self layoutTextContainers];
        
    });
    
   //
    
    NSLog(@"The htmlString to pages %@",htmlString);
    
    _pageNumberLbl.text=[NSString stringWithFormat:@"%d",_pageNumber+1];
    
   
    
}


- (void)layoutTextContainers{
    
    NSUInteger lastRenderedGlyph = 0;
    CGFloat currentXOffset = 0;
    while (lastRenderedGlyph < _layoutManager.numberOfGlyphs) {
        CGRect textViewFrame = CGRectMake(currentXOffset, 0, CGRectGetWidth(self.scrollView.bounds) / 2, CGRectGetHeight(self.scrollView.bounds));
        CGSize columnSize = CGSizeMake(CGRectGetWidth(textViewFrame) - 20,CGRectGetHeight(textViewFrame) - 10);
        
        NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:columnSize];
        [_layoutManager addTextContainer:textContainer];
        _textView = [[UITextView alloc] initWithFrame:textViewFrame
                                                   textContainer:textContainer];
        _textView.scrollEnabled = NO;
        _textView.font = [UIFont systemFontOfSize:textFontSize];
        if (isNightMode) {
            _textView.textColor = [UIColor whiteColor];
            _textView.backgroundColor = [UIColor blackColor];

        }else{
            
            _textView.textColor = [UIColor blackColor];
            _textView.backgroundColor = [UIColor whiteColor];

        }
        
        [self.scrollView addSubview:_textView];
        
        // Increase the current offset
        currentXOffset += CGRectGetWidth(textViewFrame);
        
        // And find the index of the glyph we've just rendered
        lastRenderedGlyph = NSMaxRange([_layoutManager glyphRangeForTextContainer:textContainer]);
    }
    
    // Need to update the scrollView size
    CGSize contentSize = CGSizeMake(currentXOffset, CGRectGetHeight(self.scrollView.bounds));
    self.scrollView.contentSize = contentSize;

    
}


- (void)swipeRightAction:(id)ignored{
    
    if (_pageNumber >0 ) {
  
    
    CATransition *animation = [CATransition animation];
    [animation setDelegate:self];
    [animation setDuration:0.5f];
    [animation setType:@"pageUnCurl"];
    
    //[animation setType:kcat]; 
    [animation setSubtype:@"fromRight"];

    //[_webview reload];
    _pageNumber--;
    [self loadPage];
    [[_textView layer] addAnimation:animation forKey:@"WebPageUnCurl"];

  }

}



- (void)swipeLeftAction:(id)ignored
{
    
    if (_pageNumber < [self._ePubContent._spine count]-1 ) {

    CATransition *animation = [CATransition animation];
    [animation setDelegate:self];
    [animation setDuration:0.5f];
    [animation setType:@"pageCurl"];
    
    //[animation setType:kcat]; 
    [animation setSubtype:@"fromRight"];
    

    

    //[_textView reload];
    _pageNumber++;
    [self loadPage];
    
    [[_textView layer] addAnimation:animation forKey:@"WebPageCurl"];

    }

}



- (IBAction)prev:(id)ignored{
    
    if (_pageNumber >0 ) {

    CATransition *animation = [CATransition animation];
    [animation setDelegate:self];
    [animation setDuration:0.5f];
    [animation setType:@"pageUnCurl"];
    [animation setSubtype:@"fromRight"];
    
    
   // [_webview reload];
    _pageNumber--;
    [self loadPage];
    [[_scrollView layer] addAnimation:animation forKey:@"WebPageUnCurl"];
    
    }
}



- (IBAction)next:(id)ignored
{
    if (_pageNumber < [self._ePubContent._spine count]-1 ) {

    
    CATransition *animation = [CATransition animation];
    [animation setDelegate:self];
    [animation setDuration:0.5f];
    [animation setType:@"pageCurl"];
    [animation setSubtype:@"fromRight"];
    //[_webview reload];
    _pageNumber++;
    [self loadPage];
    
    [[_scrollView layer] addAnimation:animation forKey:@"WebPageCurl"];

    }
    
    
}


-(IBAction)plusA:(id)sender{
    
    textFontSize = (textFontSize < 50) ? textFontSize +2 : textFontSize;
    [self.textView setFont:[UIFont systemFontOfSize:textFontSize]];
    
    [self loadPage];
}



-(IBAction)minusA:(id)sender{

    textFontSize = (textFontSize > 14) ? textFontSize -2 : textFontSize;
   [self.textView setFont:[UIFont systemFontOfSize:textFontSize]];

    [self loadPage];

}


-(IBAction)day:(id)sender{
    

    
    isNightMode = NO;
    [self loadPage];

}



-(IBAction)night:(id)sender{


    isNightMode = YES;
    [self loadPage];
   
    

}


- (void)removeHighlights{
    
   
   // [_webview stringByEvaluatingJavaScriptFromString:@"uiWebview_RemoveAllHighlights()"];  // to remove highlight
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    

    NSString * searchString = searchBar.text;
    NSString *html = [[NSString alloc] initWithData:[NSData dataWithContentsOfURL:[NSURL fileURLWithPath:_pagesPath]] encoding:NSUTF8StringEncoding];
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithData:[html dataUsingEncoding:NSUnicodeStringEncoding] options:@{ NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType } documentAttributes:nil error:nil];
    _textView.attributedText = attributedString;

    NSString * baseString = _textView.text;
    
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:searchString options:NSRegularExpressionCaseInsensitive error:&error];
    NSArray *matches = [regex matchesInString:baseString
                                      options:0
                                        range:NSMakeRange(0, baseString.length)];
    
    for (NSTextCheckingResult *match in matches)
    {
        NSRange matchRange = [match rangeAtIndex:0];
        [attributedString addAttribute:NSBackgroundColorAttributeName
                                 value:[UIColor yellowColor]
                                 range:matchRange];
     

    }
    
    _textView.attributedText = attributedString;


    if (isNightMode) {
        _textView.textColor = [UIColor whiteColor];

    }else{
        _textView.textColor = [UIColor blackColor];
    }
    

    
    [_textView setFont:[UIFont systemFontOfSize:textFontSize]];


    [searchBar becomeFirstResponder];
}


- (IBAction)removeHighlightsB{
    [self loadPage];

   [self.view endEditing:YES];
}





- (void)viewDidUnload{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated{
	[super viewDidDisappear:animated];
}


//TextView Delegate
- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange{
    
    _pagesPath=[NSString stringWithFormat:@"%@/%@",self._rootPath,[self._ePubContent._manifest valueForKey:[self._ePubContent._spine objectAtIndex:_pageNumber]]];
    NSString * URLString = [NSString stringWithFormat:@"%@",URL];
    NSString * lastPath = [URLString lastPathComponent];
    NSString * firstPath = [_pagesPath stringByDeletingLastPathComponent];
    
    NSArray *myStrings = [[NSArray alloc] initWithObjects:firstPath, @"/", lastPath, nil];
    NSString *joinedString = [myStrings componentsJoinedByString:@""];
    
    ///***** Should be a better method to do this ******///
    NSString* htmlString = [[NSString alloc] initWithData:[NSData dataWithContentsOfURL:[NSURL fileURLWithPath:joinedString]] encoding:NSUTF8StringEncoding];


    dispatch_async(dispatch_get_main_queue(), ^{
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithData:[htmlString dataUsingEncoding:NSUnicodeStringEncoding] options:@{ NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType } documentAttributes:nil error:nil];
        _textView.attributedText = attributedString;
        _textView.font = [UIFont systemFontOfSize:textFontSize];
        _textView.textColor = color;
    });
    
    return YES;
}

@end
