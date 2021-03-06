//
//  ViewController.m
//  testPubb
//
//  Created by Shrutesh on 07/02/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "Constants.h"

#import "ViewController.h"
#import "SSZipArchive.h"


@implementation ViewController
@synthesize _ePubContent;
@synthesize _rootPath;
@synthesize _strFileName;
@synthesize _webview;

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
    [_webview setBackgroundColor:[UIColor clearColor]];
    [self unzipAndSaveFile];
	_xmlHandler=[[XMLHandler alloc] init];
	_xmlHandler.delegate=self;
	[_xmlHandler parseXMLFileAt:[self getRootFilePath]];
    
    
    
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self  action:@selector(swipeRightAction:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRight.delegate = self;
    [_webview addGestureRecognizer:swipeRight];
    
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeftAction:)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeft.delegate = self;
    [_webview addGestureRecognizer:swipeLeft];

    textFontSize = 120;
    textColor = [[NSString alloc]init];
    backgroundColor = [[NSString alloc]init];
  
}



/*Function Name : unzipAndSaveFile
 *Return Type   : void
 *Parameters    : nil
 *Purpose       : To unzip the epub file to documents directory
 */

- (void)unzipAndSaveFile{
	
    NSString *zipPath = [[NSBundle mainBundle] pathForResource:@"moby-dick-20120118" ofType:@"epub"];
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
		
		//[filemanager release];
		//filemanager=nil;
		
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
	[_webview loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:_pagesPath]]];
	//set page number
	_pageNumberLbl.text=[NSString stringWithFormat:@"%d",_pageNumber+1];

}





- (void)swipeRightAction:(id)ignored{
    
    if (_pageNumber >0 ) {
  
    
    CATransition *animation = [CATransition animation];
    [animation setDelegate:self];
    [animation setDuration:0.5f];
    [animation setType:@"pageUnCurl"];
    
    //[animation setType:kcat]; 
    [animation setSubtype:@"fromRight"];
    

    [_webview reload];
    _pageNumber--;
    [self loadPage];
    [[_webview layer] addAnimation:animation forKey:@"WebPageUnCurl"]; 
  }

}



- (void)swipeLeftAction:(id)ignored{
    
    if (_pageNumber < [self._ePubContent._spine count]-1 ) {

    CATransition *animation = [CATransition animation];
    [animation setDelegate:self];
    [animation setDuration:0.5f];
    [animation setType:@"pageCurl"];
    
    //[animation setType:kcat]; 
    [animation setSubtype:@"fromRight"];
    

    

    [_webview reload];
    _pageNumber++;
    [self loadPage];
    
    [[_webview layer] addAnimation:animation forKey:@"WebPageCurl"]; 

    }

}



- (IBAction)prev:(id)ignored{
    
    if (_pageNumber >0 ) {

    CATransition *animation = [CATransition animation];
    [animation setDelegate:self];
    [animation setDuration:0.5f];
    [animation setType:@"pageUnCurl"];
    [animation setSubtype:@"fromRight"];
    
    
    [_webview reload];
    _pageNumber--;
    [self loadPage];
    [[_webview layer] addAnimation:animation forKey:@"WebPageUnCurl"]; 
    
    }
}



- (IBAction)next:(id)ignored{
    
    if (_pageNumber < [self._ePubContent._spine count]-1 ) {

    
    CATransition *animation = [CATransition animation];
    [animation setDelegate:self];
    [animation setDuration:0.5f];
    [animation setType:@"pageCurl"];
    [animation setSubtype:@"fromRight"];
    [_webview reload];
    _pageNumber++;
    [self loadPage];
    
    [[_webview layer] addAnimation:animation forKey:@"WebPageCurl"]; 

    }
    
    
}


- (IBAction)plusA:(id)sender{
    
    
    textFontSize = (textFontSize < 140) ? textFontSize +2 : textFontSize;
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%lu%%'", (unsigned long)textFontSize];
    [_webview stringByEvaluatingJavaScriptFromString:jsString];
    
}



- (IBAction)minusA:(id)sender{
    
    textFontSize = (textFontSize > 100) ? textFontSize -2 : textFontSize;
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%lu%%'", (unsigned long)textFontSize];
    [_webview stringByEvaluatingJavaScriptFromString:jsString];

}


