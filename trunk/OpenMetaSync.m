//
//  OpenMetaSync.m
//  yep
//
//  Created by Tom Andersen on 2012-08-07.
//
//

#import "OpenMeta.h"
#import "OpenMetaSync.h"

#ifndef OM_ParamError
    #define OM_ParamError (-1)
    #define OM_NoDataFromPropertyListError (-2)
    #define OM_NoMDItemFoundError (-3)
    #define OM_CantSetMetadataError (-4)
    #define OM_MetaTooBigError (-5)
#endif

NSString* const OM_ParamErrorStringSync = @"Open Meta parameter error";
NSString* const OM_MetaTooBigErrorStringSync = @"Meta data is too big - size as binary plist must be less than (perhaps 4k?) some number of bytes";
const long kMaxDataSizeAttr = 4096; // Limit maximum data that can be stored,



@interface OpenMetaSync (Private)

-(void)writeSingleFile;
-(void)readSingleFile;
-(void)doneTheJob;

@end


@implementation OpenMetaSync
@synthesize files;
@synthesize	returnDict;
@synthesize	readItems;
@synthesize	aggressiveRestore;

-(void)main;
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    BOOL savedAllowAuthDialogs = gAllowOpenMetaAuthenticationDialogs;
    gAllowOpenMetaAuthenticationDialogs = NO;
    // we are either to read or write open meta data:
    [self readSingleFile];
    [self writeSingleFile];
	
	// ok report back the news:
	[self performSelectorOnMainThread:@selector(doneTheJob:) withObject:nil waitUntilDone:NO];
    self.files = nil;
	self.returnDict = nil;
    self.readItems = nil;
    
    gAllowOpenMetaAuthenticationDialogs = savedAllowAuthDialogs;
    
    [pool release];
}

-(NSString*)singleFile;
{
    if ([self.files count] == 0)
        return nil;
    
    return [self.files objectAtIndex:0];
}

-(void)dealloc;
{
	self.files = nil;
	self.returnDict = nil;
    self.readItems = nil;
	[super dealloc];
}

-(void)doneTheJob:(id)obj;
{
	[[NSNotificationCenter defaultCenter] postNotificationName:@"OpenMetaSyncDone" object:self.returnDict];
}



+(NSDictionary*)backupDictForPath:(NSString*)inPath;
{
	if ([inPath length] == 0)
        return nil;
    
    // we backup tagtime, tags and ratings
    NSError* error = nil;
    NSArray* userTags = [OpenMeta getUserTags:inPath error:&error];
	NSNumber* rating = [OpenMeta getXAttrMetaData:(NSString*)kMDItemStarRating path:inPath error:&error];
	NSDate* tagTime = [OpenMeta getXAttrMetaData:kMDItemOMUserTagTime path:inPath error:&error];
	NSDate* ratingTime = [OpenMeta getXAttrMetaData:kMDItemOMRatingTime path:inPath error:&error];
    
    if (userTags == nil && rating == nil && tagTime == nil && ratingTime == nil)
        return nil;
    
    NSMutableDictionary* buDict = [NSMutableDictionary dictionary];
    if (userTags)
        [buDict setObject:userTags forKey:@"tags"];
    if (rating)
        [buDict setObject:rating forKey:@"rating"];
    if (tagTime)
        [buDict setObject:tagTime forKey:@"tagdate"];
    if (ratingTime)
        [buDict setObject:ratingTime forKey:@"ratingdate"];
    
    [buDict setObject:inPath forKey:@"path"];
    return buDict;
}

+(BOOL)backupDictsTheSame:(NSDictionary*)one two:(NSDictionary*)two;
{
	if ([one count] != [two count])
		return NO;
	    
	NSArray* keys = [one allKeys];
	for (NSString* aKey in keys)
	{
		id obj1 = [one objectForKey:aKey];
		id obj2 = [two objectForKey:aKey];
		
		// if both objects are dates, they will compare non equal, even though they both were spawned by the same date: the stored date in a backup file is only good to the second, I think that the binary plist gets more resolution?
		if ([obj1 isKindOfClass:[NSDate class]] && [obj2 isKindOfClass:[NSDate class]])
		{
			// compare the dates
			NSTimeInterval difference = [obj1 timeIntervalSinceDate:obj2];
			if (fabs(difference) > 2.0)
				return NO;
		}
		else 
		{
			if (![obj1 isEqual:obj2])
				return NO;
		}
	}
	return YES;
}

