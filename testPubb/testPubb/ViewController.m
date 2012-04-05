//
//  ViewController.m
//  testPubb
//
//  Created by Shrutesh on 07/02/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "ViewController.h"
#import "ZipArchive.h"


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
    
    for (id subview in _webview.subviews)
        if ([[subview class] isSubclassOfClass: [UIScrollView class]])
            ((UIScrollView *)subview).bounces = NO;
    
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self  action:@selector(swipeRightAction:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRight.delegate = self;
    [_webview addGestureRecognizer:swipeRight];
    
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeftAction:)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeft.delegate = self;
    [_webview addGestureRecognizer:swipeLeft];

    textFontSize = 100;
    
  
}



/*Function Name : unzipAndSaveFile
 *Return Type   : void
 *Parameters    : nil
 *Purpose       : To unzip the epub file to documents directory
 */

- (void)unzipAndSaveFile{
	
	ZipArchive* za = [[ZipArchive alloc] init];
	if( [za UnzipOpenFile:[[NSBundle mainBundle] pathForResource:_strFileName ofType:@"epub"]] ){
		
		NSString *strPath=[NSString stringWithFormat:@"%@/UnzippedEpub",[self applicationDocumentsDirectory]];
		//Delete all the previous files
		NSFileManager *filemanager=[[NSFileManager alloc] init];
		if ([filemanager fileExistsAtPath:strPath]) {
			
			NSError *error;
			[filemanager removeItemAtPath:strPath error:&error];
		}
		filemanager=nil;
		//start unzip
		BOOL ret = [za UnzipFileTo:[NSString stringWithFormat:@"%@/",strPath] overWrite:YES];
		if( NO==ret ){
			// error handler here
			UIAlertView *alert=[[UIAlertView alloc] initWithTitle:@"Error"
														  message:@"An unknown error occured"
														 delegate:self
												cancelButtonTitle:@"OK"
												otherButtonTitles:nil];
			[alert show];
			alert=nil;
		}
		[za UnzipCloseFile];
	}					
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
    
    [_webview reload];
    _pageNumber--;
    [self loadPage];
       

}



- (void)swipeLeftAction:(id)ignored
{

    [_webview reload];
    _pageNumber++;
    [self loadPage];
    


}



- (IBAction)swipeRightAction1:(id)ignored{
    
    [_webview reload];
    _pageNumber--;
    [self loadPage];
    
    
}



- (IBAction)swipeLeftAction1:(id)ignored
{
    
    [_webview reload];
    _pageNumber++;
    [self loadPage];
    
    
    
}


-(IBAction)plusA:(id)sender{
    
    NSUserDefaults *userDefaults1 = [NSUserDefaults standardUserDefaults];
    [userDefaults1 setBool:YES forKey:@"btnM2"];
    [userDefaults1 synchronize];
    
    textFontSize = (textFontSize < 140) ? textFontSize +2 : textFontSize;
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%d%%'", textFontSize];
    [_webview stringByEvaluatingJavaScriptFromString:jsString];
    
}



-(IBAction)minusA:(id)sender{
    
    NSUserDefaults *userDefaults1 = [NSUserDefaults standardUserDefaults];
    [userDefaults1 setBool:NO forKey:@"btnM2"];
    [userDefaults1 synchronize];
    
    textFontSize = (textFontSize > 100) ? textFontSize -2 : textFontSize;
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%d%%'", textFontSize];
    [_webview stringByEvaluatingJavaScriptFromString:jsString];

}


-(IBAction)day:(id)sender{
    
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:YES forKey:@"btnM1"];
    [userDefaults synchronize];
    
    [_webview setOpaque:NO];
    [_webview setBackgroundColor:[UIColor whiteColor]];
    NSString *jsString2 = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextFillColor= 'black'"];
    [_webview stringByEvaluatingJavaScriptFromString:jsString2];
   
}



-(IBAction)night:(id)sender{

    NSUserDefaults *userDefaults2 = [NSUserDefaults standardUserDefaults];
     [userDefaults2 setBool:NO forKey:@"btnM1"];
    [userDefaults2 synchronize];
    
    [_webview setOpaque:NO];
    [_webview setBackgroundColor:[UIColor blackColor]];
    NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextFillColor= 'white'"];
    [_webview stringByEvaluatingJavaScriptFromString:jsString];
    
}


- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType{
    
    return YES;
    
}


- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    
    
    NSUserDefaults *menuUserDefaults = [NSUserDefaults standardUserDefaults];

    if([menuUserDefaults boolForKey:@"btnM1"]){
        [_webview setOpaque:NO];
        [_webview setBackgroundColor:[UIColor whiteColor]];
        NSString *jsString2 = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextFillColor= 'black'"];
        [_webview stringByEvaluatingJavaScriptFromString:jsString2];
    
    }
    
    else{
        [_webview setOpaque:NO];
        [_webview setBackgroundColor:[UIColor blackColor]];
        NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextFillColor= 'white'"];
        [_webview stringByEvaluatingJavaScriptFromString:jsString];
    
    }
    
    NSUserDefaults *menuUserDefaults2 = [NSUserDefaults standardUserDefaults];
    
    if([menuUserDefaults2 boolForKey:@"btnM2"]){
       
        textFontSize = (textFontSize < 140) ? textFontSize +2 : textFontSize;
        NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%d%%'", textFontSize];
        [_webview stringByEvaluatingJavaScriptFromString:jsString];
        
    }
    
    else{
              
        textFontSize = (textFontSize > 100) ? textFontSize -2 : textFontSize;
        NSString *jsString = [[NSString alloc] initWithFormat:@"document.getElementsByTagName('body')[0].style.webkitTextSizeAdjust= '%d%%'", textFontSize];
        [_webview stringByEvaluatingJavaScriptFromString:jsString];
        
    }
    
    
    
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
    
    int resultCount = [self stringHighlight:searchBar.text];
    
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



- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
 
     [_webview reload];
       return YES;
}

@end