- (IBAction)day:(id)sender{
    
    backgroundColor = @"white";
    textColor = @"black";
    
    NSString *jsString1 = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].bgColor= '%@'",backgroundColor];
    [_webview stringByEvaluatingJavaScriptFromString:jsString1];

    
    NSString *jsString2 = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextFillColor= '%@'",textColor];
    [_webview stringByEvaluatingJavaScriptFromString:jsString2];
   

}



- (IBAction)night:(id)sender{

    
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        
        backgroundColor = @"black";
        textColor = @"white";
        
        NSString *jsString1 = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].bgColor= '%@'",backgroundColor];
        [_webview stringByEvaluatingJavaScriptFromString:jsString1];
        
        
        NSString *jsString2 = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextFillColor= '%@'",textColor];
        [_webview stringByEvaluatingJavaScriptFromString:jsString2];
        
    } completion:^(BOOL finished) {
        
       
   
    }];
    

   
}


- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType{
    
    return YES;
    
}



- (void)webViewDidFinishLoad:(UIWebView *)webView{
  

        NSString *jsString1 = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextFillColor= '%@'",textColor];
        [webView stringByEvaluatingJavaScriptFromString:jsString1];
    
        NSString *jsString2 = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].bgColor= '%@'",backgroundColor];
        [webView stringByEvaluatingJavaScriptFromString:jsString2];
    
        textFontSize = (textFontSize > 100) ? textFontSize -2 : textFontSize;
        NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%lu%%'", (unsigned long)textFontSize];
        [webView stringByEvaluatingJavaScriptFromString:jsString];
    
    
    
   // NSString *insertRule1 = [NSString stringWithFormat:@"addCSSRule('html', 'padding: 0px; height: %fpx; -webkit-column-gap: 0px; -webkit-column-width: %fpx; overflow: hidden;')", self.view.bounds.size.height, _webview.bounds.size.width];
   // NSString *insertRule2 = [NSString stringWithFormat:@"addCSSRule('p', 'text-align: justify;')"];
    
    [webView stringByEvaluatingJavaScriptFromString:SHEET];
    [webView stringByEvaluatingJavaScriptFromString:ADDCSSRULE];
   // [webView stringByEvaluatingJavaScriptFromString:insertRule1];
  //  [webView stringByEvaluatingJavaScriptFromString:insertRule2];
    

    webView.scrollView.showsHorizontalScrollIndicator = NO;
    webView.scrollView.scrollEnabled = YES;
    
}

/*
 Search A string inside UIWebView with the use of the javascript function
 */

- (NSInteger)stringHighlight:(NSString*)str
{
    // The JS File   
    NSString *filePath  = [[NSBundle mainBundle] pathForResource:@"UIWebViewSearch" ofType:@"js" inDirectory:@""];
    NSData *fileData    = [NSData dataWithContentsOfFile:filePath];
    NSString *jsString  = [[NSMutableString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
    [_webview stringByEvaluatingJavaScriptFromString:jsString];

    
    // The JS Function
    NSString *startSearch   = [NSString stringWithFormat:@"uiWebview_HighlightAllOccurencesOfString('%@')",str];
    [_webview stringByEvaluatingJavaScriptFromString:startSearch];
    NSString *result        = [_webview stringByEvaluatingJavaScriptFromString:@"uiWebview_SearchResultCount"];
    return [result integerValue];
}



- (void)removeHighlights{
    
   
    [_webview stringByEvaluatingJavaScriptFromString:@"uiWebview_RemoveAllHighlights()"];  // to remove highlight
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    
    [self removeHighlights];
    
    NSUInteger resultCount = [self stringHighlight:searchBar.text];
    
    // If no occurences of string, show alert message
    if (resultCount <= 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"LOL!" 
                                                        message:[NSString stringWithFormat:@"Type again and You might find it: %@", searchBar.text]
                                                       delegate:nil 
                                              cancelButtonTitle:@"Ok" 
                                              otherButtonTitles:nil];
        [alert show];
        //[alert release];
    }
    
    // remove kkeyboard
    [searchBar resignFirstResponder];
}


- (IBAction)removeHighlightsB{
    
    [_webview stringByEvaluatingJavaScriptFromString:@"uiWebview_RemoveAllHighlights()"];  // to remove highlight
    [self.view endEditing:YES];
}





- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}



//- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
//{
//    // Return YES for supported orientations
// 
//     [_webview reload];
//       return YES;
//}

@end