+(BOOL)needToUpdate:(NSDictionary*)onDisk fromBU:(NSDictionary*)fromBU dateKey:(NSString*)dateKey;
{
	NSDate* dateOnDisk = [onDisk objectForKey:dateKey];
	NSDate* dateOnBU = [fromBU objectForKey:dateKey];
    
    if (dateOnDisk == nil && dateOnBU == nil)
        return NO;
    
    if (dateOnDisk == nil && dateOnBU != nil)
        return YES;
    
    if (dateOnDisk != nil && dateOnBU == nil)
        return NO;
    
    NSComparisonResult theCompare = [dateOnDisk compare:dateOnBU];
    if (theCompare == NSOrderedSame)
        return NO;
    
    // The dateOnDisk is later in time than anotherDate, NSOrderedDescending
    if (theCompare == NSOrderedDescending)
        return NO;
    
	return YES;
}


+(NSInteger)setTagsAndTime:(NSDictionary*)buDict toPath:(NSString*)inPath;
{
    // we need to set the tags to be exactly how they are in the backup, not to 'NOW'
    NSError* error = [OpenMeta setUserTags:[buDict objectForKey:@"tags"] path:inPath atDate:[buDict objectForKey:@"tagdate"]];
    if (error)
        return 0;
    return [[buDict objectForKey:@"tags"] count];
}

+(NSInteger)setRatingAndTime:(NSDictionary*)buDict toPath:(NSString*)inPath;
{
    [OpenMeta setXAttrMetaData:[buDict objectForKey:@"rating"] metaDataKey:(NSString*)kMDItemStarRating path:inPath];
 	NSError* error = [OpenMeta setXAttrMetaData:[buDict objectForKey:@"ratingdate"] metaDataKey:kMDItemOMRatingTime path:inPath];
    if (error)
        return 0;
    return 1;
}

+(int)restoreMetadataFromBackupDictIfNeeded:(NSDictionary*)backupContents;
{
	if ([backupContents count] == 0)
		return 0;

	NSString* filePath = [[backupContents objectForKey:@"path"] stringByExpandingTildeInPath];
	if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
	{
        return -1; // could find no file to bu to.
	}
	
	// obtain the current state of affairs on the file by looking at a backup dict from the existing file:
	NSDictionary* currentData = [self backupDictForPath:filePath];
	
	if ([currentData count] == 0 && [backupContents count] == 0)
		return 0; // no data anywhere
	
	if ([self backupDictsTheSame:currentData two:backupContents])
		return 0;
    
    int numKeysSet = 0;
    if ([self needToUpdate:currentData fromBU:backupContents dateKey:@"tagdate"])
    {
        numKeysSet += [self setTagsAndTime:backupContents toPath:filePath];
    }
    
    if ([self needToUpdate:currentData fromBU:backupContents dateKey:@"ratingdate"])
    {
        numKeysSet += [self setRatingAndTime:backupContents toPath:filePath];
    }
	
#if KP_DEBUG
	if (numKeysSet > 0)
		NSLog(@"meta data synced on %@ with %@", filePath, backupContents);
#endif
	return numKeysSet;
}

+(int)searchAndRestore:(NSDictionary*)backupContents;
{
    @try {
            // find all files that have the same file name:
            NSString* fileName = [[[backupContents objectForKey:@"path"] stringByExpandingTildeInPath] lastPathComponent];
            NSArray* filesWithThatName = [self filesWithName:fileName];
            
            // if a file is too popular a name we don't do this.
            if ([filesWithThatName count] > 6)
                return 0;
            
            int numKeysSet = 0;
            for (NSString* aFile in filesWithThatName)
            {
                // obtain the current state of affairs on the file by looking at a backup dict from the existing file:
                NSDictionary* currentData = [self backupDictForPath:aFile];
                
                if ([currentData count] == 0 && [backupContents count] == 0)
                    return 0; // no data anywhere
                
                if ([currentData count] > 0)
                    return 0; // if the file already has some tags added, then this is not the system to update that.
                
                if ([self needToUpdate:currentData fromBU:backupContents dateKey:@"tagdate"])
                {
                    numKeysSet += [self setTagsAndTime:backupContents toPath:aFile];
                }
                
                if ([self needToUpdate:currentData fromBU:backupContents dateKey:@"ratingdate"])
                {
                    numKeysSet += [self setRatingAndTime:backupContents toPath:aFile];
                }
                
            #if KP_DEBUG
                if (numKeysSet > 0)
                    NSLog(@"meta data synced on %@ with %@", aFile, backupContents);
            #endif
            }
        return numKeysSet;
    }
    @catch (NSException *exception) {
        NSLog(@"Exception on Tag restore by File Name: %@", [exception description]);
    }
    return 0;
}

