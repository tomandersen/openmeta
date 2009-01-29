//
//  OpenMetaBackup.h
//  Fresh
//
//  Created by Tom Andersen on 26/01/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface OpenMetaBackup : NSObject {

}

// individual file handling:
// ---------------------------

// backup is called automatically each time you set any attribute with kOM*, so you actually don't have to call this.
+(void)backupMetadata:(NSString*)inPath;

// restore is called for you ONLY on tags and ratings. If you are using OpenMeta and not using tags or ratings, you need to call this first, in case the 
// OpenMeta data has been deleted.
+(void)restoreMetadata:(NSString*)inPath;


// Restoring all metadata 
// ---------------------------
// call this to restore all backed up meta data. Call when? On every launch may be 'too much' for apps that are launched a lot. 
// it does run in a thread, though..
+(void)restoreAllMetadataOnBackgroundThread;

// shutting down OpenMeta backup and restore systems 
// ---------------------------

// call this on quit, to leave time for any restores to safely, possibly, partially finish
+(void)appIsTerminating;



@end
