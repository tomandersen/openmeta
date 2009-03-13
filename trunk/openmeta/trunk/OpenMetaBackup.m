//
//  OpenMetaBackup.m
//  Fresh
//
//  Created by Tom Andersen on 26/01/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#include <sys/xattr.h>
#include <sys/time.h>
#include <sys/stat.h>

#import "OpenMeta.h"
#import "OpenMetaBackup.h"

@interface OpenMetaBackup (Private)
+(NSString*)fsRefToPath:(FSRef*)inRef;
+(NSData*)aliasDataForFSRef:(FSRef*)inRef;
+(NSData*) aliasDataForPath:(NSString*)inPath;
+(NSString*) resolveAliasDataToPath:(NSData*)inData osErr:(OSErr*)outErr;
+(NSString*) backupPathForMonthsBeforeNow:(int)inMonthsBeforeNow;
+(void)setBackupStamp:(NSString*)inPath;
+(NSString*) backupPathForItem:(NSString*)inPath;
+(void)restoreMetadataSearchForFile:(NSString*)inPath;
+(NSString*)hashString:(NSString*)inString;
+(NSThread*)backupThread;
+(void)enqueueBackupItem:(NSString*)inPath;
+(BOOL)hasCorrectBackupStamp:(NSString*)inPath;
+(NSString*)truncatedPathComponent:(NSString*)aPathComponent;
+(void)backupMetadataNow:(NSString*)inPath;
+(void)restoreMetadata:(NSDictionary*)buDict toFile:(NSString*)inFile;
+(BOOL)backupThreadIsBusy;
+(BOOL)openMetaThreadIsBusy;
@end

@implementation OpenMetaBackup

//----------------------------------------------------------------------
//	OpenMetaBackup
//
//	OpenMetaBackup - the idea is to store a backup of all user entered meta data - eg tags, ratings, etc. 
//					these are backed up to a folder in the application support folder Library/Application Support/OpenMeta/2009/1/lotsOfbackupfiles.omback
//
//					When tags, etc are about to be set on a document and the document has no openmeta data set on it, we check to make sure that it is actually an empty doc, 
//					and not some doc that has had the metadata stripped away. 
//
//					Currently, any setting of an kOM* key will cause a backup to happen. Restore is attempted for Tags and ratings only - if you need to restore, then you have to call it yourself,
//					which is easy.
//	
//
//
//  Created by Tom Andersen on 2009/01/26 
//
//----------------------------------------------------------------------


#pragma mark backup and restore openmeta data

//----------------------------------------------------------------------
//	backupMetadata
//
//	Purpose:	backs up metadata for the passed path. 
//				can be called many times in a row, will coalesce backup requests into one write
//	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/26 
//
//----------------------------------------------------------------------
+(void)backupMetadata:(NSString*)inPath;
{
	if ([inPath length] == 0)
		return;
	
	// backups are handled by a thread that has a queue
	NSThread* buThread = [self backupThread];  	
	[self performSelector:@selector(enqueueBackupItem:) onThread:buThread withObject:inPath waitUntilDone:NO];
}

//----------------------------------------------------------------------
//	restoreMetadata (public call)
//
//	Purpose:	if there is openmeta data of any sort set on the file, this call returns without doing anything.
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/26 
//
//----------------------------------------------------------------------
+(void)restoreMetadata:(NSString*)inPath;
{
	if ([self hasCorrectBackupStamp:inPath])
		return;
	
	// if a file has no backup stamp, then either has never been tagged, or some process has stripped off the tags. At this point we can't tell which, so we search for a restore.
	[self restoreMetadataSearchForFile:inPath];
	
	// the process of looking for a backup is long and slow, so we ensure that there is a backup stamp set, even if the user does not set any meta data - which is fine
	[self setBackupStamp:inPath];
}

#pragma mark backup paths and stamps