+(NSArray*)filesWithName:(NSString*)inFileName;
{
	// create the query
    // We would like to query on kMDItemFSName but that is really really really slow.
    // so we use display name.
    // for a name like thisfile.pdf we might have a display name of thisfile or thisfile.pdf, so we look for those only. Not perfect, but FS searches will not work here.
    NSString* fileNameNoExt = [inFileName stringByDeletingPathExtension];
	NSString* queryString = [NSString stringWithFormat:@"((kMDItemDisplayName == \"%@\") || (kMDItemDisplayName == \"%@\"))", inFileName, fileNameNoExt];
	MDQueryRef mdQuery = MDQueryCreate(nil, (CFStringRef)queryString, nil, nil);
	
	// if something is goofy, we won't get the query back, and all calls involving a mil MDQuery crash. So return:
	if (mdQuery == nil)
	{
		return nil;
	}
	
	// look for these only on the computer.
	CFArrayRef scope = (CFArrayRef)[NSArray arrayWithObjects:(NSString*)kMDQueryScopeComputer, nil];
	MDQuerySetSearchScope(mdQuery, scope, 0);
	
	[NSRunLoop currentRunLoop]; // need run loop for mdquery
	
	// start it
	MDQuerySetMaxCount(mdQuery, 25); // so we don't go completely crazy..
	BOOL queryRunning = MDQueryExecute(mdQuery, kMDQuerySynchronous); 
	if (!queryRunning)
	{
		CFRelease(mdQuery);
		return nil;
	}
	
	// ok enumerate through the results:
	NSInteger numResults = MDQueryGetResultCount(mdQuery);

	NSMutableArray* items = [NSMutableArray array];
	
	NSInteger count;
	for (count = 0; count < numResults; count++)
	{
		MDItemRef theItem = (MDItemRef) MDQueryGetResultAtIndex(mdQuery, count);
		
		CFStringRef path = MDItemCopyAttribute(theItem, kMDItemPath);
		if (path)
		{
            [items addObject:(id)path];
			CFRelease(path);
		}
	}
	
	CFRelease(mdQuery);
    
    return items;
}

-(void)writeSingleFile;
{
	// first we have to search for all the items we can find. 
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	// create the query
    //NSArray* keysToSearch = [NSArray arrayWithObjects:@"kMDItemOMUserTagTime", [OpenMeta tagsToSearchFor], (NSString*)kMDItemStarRating, nil];
    NSArray* keysToSearch = [NSArray arrayWithObjects:@"kMDItemOMUserTagTime", kMDItemOMUserTags, kMDItemUserTags, (NSString*)kMDItemStarRating, nil];
	
	NSString* queryString = @"";
	for (NSString* aKey in keysToSearch)
	{
		NSString* thisKeyQuery = [NSString stringWithFormat:@"(%@ == *)", aKey];
		if ([queryString length] > 0)
			queryString = [queryString stringByAppendingString:@" || "];
		queryString = [queryString stringByAppendingString:thisKeyQuery];
	}
	
	MDQueryRef mdQuery = MDQueryCreate(nil, (CFStringRef)queryString, nil, nil);
	
	// if something is goofy, we won't get the query back, and all calls involving a mil MDQuery crash. So return:
	if (mdQuery == nil)
	{
		[pool release];
		self.returnDict = [NSDictionary dictionaryWithObject:@"spotlight failed" forKey:@"status"];
		return;
	}
	
	// look for these everywhere.
	CFArrayRef scope = (CFArrayRef)[NSArray arrayWithObjects:(NSString*)kMDQueryScopeComputer, (NSString*)kMDQueryScopeNetwork, nil];
	MDQuerySetSearchScope(mdQuery, scope, 0);
	
	[NSRunLoop currentRunLoop]; // need run loop for mdquery
	
	
	// start it
	MDQuerySetMaxCount(mdQuery, 500000); // so we don't go completely crazy..
	BOOL queryRunning = MDQueryExecute(mdQuery, kMDQuerySynchronous); 
	if (!queryRunning)
	{
		CFRelease(mdQuery);
		[pool release];
		self.returnDict = [NSDictionary dictionaryWithObject:@"spotlight failed" forKey:@"status"];
		return;
	}
	
	// ok enumerate through the results:
	NSInteger numResults = MDQueryGetResultCount(mdQuery);

	NSMutableArray* items = [NSMutableArray array];
	
	NSInteger count;
	for (count = 0; count < numResults; count++)
	{
		NSAutoreleasePool* innerPool = [[NSAutoreleasePool alloc] init];
		
		MDItemRef theItem = (MDItemRef) MDQueryGetResultAtIndex(mdQuery, count);
		
		CFStringRef path = MDItemCopyAttribute(theItem, kMDItemPath);
		if (path)
		{
			NSDictionary* backupDict = [[self class] backupDictForPath:(NSString*)path];
			if (backupDict)
				[items addObject:backupDict];
			
			CFRelease(path);
		}
		[innerPool release];
	}
	
	CFRelease(mdQuery);
	
    // we write a merged file.
    NSMutableDictionary* outDict = [NSMutableDictionary dictionary];
    for (NSDictionary* aDict in self.readItems)
    {
        // all paths are written as abbreviated
        if ([aDict objectForKey:@"path"])
            [outDict setObject:aDict forKey:[aDict objectForKey:@"path"]];
    }
    
    for (NSDictionary* aDict in items)
    {
        // all paths are written as abbreviated
        if ([aDict objectForKey:@"path"])
            [outDict setObject:aDict forKey:[aDict objectForKey:@"path"]];
    }
    
    NSMutableArray* allItems = [NSMutableArray arrayWithArray:[outDict allValues]];
    
    
    // sort by path - something so that we will write the same file for the same data... helps dropbox do syncing.
    NSSortDescriptor *descriptor = [[[NSSortDescriptor alloc] initWithKey:@"path" ascending:NO] autorelease];
    [allItems sortUsingDescriptors:[NSArray arrayWithObjects:descriptor, nil]];
    BOOL worked = NO;
    for (NSString* aFile in self.files)
        worked = [allItems writeToFile:aFile atomically:YES];
	
	NSString* statusString = [NSString stringWithFormat:@"%ld backups done, file written to %@", numResults, [[self singleFile] stringByAbbreviatingWithTildeInPath]];
	self.returnDict = [NSDictionary dictionaryWithObjectsAndKeys:	statusString, @"status",
																	[NSNumber numberWithBool:worked], @"worked",
																	[NSNumber numberWithInt:(int) [items count]], @"itemCount",
																	nil];
	
	[pool release];
}

