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
    
    _swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self  action:@selector(prev:)];
    _swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    _swipeRight.delegate = self;
    _swipeRight.enabled = NO;
    [_scrollView addGestureRecognizer:_swipeRight];
    
    _swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(next:)];
    _swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    _swipeLeft.delegate = self;
    _swipeLeft.enabled = NO;
    [_scrollView addGestureRecognizer:_swipeLeft];

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
	
    NSString *zipPath = [[NSBundle mainBundle] pathForResource:@"igp-ttohr-math copy" ofType:@"epub"];
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
    
    stringArray = [[NSMutableArray alloc]init];
    originalArray = [[NSMutableArray alloc]init];


    NSString* htmlString = [[NSString alloc] initWithData:[NSData dataWithContentsOfURL:[NSURL fileURLWithPath:_pagesPath]] encoding:NSUTF8StringEncoding];
   
    
        NSError *error = NULL;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(<img\\s[\\s\\S]*?src\\s*?=\\s*?['\"](.*?)['\"][\\s\\S]*?>)+?"
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:&error];
        
        [regex enumerateMatchesInString:htmlString
                                options:0
                                  range:NSMakeRange(0, [htmlString length])
                             usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                                 
                                 _originalImageString = [htmlString substringWithRange:[result rangeAtIndex:2]];
                                 
                                 [originalArray addObject:_originalImageString];
                                 
                                 
                                 NSArray *myStrings = [[NSArray alloc] initWithObjects:[_pagesPath stringByDeletingLastPathComponent], @"/", _originalImageString, nil];
                                 _joinedString = [myStrings componentsJoinedByString:@""];
                                 
                                 [stringArray addObject:[NSString stringWithFormat:@"file://%@",_joinedString]];
                                 
                             }];
        
        
        _outputString = htmlString;
        
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_originalImageString) {
            for (int i= 0; i< [stringArray count]; i++) {
                
                _outputString = [_outputString stringByReplacingOccurrencesOfString:[originalArray objectAtIndex:i] withString:[stringArray objectAtIndex:i]];
                
                /*
                 NSString *docsFolder = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
                 NSString *filename = [docsFolder stringByAppendingPathComponent:@"sample.html"];
                 NSError *error;
                 [_outputString writeToFile:filename atomically:NO encoding:NSUTF8StringEncoding error:&error];
                 */
            }
        }else{
            _outputString = [NSString stringWithString:htmlString];
        }
        
        
        _textStorage = [[NSTextStorage alloc]initWithData:[_outputString dataUsingEncoding:NSUnicodeStringEncoding] options:@{ NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType } documentAttributes:nil error:nil];
        _layoutManager = [[NSLayoutManager alloc]init];
        [_textStorage addLayoutManager:_layoutManager];
        
        [self layoutTextContainers];
    });
    
    _pageNumberLbl.text=[NSString stringWithFormat:@"%d",_pageNumber+1];
    
   
}


+ (NSString *)scanString:(NSString *)string startTag:(NSString *)startTag endTag:(NSString *)endTag {
    
    NSString* scanString = @"";
    
    if (string.length > 0) {
        
        NSScanner* scanner = [[NSScanner alloc] initWithString:string];
        
        @try {
            [scanner scanUpToString:startTag intoString:nil];
            scanner.scanLocation += [startTag length];
            [scanner scanUpToString:endTag intoString:&scanString];
        }
        @catch (NSException *exception) {
            return nil;
        }
        @finally {
            return scanString;
        }
        
    }
    
    return scanString;
    
}



- (void)layoutTextContainers{
    
    NSUInteger lastRenderedGlyph = 0;
    CGFloat currentXOffset = 0;
   
    while (lastRenderedGlyph < _layoutManager.numberOfGlyphs) {
        if (self.view.frame.size.width > self.view.frame.size.height) {
            isLandscape = YES;
                textViewFrame = CGRectMake(currentXOffset, 0, CGRectGetWidth(self.scrollView.bounds) / 2, CGRectGetHeight(self.scrollView.bounds));
                columnSize = CGSizeMake(CGRectGetWidth(textViewFrame) - 20,CGRectGetHeight(textViewFrame) - 10);

        }else{

                textViewFrame = CGRectMake(currentXOffset, 0, CGRectGetWidth(self.scrollView.bounds), CGRectGetHeight(self.scrollView.bounds));
                columnSize = CGSizeMake(CGRectGetWidth(textViewFrame) - 20,CGRectGetHeight(textViewFrame) - 10);

        }
        
        
        NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:columnSize];
        [_layoutManager addTextContainer:textContainer];
        _textView = [[UITextView alloc] initWithFrame:textViewFrame textContainer:textContainer];
        
        _textView.scrollEnabled = NO;
        _textView.delegate = self;
        _textView.font = [UIFont systemFontOfSize:textFontSize];
        _textView.editable = NO;
        _textView.selectable = YES;

    
        [self.scrollView addSubview:_textView];
        
        if (isNightMode) {
                _textView.textColor = [UIColor whiteColor];
                _textView.backgroundColor = [UIColor blackColor];
        }else{
            
                _textView.textColor = [UIColor blackColor];
                _textView.backgroundColor = [UIColor whiteColor];
        }
        
        // Increase the current offset
        currentXOffset += CGRectGetWidth(textViewFrame);
        
        // And find the index of the glyph we've just rendered
        lastRenderedGlyph = NSMaxRange([_layoutManager glyphRangeForTextContainer:textContainer]);
        
        //NSRange glyphRange = [self.layoutManager glyphRangeForTextContainer:textContainer];

        
    }
    
    // Need to update the scrollView size
    CGSize contentSize = CGSizeMake(currentXOffset, CGRectGetHeight(self.scrollView.bounds));
    self.scrollView.contentSize = contentSize;

    
}