//----------------------------------------------------------------------
//	calculateBackupStamp
//
//	Purpose:	the backup stap for the file - what the stamp should be for the passed path - NOT what is stored on disk
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(NSString*)calculateBackupStamp:(NSString*)inPath;
{
	NSString* fileName = [self truncatedPathComponent:[inPath lastPathComponent]]; 
	NSString* fileNameHash = [self hashString:[inPath lastPathComponent]]; // hash the name
	NSString* folderHash = [self hashString:[inPath stringByDeletingLastPathComponent]]; // hash is for the parent folder - this allows for searching for renamed files in some cases...
	NSString* backupStamp = [fileName stringByAppendingString:@"__"];
	backupStamp = [backupStamp stringByAppendingString:fileNameHash];
	backupStamp = [backupStamp stringByAppendingString:@"__"];
	backupStamp = [backupStamp stringByAppendingString:folderHash];
	
	return backupStamp;
}	

+(NSString*)getBackupStamp:(NSString*)inPath;
{
	return [OpenMeta getXAttrMetaData:@"kBackupStampOM" path:inPath error:nil];
}

//----------------------------------------------------------------------
//	hasBackupStamp
//
//	Purpose: return YES if this item has some openmeta data set on it. It does this by checking for a backup stamp.
//			 if the backup stamp is old or inaccurate, a new backup is called for.
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(BOOL)hasCorrectBackupStamp:(NSString*)inPath;
{
	NSString* currentBackupStamp = [self getBackupStamp:inPath];
	if (currentBackupStamp == nil)
		return NO;
	
	// if the item was moved, renamed, etc, then the backup stamp will be wrong - we take this opportunity to fix that:
	NSString* backupStamp = [self calculateBackupStamp:inPath];
	if ([backupStamp isEqualToString:currentBackupStamp])
		return YES;
	
	return NO;
}


//----------------------------------------------------------------------
//	setBackupStamp
//
//	Purpose:	returns the backup stamp for the item. After this call, it will also be set 
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(void)setBackupStamp:(NSString*)inPath;
{
	if ([self hasCorrectBackupStamp:inPath])
		return;
	
	// mark this file as being in the openmeta system on this machine - its backup stamp
	// I set the backup stamp as indexible, but not to be backed up (- it is not kOM* - so no backup).
	// I plan on making an automated, efficient backup that uses this mechanism - I can eliminate 
	// items to backup based on the results of an MDQuery. That is the plan anyways.
	[OpenMeta setXAttrMetaData:[self calculateBackupStamp:inPath] metaDataKey:@"kBackupStampOM" path:inPath];
}



