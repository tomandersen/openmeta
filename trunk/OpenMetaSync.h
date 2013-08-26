//
//  OpenMetaSync.h
//  yep
//
//  Created by Tom Andersen on 2012-08-07.
//
//

#import <Foundation/Foundation.h>

// class for single file bullk backup
@interface OpenMetaSync : NSOperation
{
	NSArray* files;
	NSDictionary* returnDict;
    NSArray* readItems;
    BOOL aggressiveRestore;
}

@property (retain) NSArray*  files;
@property (retain) NSDictionary*  returnDict;
@property (retain) NSArray*  readItems;
@property (readwrite) BOOL aggressiveRestore;

// the first file is used for input, after syncing current tags and ratings written to all locations passed
+(void)syncWithFiles:(NSArray*)inFilePaths aggressiveRestore:(BOOL)inAggressiveRestore;

@end

