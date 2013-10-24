//
//  AppDelegate.m
//  OpenMetaSetup
//
//  Created by Tom Andersen on 11-10-17.
//  Copyright (c) 2011 Keaten House, Ltd. All rights reserved.
//

#import "AppDelegate.h"
#import "OpenMeta.h"
#import "OpenMetabackup.h"

@implementation AppDelegate

@synthesize window = _window;

- (void)dealloc
{
    [super dealloc];
}

//----------------------------------------------------------------------
//	registerOMAttributes
//
//				Easiest to ususally call registerUsualOMAttributes
//
//	Purpose:	This should be called by any application that uses OpenMeta, to register the attributes that you are using with spotlight.
//				Spotlight may not 'know' about say kMDItemOMUserTags unless you set a file with some user tags so that the OpenMeta spotlight importer can
//				run on this one (fairly hidden file), which then tells spotlight to look up and use all the relevant 'stuff':
//
//				For the kMDItemOMUserTags example:
//				kMDItemOMUserTags is an array of nsstrings. So create one, tags = [NSArray arrayWithObjects:@"foo", @"bar"], and make a dictionary entry for it:
//				[myAttributeDict setObject:tags forKey:@"kMDItemOMUserTags"];
//		
//				Then add other attributes that your app uses:
//				[myAttributeDict setObject:[NSNumber numberWithFloat:2] forKey:(NSString*)kMDItemStarRating];

//				Then register the types:
//				[OpenMeta registerOMAttributes:myAttributeDict forAppName:@"myCoolApp"];
//
//				Doing all of this is necc to get searches like 'starrating:>4' working in spotlight, and for the item 'Rated' to show up 
//				in the Finder (and other apps) when you do a Find and then look under the little 'Other' menu. 
//
//				All this routine does is make a file that the importer will import, then let mdimport go at it, then remove the file. 
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/21 
//
// The version here uses our directory to register the open meta stuff, which is better for the apple store. 
//
//----------------------------------------------------------------------
-(void)registerOMAttributes:(NSDictionary*)typicalAttributes;
{
	// create the file: - directory - spotlight will still import it.
	NSString* path = [@"~/Documents" stringByExpandingTildeInPath];
	[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
	
	// the spotlight plugin is registered to only import files with openmetaschema as an extension
	path = [path stringByAppendingPathComponent:@"registerFile.openmetaschema"];
	
	[typicalAttributes writeToFile:path atomically:YES];
	
	// simpler - just leave mdimport a few seconds to get to the file. 
	[self performSelector:@selector(removeSchemaFileAndTerminate:) withObject:path afterDelay:1.0];
}

-(void)removeSchemaFileAndTerminate:(NSString*)path;
{
	if ([path rangeOfString:@"schemaregister"].location != NSNotFound) // make sure some error does not see us erasing lots of stuff 
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];

    NSRunAlertPanel(@"OpenMeta backups enabled", @"You only need to run this app once, then keep it on your computer. It does not need to be running all the time", @"Quit", nil, nil);
    
    [NSApp terminate:nil];
}

//----------------------------------------------------------------------
//	registerUsualOMAttributes
//
//	Purpose:	Call on launch to be sure that the OpenMeta spotlgight importer that you included in your app bundle 
//				gets registered. If you are  doing a command line thing, or some tool where you know the person has the OpenMeta spotlight plugin installed,
//				then you don't need this. 
//
//				It makes sure that typing a search like 'tag:goofy' will work in the Apple default spotlight search, or in the Finder.
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/05/19 
//
//----------------------------------------------------------------------
-(void)registerUsualOMAttributes;
{
	NSDictionary* stuffWeUse = [NSDictionary dictionaryWithObjectsAndKeys:
								[NSArray arrayWithObjects:@"openMeta1", @"openMeta2", nil], @"kMDItemOMUserTags",
								[NSDate date], @"kMDItemOMUserTagTime",
								[NSDate date], @"kMDItemOMDocumentDate",
								[NSNumber numberWithBool:YES], @"kMDItemOMManaged",
								[NSArray arrayWithObjects:@"bookmark1", @"bookmark2", nil], @"kMDItemOMBookmarks",
								nil];
    
	[self registerOMAttributes:stuffWeUse];
}

// For the apple app store, only use open meta prefs file if the file is there...
-(void)ensureOpenMetaPrefsFile;
{
	NSString* prefFilePath = [@"~/Library/Preferences/com.openmeta.shared.plist" stringByExpandingTildeInPath];
	if (![[NSFileManager defaultManager] fileExistsAtPath:prefFilePath])
    {
        [[NSDictionary dictionary] writeToFile:prefFilePath atomically:YES];
    }
}



- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
	NSString* path = [@"~/Library/Application Support/OpenMeta/" stringByExpandingTildeInPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    
    [self ensureOpenMetaPrefsFile];
    
    [self registerUsualOMAttributes];
    
}

@end