//----------------------------------------------------------------------
//	backupPathForMonthsBeforeNow
//
//	Purpose:	I store backups in month - dated folders. Once a month is over, i won't write any new files in that month. (there are very small time zone issues)
//				Thus in the future, an optimized 'old' month searching db / fast access could be made...
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(NSString*) backupPathForMonthsBeforeNow:(int)inMonthsBeforeNow;
{
//+    NSString *libraryDir = [NSSearchPathForDirectoriesInDomains( NSApplicationSupportDirectory,
//                                                                  NSUserDomainMask,
//                                                                  YES ) objectAtIndex:0];
	NSString* backupPath = @"~/Library/Application Support/OpenMeta/backups"; // i guess this should be some messy cocoa special folder lookup for application support
	backupPath = [backupPath stringByExpandingTildeInPath];
	
	NSCalendarDate* todaysDate = [NSCalendarDate calendarDate];
	
	int theYear = [todaysDate yearOfCommonEra];
	int theMonth = [todaysDate monthOfYear]; // 1 - 12 returned
	
	// adjust:
	theMonth -= inMonthsBeforeNow;
	while (theMonth < 1)
	{
		theMonth += 12;
		theYear -= 1;
	}
	
	backupPath = [backupPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d", theYear]];
	backupPath = [backupPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d", theMonth]];
	
	return backupPath;
}

//----------------------------------------------------------------------
//	currentBackupPath
//
//	Purpose:	The path to the folder for the current months backups. Directory created if needed.
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(NSString*) currentBackupPath;
{
	NSString* bupath = [self backupPathForMonthsBeforeNow:0];
	if (![[NSFileManager defaultManager] fileExistsAtPath:bupath])
		[[NSFileManager defaultManager] createDirectoryAtPath:bupath withIntermediateDirectories:YES attributes:nil error:nil];
	
	return bupath;
}

//----------------------------------------------------------------------
//	truncatedPathComponent
//
//	Purpose:	backupStamps and backupfiles need to have filenames that are manageable. This truncs filenames by cutting in the middle.
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(NSString*)truncatedPathComponent:(NSString*)aPathComponent;
{
	if ([aPathComponent length] > 40)
	{
		// we need to trunc the same way every time... - take first 20 plus last twenty
		aPathComponent = [[aPathComponent substringToIndex:20] stringByAppendingString:[aPathComponent substringFromIndex:[aPathComponent length] - 20]];
	}
	return aPathComponent;
}


//----------------------------------------------------------------------
//	backupPathForItem
//
//	Purpose:	place to write backup file for passed item
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(NSString*) backupPathForItem:(NSString*)inPath;
{
	NSString* bupath = [self currentBackupPath];

	// now create the special name that allows lookup:
	// our file names are: the filename.extension__hash.omback
	NSString* buFileName = [self calculateBackupStamp:inPath];
	buFileName = [buFileName stringByAppendingString:@".omback"];
	return [bupath stringByAppendingPathComponent:buFileName];
}

#pragma mark restore all metadata - bulk 
BOOL gOMRestoreThreadBusy = NO;
BOOL gOMIsTerminating = NO;

//----------------------------------------------------------------------
//	restoreMetadataFromBackupFileIfNeeded
//
//	Purpose:	restores kOM* data
//
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(int)restoreMetadataFromBackupFileIfNeeded:(NSString*)inPathToBUFile;
{
	NSDictionary* backupContents = [NSDictionary dictionaryWithContentsOfFile:inPathToBUFile];
	if ([backupContents count] == 0)
		return 0;
	
	// if the file at the path has a backup stamp, we are good to go.
	NSString* filePath = [backupContents objectForKey:@"bu_path"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
	{
		OSErr theErr;
		filePath = [self resolveAliasDataToPath:[backupContents objectForKey:@"bu_alias"] osErr:&theErr];
		if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
			return 0; // could find no file to bu to.
	}
	
	if ([self hasCorrectBackupStamp:filePath])
		return 0;
		
	[self restoreMetadata:backupContents toFile:filePath];
	
	[self setBackupStamp:filePath];
#if KP_DEBUG
	NSLog(@"meta data repaired on %@ with %@", filePath, backupContents);
#endif
	return 1; // one file fixed up
}

//----------------------------------------------------------------------
//	restoreAllMetadataMDQuery
//
//	Purpose:	Use mdquery to make this job very much faster...
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/26 
//
//----------------------------------------------------------------------
+(void)restoreAllMetadataMDQuery:(id)arg;
{
	// run this on thread
	// 1) do query for all items with a backupStamp - organize backupstamps into dict
	// 2) loop over 12 months or more...
	// 2) read a month's worth of backups
	// 3) eliminate all ones that have backup from the list
	// 4) call restoreMetadataFromBackupFileIfNeeded on any backup files not eliminated.
	
	// Problems with this (likely accepable)
	// if user throws out a ton of files, then the metadata will attempt a reset for each item tossed.
	// You don't want to give up too easily, though, as there are files that will not be reachable now, but will be later, when the server is mounted.
	// I could easily create a known server down list, which would help with the zippyness factor..
	

}

//----------------------------------------------------------------------
//	tellUserRestoreFinished
//
//	Purpose:	will show a modal dialog when the restore is finished. 
//
//	Inputs:		you can override the strings in a localization file
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/03/11 
//
//----------------------------------------------------------------------
+(void)tellUserRestoreFinished:(NSNumber*)inNumberOfFilesRestored;
{
	NSString* title = NSLocalizedString(@"Open Meta Restore Done", @"");
	
	NSString* comments = NSLocalizedString(@"No files needed to have meta data such as tags and ratings restored.", @"");
	if ([inNumberOfFilesRestored intValue] > 0)
	{
		comments = NSLocalizedString(@"%1 files had meta data such as tags and ratings restored.", @"");
		comments = [comments stringByReplacingOccurrencesOfString:@"%1" withString:[inNumberOfFilesRestored stringValue]];
	}

// This is the only UI in the OpenMeta code. If you don't want to or can't link to UI, then define OPEN_META_NO_UI in the compiler settings. 
#if OPEN_META_NO_UI 
	NSLog(@" %@ \n %@ ", title, comments);
#else
	NSRunAlertPanel(	title,
						comments, 
						nil,
						nil,
						nil,
						nil);
#endif
}

//----------------------------------------------------------------------
//	restoreAllMetadata
//
//	Purpose:	should be run as  a 'job' on a thread to restore metadata to every file it can find that has no metadata set. 
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/26 
//
//----------------------------------------------------------------------
+(void)restoreAllMetadata:(NSNumber*)tellUserWhenDoneNS;
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	BOOL tellUserWhenDone = [tellUserWhenDoneNS boolValue];
	
	// go through files, opening up as needed the filePath metadata...
	// when i find one that needs restoring, also issue a call to add it to this month's list of edits.
	// look through the previous 12 months for data. 
	// when i find it needs restoring, also issue a call to add it to this month's list of edits.
	int count;
	int numFilesFixed = 0;
	int numFilesChecked = 0;
	for (count = 0; count < 36; count++)
	{
		NSString* backupDir = [self backupPathForMonthsBeforeNow:count];
		NSArray* fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:backupDir error:nil];
		
		// the file name and folder name in the backup file filename may be truncated:
		for (NSString* aFileName in fileNames)
		{
			// our file names have: the filename.extension__pathhash.omback
			// just plow through, restoring...
			numFilesFixed += [self restoreMetadataFromBackupFileIfNeeded:[backupDir stringByAppendingPathComponent:aFileName]];
			
			numFilesChecked++;
			
			if (!tellUserWhenDone)
				[NSThread sleepForTimeInterval:0.05]; // don't push too hard if we are running lazily (not telling the user when we are done)
			
			if (gOMIsTerminating)
			{
				[pool release];
				gOMRestoreThreadBusy = NO;
				return;
			} 
			
		}
	}

#if KP_DEBUG
	NSLog(@"%d files checked for restore", numFilesChecked);
#endif
	
	if (tellUserWhenDone)
	{
		NSNumber* numFilesFixedNS = [NSNumber numberWithInt:numFilesFixed];
		[self performSelectorOnMainThread:@selector(tellUserRestoreFinished:) withObject:numFilesFixedNS waitUntilDone:YES];
	}
	
	[pool release];
	gOMRestoreThreadBusy = NO;
}

//----------------------------------------------------------------------
//	restoreAllMetadataOnBackgroundThread
//
//	Purpose:	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(void)restoreAllMetadataOnBackgroundThread:(BOOL)tellUserWhenDone;
{
	if (gOMRestoreThreadBusy)
	{
		NSLog(@"meta data restore already running");
		return;
	}
	
	gOMRestoreThreadBusy = YES;
	NSNumber* tellUserWhenDoneNS = [NSNumber numberWithBool:tellUserWhenDone];
	[NSThread detachNewThreadSelector:@selector(restoreAllMetadata:) toTarget:self withObject:tellUserWhenDoneNS];
}

+(BOOL)restoreThreadIsBusy;
{
	return gOMRestoreThreadBusy;
}


//----------------------------------------------------------------------
//	appIsTerminating
//
//	Purpose: call this to tell restore and other functions running in the background to gracefully exit.	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(void)appIsTerminating;
{
	gOMIsTerminating = YES;
	while ([OpenMetaBackup openMetaThreadIsBusy])
		[NSThread sleepForTimeInterval:0.1];
}

//----------------------------------------------------------------------
//	openMetaThreadIsBusy
//
//	Purpose:	returns true if some backup thread is working on stuff
//
//	usage: at terminate
//	while ([OpenMetaBackup openMetaThreadIsBusy])
//		[NSThread sleepForTimeInterval:0.1];
//			
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(BOOL)openMetaThreadIsBusy;
{
	if ([self restoreThreadIsBusy] || [self backupThreadIsBusy])
		return YES;
	
	return NO;
}
#pragma mark restoring metadata
//----------------------------------------------------------------------
//	restoreMetadata
//
//	Purpose:	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(void)restoreMetadata:(NSDictionary*)buDict toFile:(NSString*)inFile;
{
	NSDictionary* omDict = [buDict objectForKey:@"omDict"];
	
	NSError* error = nil;
	for (NSString* aKey in [omDict allKeys])
	{
		id dataItem = [omDict objectForKey:aKey];
		if (dataItem)
		{
			// only set data that is not already set - the idea of a backup is only replace if missing...
			id storedObject = [OpenMeta getXAttr:aKey path:inFile error:&error];
			if (storedObject == nil)
				error = [OpenMeta setXAttr:dataItem forKey:aKey path:inFile];
		}
	}
}


//----------------------------------------------------------------------
//	restoreMetadataFromBackupFile
//
//	Purpose:	restores data to the passed path. Will only restore if the passed path matches the alias or the stored path. (we also check filename in emergency)
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(BOOL)restoreMetadataFromBackupFile:(NSString*)inPathToBUFile toFile:(NSString*)inPath;
{
	NSDictionary* backupContents = [NSDictionary dictionaryWithContentsOfFile:inPathToBUFile];
	if ([backupContents count] == 0)
		return NO;
	
	// if the path is right, then restore and return:
	if ([inPath isEqualToString:[backupContents objectForKey:@"bu_path"]])
	{
		[self restoreMetadata:backupContents toFile:inPath];
		return YES;
	}
	
	// if the alias resolves to the path, or the path is 
	OSErr theErr;
	NSString* aliasPath = [self resolveAliasDataToPath:[backupContents objectForKey:@"bu_alias"] osErr:&theErr];
	
	if ([aliasPath length] == 0)
	{
		// if the alias could not be resolved, it means that for some reason the original file is not around. This could mean for instance a file that has gone on a round trip to a subversion
		// repository, combined with a name change, or photoshop cs3 or cs4 will often kill aliases etc. 
		
		// if the file names match then we take our file as being found.
		NSString* fileNameToLookFor = [self truncatedPathComponent:[inPath lastPathComponent]];
		if ([inPath rangeOfString:fileNameToLookFor].location != NSNotFound)
		{
			[self restoreMetadata:backupContents toFile:inPath];
			return YES;
		}
	}
	else if ([[NSFileManager defaultManager] contentsEqualAtPath:aliasPath andPath:inPath])
	{
		[self restoreMetadata:backupContents toFile:inPath];
		return YES;
	}
	
	return NO;
}

//----------------------------------------------------------------------
//	restoreMetadataSearchForFile
//
//	Purpose:	This call is called when we can't find meta data for a file, which happens when a file has no metadata set on it.
//	
//	NOTE:		This call needs to be fast, as it can get called often, but it also has to be able to find metadata easily...
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(void)restoreMetadataSearchForFile:(NSString*)inPath;
{
	// look for an exact match on the previous 12 months of data. If there is one found, we are good. 
	// there exists the slim possibility that this will find the 'wrong' backup data:
	// Steps:	1) tags are assigned, so bu made
	//			2) file moved
	//			3) file has new tags added
	//			4) file loses all tags
	//			6) file is moved back to the original folder. In this case the backup will restore the tags from step 1. 
	//	I think that the above scenario is a little far fetched...
	//----------
	NSString* backupStamp = [self calculateBackupStamp:inPath];
	NSString* exactBackupFileName = [backupStamp stringByAppendingPathExtension:@"omback"];
	int count;
	for (count = 0; count < 12; count++)
	{
		NSString* backupDir = [self backupPathForMonthsBeforeNow:count];
		if ([self restoreMetadataFromBackupFile:[backupDir stringByAppendingPathComponent:exactBackupFileName] toFile:inPath])
			return; // found a backup file that looked good enough to use.
	}
	
	// filenames are trunced to 40 chars in the stamp
	NSString* fileNameToLookFor = [self truncatedPathComponent:[inPath lastPathComponent]];
	
	// look through the previous 12 months for data. 
	// when i find it needs restoring, also issue a call to add it to this month's list of edits.
	for (count = 0; count < 12; count++)
	{
		NSString* backupDir = [self backupPathForMonthsBeforeNow:count];
		NSArray* fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:backupDir error:nil];
		
		// the file name and folder name in the backup file filename may be truncated:
		for (NSString* aFileName in fileNames)
		{
			// our file names have: the filename.extension__pathhash.omback
			
			// look for a hit on name. When we see a name match, check now. 
			// for folder matches we just add to our array of ones to check.
			if ([aFileName rangeOfString:fileNameToLookFor].location != NSNotFound)
			{
				if ([self restoreMetadataFromBackupFile:[backupDir stringByAppendingPathComponent:aFileName] toFile:inPath])
					return; // found a backup file that looked good enough to use. (ie alias resolve worked)
			}
			
		}
	}
	
	// if all else fails - do we look through every file until we get a hit? - perhaps look through files for a second or so? 
	
	// one thing we could do is look through all the items that have the same parent folder hash as the passed path,
	// then see if any of the aliases point to the item. If any do, then use that, but if we find some files with aliases that don't resolve,
	// then we could ask the user if that meta data is the correct one/pick from a list...?
	
	
	// note that editing a moved file in photoshop will render the alias useless. The path is also useless. 
	// moving a renamed, tagged file, and then editing it in photoshop will lose tags. 
	
	// that would be slow. Perhaps we just give up. Maybe the restore all will do the trick...
	
}