- (void)textViewDidChangeSelection:(UITextView *)textView {
    
    UITextRange *selectedRange = [textView selectedTextRange];
    NSString *selectedText = [textView textInRange:selectedRange];
    NSLog(@"selected text is %@",selectedText);
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

    for (UITextView*tv in self.scrollView.subviews) {
        [tv removeFromSuperview];
    }
    
}



- (void)swipeLeftAction:(id)ignored
{
    
    if (_pageNumber < [self._ePubContent._spine count]-1 ) {


        CATransition *transition = [CATransition animation];
        transition.type = kCATransitionMoveIn;
        [transition setDelegate:self];
        transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        transition.duration = 0.5;
        transition.subtype = kCATransitionFromBottom;
        
  
        
    

    //[_textView reload];
    _pageNumber++;
    [self loadPage];
    [[self.textView layer] addAnimation:transition forKey:@"next"];

    }
    for (UITextView*tv in self.scrollView.subviews) {
        [tv removeFromSuperview];
    }

}



- (IBAction)prev:(id)ignored{
    
    if (_pageNumber >0 ) {

        CATransition *transition = [CATransition animation];
        transition.type = kCATransitionPush;
        [transition setDelegate:self];
        transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        transition.fillMode = kCAFillModeBoth;
        transition.duration = 0.5;
        transition.subtype = kCATransitionFromLeft;

    
    
   // [_webview reload];
    _pageNumber--;
    [self loadPage];
        [[self.scrollView layer] addAnimation:transition forKey:@"prev"];
        [self.scrollView setContentOffset:CGPointMake(0, self.scrollView.contentOffset.y) animated:NO];

        for (UITextView*tv in self.scrollView.subviews) {
            [tv removeFromSuperview];
        }
    }
    
}



- (IBAction)next:(id)ignored{
    
    if (_pageNumber < [self._ePubContent._spine count]-1 ) {

    
        CATransition *transition = [CATransition animation];
        transition.type = kCATransitionPush;
        transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        transition.fillMode = kCAFillModeBoth;
        transition.duration = 0.5;
        transition.subtype = kCATransitionFromRight;    //[_webview reload];
        _pageNumber++;
        [self loadPage];
        [[self.scrollView layer] addAnimation:transition forKey:@"next"];
        [self.scrollView setContentOffset:CGPointMake(0, self.scrollView.contentOffset.y) animated:NO];

        for (UITextView*tv in self.scrollView.subviews) {
            [tv removeFromSuperview];
        }
    }
    else{
     
        NSLog(@"You've reached the end");

    }

    
}


- (IBAction)plusA:(id)sender{
    
    textFontSize = (textFontSize < 50) ? textFontSize +2 : textFontSize;
    [self.textView setFont:[UIFont systemFontOfSize:textFontSize]];
    
    [self loadPage];
}



- (IBAction)minusA:(id)sender{
    textFontSize = (textFontSize > 14) ? textFontSize -2 : textFontSize;
   [self.textView setFont:[UIFont systemFontOfSize:textFontSize]];

    [self loadPage];

}


- (IBAction)day:(id)sender{
    isNightMode = NO;
    [self loadPage];
}



- (IBAction)night:(id)sender{
    isNightMode = YES;
    [self loadPage];
}


- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    
    float edge = scrollView.contentOffset.x + scrollView.frame.size.width;
    if (edge >= scrollView.contentSize.width) {
        
        NSLog(@"end");
    }
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

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator{
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [self loadPage];

}

//- (void)textTapped:(UITapGestureRecognizer *)recognizer
//{
//    UITextView *textView = (UITextView *)recognizer.view;
//    
//    // Location of the tap in text-container coordinates
//    
//    NSLayoutManager *layoutManager = textView.layoutManager;
//    CGPoint location = [recognizer locationInView:textView];
//    location.x -= textView.textContainerInset.left;
//    location.y -= textView.textContainerInset.top;
//    
//    // Find the character that's been tapped on
//    
//    NSUInteger characterIndex;
//    characterIndex = [layoutManager characterIndexForPoint:location
//                                           inTextContainer:textView.textContainer
//                  fractionOfDistanceBetweenInsertionPoints:NULL];
//    
//    if (characterIndex < textView.textStorage.length) {
//        
//        NSRange range;
//      //  id value = [textView.attributedText attribute:@"myCustomTag" atIndex:characterIndex effectiveRange:&range];
//        
//        // Handle as required...
//        
//        NSLog(@"%d, %d", range.location, range.length);
//        
//    }
//}


@end