-(void)readSingleFile;
{
	NSArray* items = [NSArray arrayWithContentsOfFile:[self singleFile]];
	if ([items count] == 0)
	{
		self.returnDict = [NSDictionary dictionaryWithObject:@"no restore data found" forKey:@"status"];
		return;
	}
	
	// ok, loop through all keys
	int numberDone = 0;
	for (NSDictionary* aDict in items)
	{
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
        int numberForThis = [[self class] restoreMetadataFromBackupDictIfNeeded:aDict];
        if (numberForThis > 0)
            numberDone += numberForThis;
        [pool release];
	}
    
    // aggressive restores are done after a normal one, as we want any hits on the normal restore to take precendence.
    if (self.aggressiveRestore)
    {
        for (NSDictionary* aDict in items)
        {
            NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
            int numberForThis = [[self class] searchAndRestore:aDict];
            if (numberForThis > 0)
                numberDone += numberForThis;
            [pool release];
        }
	}
    self.readItems = items;
	
	NSString* statusString = [NSString stringWithFormat:@"%d restores done", numberDone];
	self.returnDict = [NSDictionary dictionaryWithObjectsAndKeys:	statusString, @"status",
					   [NSNumber numberWithBool:YES], @"worked",
					   [NSNumber numberWithInt:(int) [items count]], @"itemCount",
					   nil];
                    
    if (self.aggressiveRestore)
        [self performSelectorOnMainThread:@selector(tellDoneAgressive:) withObject:[NSNumber numberWithInteger:numberDone] waitUntilDone:YES];
}
-(void)tellDoneAgressive:(NSNumber*)numDone;
{
    NSDictionary* doneDict = [NSDictionary dictionaryWithObject:numDone forKey:@"numDone"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TagSyncDoneAgressive" object:nil userInfo:doneDict];
}


NSOperationQueue* syncFileOperationQueue = nil;
+(NSOperationQueue*)singleFileQueue;
{
	if (syncFileOperationQueue == nil)
    {
		syncFileOperationQueue = [[NSOperationQueue alloc] init];
        [syncFileOperationQueue setMaxConcurrentOperationCount:1];
    }
	
    return syncFileOperationQueue;
}

// the first file is used for input, after syncing current tags and ratings written to all locations passed
+(void)syncWithFiles:(NSArray*)inFilePaths aggressiveRestore:(BOOL)inAggressiveRestore;
{
	if (!inAggressiveRestore && [[[self singleFileQueue] operations] count] > 1)
	{
		return;
	}
	
	OpenMetaSync* newOperation = [[[OpenMetaSync alloc] init] autorelease];
	newOperation.files = inFilePaths;
    newOperation.aggressiveRestore = inAggressiveRestore;
	[[self singleFileQueue] addOperation:newOperation];
}

@end