//----------------------------------------------------------------------
//	ELFHash
//
//	Purpose:	hash to use for strings. Note that this has to be constant, 
//				and always 32 bit number, which is why the cocoa hash on the string will not work for us.	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
unsigned int ELFHash(const char* str, unsigned int len)
{
   unsigned int hash = 0;
   unsigned int x    = 0;
   unsigned int i    = 0;

   for(i = 0; i < len; str++, i++)
   {
      hash = (hash << 4) + (*str);
      if((x = hash & 0xF0000000L) != 0)
      {
         hash ^= (x >> 24);
      }
      hash &= ~x;
   }

   return hash;
}

//----------------------------------------------------------------------
//	hashString
//
//	Purpose:	has as number string
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(NSString*)hashString:(NSString*)inString;
{
	// don't use built in hash - it is 64 bit on 64bit compiles, and is not guaranteed to be constant across restart (ie system updates)
	// unsigned int is always 32 bit
	const char* fileSysRep = [inString fileSystemRepresentation];
	
	unsigned int hashNumber = ELFHash(fileSysRep, strlen(fileSysRep));
	return [[NSNumber numberWithUnsignedInt:hashNumber] description];
}

#pragma mark thread that does all the backups
//----------------------------------------------------------------------
//	backupThreadMain
//
//	Purpose:	The idea of the backup thread is so that one can call backupMetadata (the public api)
//				lots (like hundreds) of times over a short period, and have the actual backup file created just once (or a small number of times).
//				
//				The slight disadvantage is that rapidly moving files may not get their metadata backed up. (path changes before we get there to backup the file)
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(void)keepAlive:(NSTimer*)inTimer;
{
	// this keeps run loop running
}

// this array to only be accessed in the backupThread.
NSMutableArray* gOMBackupQueue = nil;
BOOL gOMBackupThreadBusy = NO;

+(void)backupThreadMain:(NSThread*)inThread;
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	
	// create array that holds all pending backups. Note that this array can only be accessed from this thread, as I don't lock it.
	gOMBackupQueue = [[NSMutableArray alloc] init];
	
	NSRunLoop* theRL = [NSRunLoop currentRunLoop];
	
	// this timer keeps the thread running. Seemed simpler than an input source
	[NSTimer scheduledTimerWithTimeInterval:86400 target:self selector:@selector(keepAlive:) userInfo:nil repeats:YES];
	
	// use autorelease pools around each event
	while (![inThread isCancelled])
	{
		NSAutoreleasePool *poolWhileLoop = [[NSAutoreleasePool alloc] init];
		[theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
		[poolWhileLoop release];
	}
	
	[pool release];
}

//----------------------------------------------------------------------
//	backupThreadIsBusy
//
//	Purpose:	returns true if the backup thread is working on stuff
//
//	usage: at terminate
//	while ([OpenMetaBackup backupThreadIsBusy])
//		[NSThread sleepForTimeInterval:0.1];
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(BOOL)backupThreadIsBusy;
{
	return gOMBackupThreadBusy;
}

//----------------------------------------------------------------------
//	backupThread
//
//	Purpose:	returns the backup thread. Usually called from the main thread, but I put a synchronize on it just in case
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(NSThread*)backupThread;
{
	@synchronized([self class])
	{
		static NSThread* buThread = nil;
		if (buThread == nil)
		{
			buThread = [[NSThread alloc] initWithTarget:self selector:@selector(backupThreadMain:) object:buThread];
			[buThread start];
		}
		return buThread;
	}
	return nil;
}

//----------------------------------------------------------------------
//	enqueueBackupItem
//
//	Purpose:	add the path to the list of items to backup data for. 
//				note that if the backup is already in the queue we do nothing.
//
//	Thread:		only call on the buThread
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(void)enqueueBackupItem:(NSString*)inPath;
{
	gOMBackupThreadBusy = YES;
	if ([gOMBackupQueue containsObject:inPath])
		return;
	
	[gOMBackupQueue addObject:inPath];
	
	if ([gOMBackupQueue count] == 1)
		[self performSelector:@selector(doABackup:) withObject:nil afterDelay:0.2];
}

//----------------------------------------------------------------------
//	doABackup
//
//	Purpose:	Does a backup. If there are more on the queue, we call ourselves later.
//
//	Thread:		only call on the buThread
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(void)doABackup:(id)arg;
{
	if ([gOMBackupQueue count] == 0)
		return;
	
	NSString* thePathToDo = [gOMBackupQueue objectAtIndex:0];
	[self backupMetadataNow:thePathToDo];
	[gOMBackupQueue removeObjectAtIndex:0];
	
	if ([gOMBackupQueue count] > 0)
	{
		[self performSelector:@selector(doABackup:) withObject:nil afterDelay:0.05];
	}
	else
	{
		gOMBackupThreadBusy = NO;
	}
}

+(BOOL)attributeKeyMeansBackup:(NSString*)attrName;
{
	if ([attrName hasPrefix:@"kOM"] || [attrName hasPrefix:[OpenMeta spotlightKey:@"kOM"]] || [attrName hasPrefix:[OpenMeta spotlightKey:@"kMDItem"]] )
		return YES;
	
	return NO;
}

//----------------------------------------------------------------------
//	backupMetadataNow
//
//	Purpose:	actually backs up the meta data. 
//
//	Thread:		should be able to call on any thread. 
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(void)backupMetadataNow:(NSString*)inPath;
{
	if ([inPath length] == 0)
		return;
		
	// create dictionary representing all kOM* metadata on the file:
	NSMutableDictionary* omDictionary = [NSMutableDictionary dictionary];
	
	char* nameBuffer = nil;
	
	ssize_t bytesNeeded = listxattr([inPath fileSystemRepresentation], nil, 0, XATTR_NOFOLLOW);
	
	if (bytesNeeded <= 0)
		return; // no attrs or no info.
	
	nameBuffer = malloc(bytesNeeded);
	listxattr([inPath fileSystemRepresentation], nameBuffer, bytesNeeded, XATTR_NOFOLLOW);
	
	// walk through the returned buffer, getting names, 
	char* namePointer = nameBuffer;
	ssize_t bytesLeft = bytesNeeded;
	while (bytesLeft > 0)
	{
		NSString* attrName = [NSString stringWithUTF8String:namePointer];
		ssize_t byteLength = strlen(namePointer) + 1;
		namePointer += byteLength;
		bytesLeft -= byteLength;
		
		// backup all kOM and kMDItem stuff. This will back up apple's where froms, etc.
		if ([self attributeKeyMeansBackup:attrName])
		{
			// add to dictionary:
			NSError* error = nil;
			id objectStored = [OpenMeta getXAttr:attrName path:inPath error:&error];
			
			if (objectStored)
				[omDictionary setObject:objectStored forKey:attrName];
		}
	}
	
	
	if ([omDictionary count] > 0)
	{
		NSMutableDictionary* outerDictionary = [NSMutableDictionary dictionary];
		
		[outerDictionary setObject:omDictionary forKey:@"omDict"];
		
		// create alias to file, so that we can find it easier:
		NSData* fileAlias = [[self class] aliasDataForPath:inPath];
		if (fileAlias)
			[outerDictionary setObject:fileAlias forKey:@"bu_alias"];
		
		// store path - which is in the alias too but not directly accessible
		if (inPath)
			[outerDictionary setObject:inPath forKey:@"bu_path"];
		
		// store date that we did the backup
		[outerDictionary setObject:[NSDate date] forKey:@"bu_date"];
		
		
		// place to put data: 
		// filename is 
		NSString* buItemPath = [self backupPathForItem:inPath];
		[outerDictionary writeToFile:buItemPath atomically:YES];
		
		[self setBackupStamp:inPath]; // set the id of the backup we just made on the actual file - not the backup file.
	}
	
	if (nameBuffer)
		free(nameBuffer);
}

#pragma mark alias handling

//----------------------------------------------------------------------
//	fsRefToPath
//
//	Purpose:	Given an fsref, returns a path
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(NSString*)fsRefToPath:(FSRef*)inRef;
{			
	if (inRef == nil)
		return nil;
		
	char thePath[4096];
	OSStatus err = FSRefMakePath(inRef, (UInt8*) &thePath, 4096);
	
	if (err == noErr)
	{
		NSString* filePath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:thePath length:strlen(thePath)];
		return filePath;
	}
	return nil;
}

//----------------------------------------------------------------------
//	aliasDataForFSRef
//
//	Purpose:	returns an alias for the passed fsRef - aliases only work for existing files.
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/28 
//
//----------------------------------------------------------------------
+(NSData*)aliasDataForFSRef:(FSRef*)inRef;
{
	AliasHandle aliasHandle = nil;
	OSStatus err = FSNewAlias(nil, inRef, &aliasHandle);
	
	if (err != noErr || aliasHandle == nil)
	{
		if (aliasHandle)
			DisposeHandle((Handle) aliasHandle);
		return nil;
	}
	
	HLock((Handle)aliasHandle);
	NSData* aliasData = [NSData dataWithBytes:*aliasHandle length:GetHandleSize((Handle) aliasHandle)];
	HUnlock((Handle)aliasHandle);

	if (aliasHandle)
		DisposeHandle((Handle) aliasHandle);
	return aliasData;
}
//----------------------------------------------------------------------
//	aliasForPath
//
//	Purpose: returns an alias for a path. NSData	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom on 2007/02/13 
//
//----------------------------------------------------------------------
+(NSData*) aliasDataForPath:(NSString*)inPath;
{
	if (inPath == nil)
		return nil;
	
	FSRef pathFSRef;
	OSErr err = FSPathMakeRefWithOptions((const UInt8*) [inPath fileSystemRepresentation], kFSPathMakeRefDoNotFollowLeafSymlink, &pathFSRef, nil);
	if (err != noErr)
		return nil;
		
	return [self aliasDataForFSRef:&pathFSRef];
}

//----------------------------------------------------------------------
//	resolveAliasDataToPath
//
//	Purpose:	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom on 2007/02/13 
//
//----------------------------------------------------------------------
+(NSString*) resolveAliasDataToPath:(NSData*)inData osErr:(OSErr*)outErr;
{
	*outErr = paramErr;
	if (inData == nil)
		return nil;
	
	if (![inData isKindOfClass:[NSData class]])
		return nil;
	
	*outErr = noErr;
	
	//Constants
	//kResolveAliasFileNoUI
	//The Alias Manager should resolve the alias without presenting a user interface.
	//kResolveAliasTryFileIDFirst
	//The Alias Manager should search for the alias target using file IDs before searching using the path.
	
	// we need to construct a handle from nsdata:
	NSString* thePath = nil;
	AliasHandle aliasHandle;
	if (PtrToHand([inData bytes], (Handle*)&aliasHandle, [inData length]) == noErr)
	{
		// We want to allow the caller to avoid blocking if the volume  
		//in question is not reachable.  The only way I see to do that is to  
		//pass the kResolveAliasFileNoUI flag to FSResolveAliasWithMountFlags.  
		//This will cause it to fail immediately with nsvErr (no such volume).
//		unsigned long mountFlags = kResolveAliasTryFileIDFirst;
//		mountFlags |= kResolveAliasFileNoUI; // no ui 
		unsigned long mountFlags = kResolveAliasFileNoUI;
			
		FSRef				theTarget;
		Boolean				changed;
		
		if((*outErr = FSResolveAliasWithMountFlags( NULL, aliasHandle, &theTarget, &changed, mountFlags )) == noErr)
		{
			thePath = [self fsRefToPath:&theTarget];
		}
		if (aliasHandle)
			DisposeHandle((Handle) aliasHandle);
	}
	return thePath;
}

@end
