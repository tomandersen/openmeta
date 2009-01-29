//
//  OpenMeta.m
//  OpenMeta
//
//  Created by Tom Andersen on 17/07/08.
//  MIT license.
//
/*
Copyright (c) 2009 ironic software

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
*/

#include <sys/xattr.h>
#include <sys/time.h>
#include <sys/stat.h>
#import "OpenMeta.h"
#import "OpenMetaBackup.h"

const long kMaxDataSize = 4096; // Limit maximum data that can be stored, 

NSString* const kOMUserTags = @"kOMUserTags";
NSString* const kOMUserTagTime = @"kOMUserTagTime";
NSString* const kOMBookmarks = @"kOMBookmarks";
NSString* const kOMApproved = @"kOMApproved";
NSString* const kOMWorkflow = @"kOMWorkflow";
NSString* const kOMProjects = @"kOMProjects";
NSString* const kOMStarRating = @"kOMStarRating";
NSString* const kOMHidden = @"kOMHidden";

const double kOMMaxRating = 5.0;


@interface OpenMeta (Private)
+(BOOL)validateAsArrayOfStrings:(NSArray*)array;
+(NSString*)spotlightKey:(NSString*)inKeyName;
+(NSArray*)removeDuplicateTags:(NSArray*)tags;
@end

@implementation OpenMeta

//----------------------------------------------------------------------
//	setUserTags
//
//	Purpose:	Set the passed tags on the passed file url, so that the user can search in 
//				spotlight. 
//	Also:		case preserving case insensitive removal of duplicate tags - so feel free to pass in a few dups
//
//	Inputs:		If you pass in nil or an empty array, the entire key is removed from the data.
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/07/17 
//
//----------------------------------------------------------------------
+(OMError)setUserTags:(NSArray*)tags url:(NSURL*)url;
{
	if (![self validateAsArrayOfStrings:tags])
		return OM_ParamError;
	
	tags = [self removeDuplicateTags:tags];
	
	// We want to keep the tags stored in as simple a way as possible. But also we don't want to have any issues with special characters,
	// so it is impossible to use a single, for example comma delimited string to hold the values. 
	// NSArrays can be written out as a plist, so that is what we will do. 
	// Write the plist out as plain xml text, so as to allow someone not using cocoa to read out the values:
	OMError outError = [self setNSArrayMetaData:tags metaDataKey:kOMUserTags url:url];
	
	// set the time that the user tagged the document:
	[self setXAttrMetaData:[NSDate date] metaDataKey:kOMUserTagTime url:url];
	
	return outError; 
}

//----------------------------------------------------------------------
//	clearUserTags
//
//	Purpose:	removes the passed tags. If the tags are already in, then OM_MetaDataNotChanged is returned
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/12/10 
//
//----------------------------------------------------------------------
+(OMError)clearUserTags:(NSArray*)tags url:(NSURL*)url;
{
	if (![self validateAsArrayOfStrings:tags])
		return OM_ParamError;

	// we need to be careful to be case insensitive case preserving here:
	OMError errorCode = OM_NoError;
	NSArray* originalTags = [self getNSArrayMetaData:kOMUserTags url:url errorCode:&errorCode];
	NSMutableArray* newArray = [NSMutableArray arrayWithCapacity:[originalTags count]];
	
	for (NSString* aTag in originalTags)
	{
		NSString* lowercaseTag = [aTag lowercaseString];
		BOOL keepTheTag = YES;
		for (NSString* aTagToClear in tags)
		{
			NSString* lowercaseTagToClear = [aTagToClear lowercaseString];
			if ([lowercaseTagToClear isEqualToString:lowercaseTag])
				keepTheTag = NO;
		}
		
		if (keepTheTag)
			[newArray addObject:aTag];
	}
	 
	if ([newArray count] == [originalTags count])
		return OM_MetaDataNotChanged;
	
	[self setXAttrMetaData:[NSDate date] metaDataKey:kOMUserTagTime url:url];
	
	return [self setNSArrayMetaData:newArray metaDataKey:kOMUserTags url:url];
}




//----------------------------------------------------------------------
//	addUserTags
//
//	Purpose:	adds the tags to the current tags. If the tags are already in, then OM_MetaDataNotChanged is returned
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/12/10 
//
//----------------------------------------------------------------------
+(OMError)addUserTags:(NSArray*)tags url:(NSURL*)url;
{
	if (![self validateAsArrayOfStrings:tags])
		return OM_ParamError;

	// we need to be careful to be case insensitive case preserving here:
	OMError errorCode = OM_NoError;
	NSArray* originalTags = [self getNSArrayMetaData:kOMUserTags url:url errorCode:&errorCode];
	NSMutableArray* newArray = [NSMutableArray arrayWithArray:originalTags]; 
	[newArray addObjectsFromArray:tags];
	NSArray* cleanedTags = [self removeDuplicateTags:newArray];
	
	if (![originalTags isEqualToArray:cleanedTags])
	{
		[self setXAttrMetaData:[NSDate date] metaDataKey:kOMUserTagTime url:url];
		
		return [self setNSArrayMetaData:cleanedTags metaDataKey:kOMUserTags url:url];
	}
		
	return OM_MetaDataNotChanged;
}


//----------------------------------------------------------------------
//	getUserTags
//
//	Purpose:	retrive user tags for the passed file
//
//	Inputs:		NSArray of strings - nothing else allowed
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/07/17 
//
//----------------------------------------------------------------------
+(NSArray*)getUserTags:(NSURL*)url errorCode:(OMError*)errorCode;
{
	// I put restore meta here - as restoreMetadata calls us! 
	// I put the restore on the usertags and ratings. Users will have to manually call restore for other keys 
	[OpenMetaBackup restoreMetadata:[url path]];
	return [self getNSArrayMetaData:kOMUserTags url:url errorCode:errorCode];
}



//----------------------------------------------------------------------
//	setRating
//
//	Purpose:	get/set ratings. If you pass in a negative rating we remove the rating, which is different from a rating of 0
//				ratings are 0 - 5 'stars'.
//
//
//	Inputs:	0. if rating is not found. 0 - 5 rating spread (float).
//
//  Created by Tom Andersen on 2008/07/17 
//
//----------------------------------------------------------------------
+(OMError)setRating:(double)rating05 url:(NSURL*)url;
{
	if (rating05 <= 0.0)
		return [self setXAttrMetaData:nil metaDataKey:kOMStarRating url:url];
	
	if (rating05 > kOMMaxRating)
		rating05 = kOMMaxRating;
		
	NSNumber* ratingNS = [NSNumber numberWithDouble:rating05];
	return [self setXAttrMetaData:ratingNS metaDataKey:kOMStarRating url:url];
}

+(double)getRating:(NSURL*)url errorCode:(OMError*)errorCode;
{
	// ratings and tags are the only 'auto - restored' items 
	[OpenMetaBackup restoreMetadata:[url path]];
	NSNumber* theNumber = [self getXAttrMetaData:kOMStarRating url:url errorCode:errorCode];
	return [theNumber doubleValue];
}

+(OMError)hide:(NSURL*)url;
{
	return [self setXAttrMetaData:[NSNumber numberWithBool:YES] metaDataKey:kOMHidden url:url];
}

+(OMError)unhide:(NSURL*)url;
{
	return [self setXAttrMetaData:nil metaDataKey:kOMHidden url:url];
}

+(BOOL)isHidden:(NSURL*)url errorCode:(OMError*)errorCode;
{
	NSNumber* theNumber = [self getXAttrMetaData:kOMHidden url:url errorCode:errorCode];
	if (theNumber == nil)
		return NO;
	
	return [theNumber boolValue];
}


//----------------------------------------------------------------------
//	setString:keyName:url:
//
//	Purpose:	simple way to set a single string on a key.
//				use these when you only want to store a single string in the spotlightDB under a key
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/09/21 
//
//----------------------------------------------------------------------
+(OMError)setString:(NSString*)string keyName:(NSString*)keyName url:(NSURL*)url;
{
	OMError	theErr = [self setXAttrMetaData:string metaDataKey:keyName url:url];
	return theErr;
}

+(NSString*)getString:(NSString*)keyName url:(NSURL*)url errorCode:(OMError*)errorCode;
{
	return [self getXAttrMetaData:keyName url:url errorCode:errorCode];
}

//----------------------------------------------------------------------
//	setDictionaries
//
//	Purpose:	
//
//	Inputs:		array of dictionaries. Two attributes will be set. One, a spotlight searchable array 
//				composed of @"name" fields found in the array, plus the entire array as passed in, which is stored in an 
//				xattr that will not be indexed by spotlight.
//				
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/07/17 
//
//----------------------------------------------------------------------
+(OMError)setDictionaries:(NSArray*)arrayOfDicts keyName:(NSString*)keyName url:(NSURL*)url;
{
	NSMutableArray* spotlightArray = [NSMutableArray array];
	BOOL needAllDictsSet = NO;
	for (NSDictionary* aDict in arrayOfDicts)
	{
		id name = [aDict objectForKey:@"name"]; // name can be string, nsdate, nsnumber
		if (name)
		{
			[spotlightArray addObject:name];
			if ([aDict count] > 1)
				needAllDictsSet = YES;
		}
		else
		{
			needAllDictsSet = YES;
		}
	}
	
	// the searchable thing is optional if the spotlightArray is empty this will erase for that key too.
	// set as array - to set single
	OMError theErr = [self setXAttrMetaData:spotlightArray metaDataKey:keyName url:url];
		
	// set all the data to the passed key - but only set if there are other keys:
	if (theErr == OM_NoError && needAllDictsSet)
		theErr = [self setXAttr:arrayOfDicts forKey:keyName url:url];
	
	return theErr;
}

//----------------------------------------------------------------------
//	getDictionaries
//
//	Purpose:	returns dicts as were passed into setDictionaries. 
//				if you only want the names then you can call getDictionariesNames
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/07/17 
//
//----------------------------------------------------------------------
+(NSArray*)getDictionaries:(NSString*)keyName url:(NSURL*)url errorCode:(OMError*)errorCode;
{
	return [self getXAttr:keyName url:url errorCode:errorCode];
}

+(NSArray*)getDictionariesNames:(NSString*)keyName url:(NSURL*)url errorCode:(OMError*)errorCode;
{
	return [self getXAttrMetaData:keyName url:url errorCode:errorCode];
}

#pragma mark getting/setting on multiple files 

+(NSArray*)urlsFromFilePaths:(NSArray*)inFilePaths;
{
	NSMutableArray* outURLs = [NSMutableArray array];
	for (NSString* path in inFilePaths)
		[outURLs addObject:[NSURL fileURLWithPath:path]];
	return outURLs;
}

//----------------------------------------------------------------------
//	getCommonUserTags
//
//	Purpose:	returns an array of tags (each of which could be multiple words, etc)
//				note that the use of 'prefix characters such as @ or & is useless and discouraged"
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/10/01 
//
//----------------------------------------------------------------------
+(NSArray*)getCommonUserTags:(NSArray*)urls errorCode:(OMError*)errorCode;
{
	// order is to 'be preserved' - but for multiple documents - we use the first passed doc
	if ([urls count] == 1)
		return [self getUserTags:[urls lastObject] errorCode:errorCode];
	
	NSMutableDictionary* theCommonTags = [NSMutableDictionary dictionary];
	
	NSArray* firstSetOfTags = nil;
	for (NSURL* aURL in urls)
	{
		// go through each document, extracting tags. 
		*errorCode = OM_NoError;
		NSArray* tags = [self getUserTags:aURL errorCode:errorCode];
		if ([tags count] == 0 || *errorCode != OM_NoError)
			return [NSArray array];
		
		// if we made it here it means that this document has some tags: if there are none in the 
		// commonTags yet it must mean that we have not added the original set:
		if ([theCommonTags count] == 0)
		{
			firstSetOfTags = tags;
			// add original set:
			for (NSString* aTag in tags)
				[theCommonTags setObject:aTag forKey:[aTag lowercaseString]];
		}
		else
		{
			// second or later document
			NSMutableDictionary* currentTags = [NSMutableDictionary dictionary];
			for (NSString* aTag in tags)
				[currentTags setObject:aTag forKey:[aTag lowercaseString]];
				
			// go through the theCommonTags,
			// removing any that are not in this document
			for (NSString* commonTag in [theCommonTags allKeys])
			{
				if ([currentTags objectForKey:commonTag] == nil)
					[theCommonTags removeObjectForKey:commonTag];
			}
		}
		
		if ([theCommonTags count] == 0)
			return [NSArray array];
	}
	
	// preserve order using the first array passed
	return [self orderedArrayWithDict:theCommonTags sortHint:firstSetOfTags];
}

//----------------------------------------------------------------------
//	setCommonUserTags
//
//	Purpose:	set common user tags: passed an array of paths and the original tags as from an earlier call 
//				to getCommonUserTags, this call will go through each document changing the tags as directed.
//				This method handles the case where another user or other program, multiple windows, etc, has modified 
//				the tags in between the time you called getCommonUserTags and the time you call setCommonUserTags
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/10/01 
//
//----------------------------------------------------------------------
+(OMError)setCommonUserTags:(NSArray*)urls originalCommonTags:(NSArray*)originalTags replaceWith:(NSArray*)replaceWith;
{
	if ([originalTags count] == 0 && [replaceWith count] == 0)
		return OM_NoError;
	
	// we try to preserve order, and we allow case changes, so original tags as @"foo" @"bar" is different from @"bar" @"Foo"
	// but all new tags are always added to the end. 
	OMError error = OM_NoError;
	for (NSURL* aURL in urls)
	{
		// get the tags currently on the document
		NSArray* tags = [self getUserTags:aURL errorCode:&error];
		NSMutableDictionary* currentTags = [NSMutableDictionary dictionary];
		for (NSString* aTag in tags)
			[currentTags setObject:aTag forKey:[aTag lowercaseString]];
		
		// remove the tags that were originally common:
		for (NSString* aTag in originalTags)
			[currentTags removeObjectForKey:[aTag lowercaseString]];
		
		// start building the new array using the order from the old array, along with the new values
		NSMutableArray* newTags = [NSMutableArray array];
		for (NSString* aTag in tags)
		{
			if ([currentTags objectForKey:[aTag lowercaseString]])
				[newTags addObject:aTag];
		}
		
		// add the new tags in the order passed.
		for (NSString* aTag in replaceWith)
			[newTags addObject:aTag];
		
		// write out the tags:
		OMError errorOnThisOne = [self setUserTags:newTags url:aURL];
		
		// if there was an error, don't abort the whoe thing, but rather just return an error code at the end:
		if (errorOnThisOne != OM_NoError)
			error = errorOnThisOne;
	}
	return error;
}

#pragma mark set data that will be indexed by spotlight 
//----------------------------------------------------------------------
//	getNSArrayMetaData
//
//	Purpose:	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/12/10 
//
//----------------------------------------------------------------------
+(NSArray*)getNSArrayMetaData:(NSString*)metaDataKey url:(NSURL*)url errorCode:(OMError*)errorCode;
{
	return (NSArray*) [self getXAttrMetaData:metaDataKey url:url errorCode:errorCode];
}

+(OMError)setNSArrayMetaData:(NSArray*)array metaDataKey:(NSString*)metaDataKey url:(NSURL*)url;
{
	return [self setXAttrMetaData:array metaDataKey:metaDataKey url:url];
}

//----------------------------------------------------------------------
//	addToNSArrayMetaData
//
//	Purpose:	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/12/10 
//
//----------------------------------------------------------------------
+(OMError)addToNSArrayMetaData:(NSArray*)itemsToAdd metaDataKey:(NSString*)metaDataKey url:(NSURL*)url;
{
	// get the current, then add the items in, checking for duplicates, then write out the result, if we need to.
	OMError errorCode = OM_NoError;
	NSMutableArray* newArray = [NSMutableArray arrayWithArray:[self getNSArrayMetaData:metaDataKey url:url errorCode:&errorCode]]; 
	
	BOOL needToSet = NO;
	for (id anItem in itemsToAdd)
	{
		if (![newArray containsObject:anItem])
		{
			needToSet = YES;
			[newArray addObject:anItem];
		}
	}
	
	if (needToSet)
		errorCode = [self setXAttrMetaData:newArray metaDataKey:metaDataKey url:url];
	
	return OM_MetaDataNotChanged;
}


//----------------------------------------------------------------------
//	getXAttrMetaData
//
//	Purpose:	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/12/10 
//
//----------------------------------------------------------------------
+(id)getXAttrMetaData:(NSString*)metaDataKey url:(NSURL*)url errorCode:(OMError*)errorCode;
{
	return [self getXAttr:[self spotlightKey:metaDataKey] url:url errorCode:errorCode];
}

//----------------------------------------------------------------------
//	setXAttrMetaData
//
//	Purpose:	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/12/10 
//
//----------------------------------------------------------------------
+(OMError)setXAttrMetaData:(id)plistObject metaDataKey:(NSString*)metaDataKey url:(NSURL*)url;
{
	OMError errorCode = [self setXAttr:plistObject forKey:[self spotlightKey:metaDataKey] url:url];
	return errorCode;
}

#pragma mark global prefs for recent tags 

//----------------------------------------------------------------------
//	recentTags
//
//	Purpose:	returns a list of the recently entered tags. The creation of the recently entered tags is not automatic. You need to call updatePrefsNewTags to do this.
//				only call updatePrefsNewTags if the USER has changed tags - usually automated scripts, etc will not want to update the recent tags
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/09 
//
//----------------------------------------------------------------------
+(NSArray*)recentTags;
{
	NSArray* outArray = [NSArray array];
	CFPropertyListRef prefArray = CFPreferencesCopyAppValue(CFSTR("recentlyEnteredTags"), CFSTR("com.openmeta.shared"));
	if (prefArray)
	{
		outArray = [NSArray arrayWithArray:(NSArray*)prefArray];
		CFRelease(prefArray);
	}
	return outArray;
}

+(void)updatePrefsNewTags:(NSArray*)oldTags newTags:(NSArray*)newTags;
{
	// we need to update the prefs with the recently entered tags. We limit the list to being 200 tags, and the most recently entered tags are at the top of the list.
	
	// we are passed a set of tags that the user started with, and the ones he ended with. We need the new ones only.
	NSMutableArray* tagsToAdd = [NSMutableArray arrayWithCapacity:[newTags count]];
	for (NSString* newTag in newTags)
	{
		if (![oldTags containsObject:newTag]) // since we are case sensitive here, a case change will count as a 'newly entered tag' which is what I want.
			[tagsToAdd addObject:newTag];
	}

	if ([tagsToAdd count] == 0)
		return;
	
	// by using CFPreferences, we can use a global shared pool of recently entered tags.
	NSMutableArray* currentRecents = [NSMutableArray array];
	CFPropertyListRef prefArray = CFPreferencesCopyAppValue(CFSTR("recentlyEnteredTags"), CFSTR("com.openmeta.shared"));
	if (prefArray)
	{
		[currentRecents addObjectsFromArray:(NSArray*)prefArray];
		CFRelease(prefArray);
	}
	// Case insensitivity is important - we also need to preserve case, but the recentTags list in the prefs only should have 
	// one version of each tag (eg only 'Tom' and not TOM, tom, ToM...)
	// Unfortunately, I need to create a copy of the array with lower cased strings (infortunate from performance point only..)
	NSMutableArray* lowerCasedCurrents = [NSMutableArray arrayWithCapacity:[currentRecents count]];
	for (NSString* aRecent in currentRecents)
		[lowerCasedCurrents addObject:[aRecent lowercaseString]];
	
	for (NSString* tagToAdd in tagsToAdd)
	{
		NSUInteger foundPosition = [lowerCasedCurrents indexOfObject:[tagToAdd lowercaseString]];
		if (foundPosition != NSNotFound)
			[currentRecents removeObjectAtIndex:foundPosition];
		else if ([currentRecents count] > 200)
			[currentRecents removeLastObject];
			
		[currentRecents insertObject:tagToAdd atIndex:0];
	}

	CFPreferencesSetAppValue(CFSTR("recentlyEnteredTags"), (CFPropertyListRef) currentRecents, CFSTR("com.openmeta.shared"));
}

//----------------------------------------------------------------------
//	synchRecentTagsPrefs
//
//	Purpose:	Call on quit, also usually call when you swap in.
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2009/01/09 
//
//----------------------------------------------------------------------
+(void)synchRecentTagsPrefs;
{
	CFPreferencesAppSynchronize(CFSTR("com.openmeta.shared"));
}
#pragma mark registering openmeta attributes
+(void)checkForRegisterDone:(NSTimer*)inTimer;
{
	NSTask* theTask = [inTimer userInfo];
	if (![theTask isRunning])
	{
		
		// delete the file - spotlight has seen what we wanted it to see...
		if ([[theTask arguments] count] > 0)
		{
			NSString* filePath = [[theTask arguments] objectAtIndex:0];
			[[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
		}
		[inTimer invalidate];
	}
}
//----------------------------------------------------------------------
//	registerOMAttributes
//
//	Purpose:	This should be called by any application that uses OpenMeta, to register the attributes that you are using with spotlight.
//				Spotlight may not 'know' about say kOMUserTags unless you set a file with some user tags so that the OpenMeta spotlight importer can
//				run on this one (fairly hidden file), which then tells spotlight to look up and use all the relevant 'stuff':
//
//				For the kOMUserTags example:
//				kOMUserTags is an array of nsstrings. So create one, tags = [NSArray arrayWithObjects:@"foo", @"bar"], and make a dictionary entry for it:
//				[myAttributeDict setObject:tags forKey:@"kOMUserTags"];
//		
//				Then add other attributes that your app uses:
//				[myAttributeDict setObject:[NSNumber numberWithFloat:2] forKey:@"kOMStarRating"];

//				Then register the types:
//				[OpenMeta registerOMAttributes:myAttributeDict forAppName:@"myCoolApp"];
//
//				Doing all of this is necc to get searches like 'rated:>4' working in spotlight, and for the item 'Rated' to show up 
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
//----------------------------------------------------------------------
+(void)registerOMAttributes:(NSDictionary*)typicalAttributes forAppName:(NSString*)appName;
{
	// the spotlight plugin is registered to only import files with openmetaschema as an extension
	appName = [appName stringByAppendingString:@".openmetaschema"];
	
	// create the file: - directory - spotlight will still import it.
	NSString* path = [@"~/Library/Application Support/OpenMeta/schemaregister" stringByExpandingTildeInPath];
	[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
	path = [path stringByAppendingPathComponent:appName];
	
	[typicalAttributes writeToFile:path atomically:YES];
	
	// get mdimport to run the file - it should do this automatically, but give it a bit 
	NSArray* args = [NSArray arrayWithObject:path];
	NSTask* importTask = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/mdimport" arguments:args];
	
	// check until it finds that the file is imported.
	[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkForRegisterDone:) userInfo:importTask repeats:YES];
}

#pragma mark private 
//----------------------------------------------------------------------
//	spotlightKey
//
//	Purpose:	if we want an array of items to be recognized by spotlight, we need to 
//				use the corect key:
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/07/17 
//
//----------------------------------------------------------------------
+(NSString*)spotlightKey:(NSString*)inKeyName;
{
	return [@"com.apple.metadata:" stringByAppendingString:inKeyName];
}

//----------------------------------------------------------------------
//	setXAttr:
//
//	Purpose:	Sets the xtended attribute on the passed file. Returns various errors
//
//	Inputs:		if items is empty or nil, the item at the passed key is removed
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/07/17 
//
//----------------------------------------------------------------------
+(OMError)setXAttr:(id)plistObject forKey:(NSString*)inKeyName url:(NSURL*)url;
{
	NSString* path = [url path];
	const char *pathUTF8 = [path fileSystemRepresentation];
	if ([path length] == 0 || pathUTF8 == nil)
	{
		return OM_ParamError;
	}
	
	// If you 'overwrite' a kMDItem* (or really com.apple.metadata:kMDItem* ) with a setxattr call, you are asking for big trouble.
	// 1) the value that you set will override the value that the spotlight importer sets on the file, so when a user changes an exif data 
	// or other thing, then this change will not be reflected in the spotlgiht DB, rather your setxattr will override it - which is totally confusing to the user, so don't do it.
	if ([inKeyName rangeOfString:@"kMDItem" options:NSLiteralSearch].location != NSNotFound)
	{
		return OM_WillNotSetkMDItemKey;
	}
	
	
	
	const char* inKeyNameC = [inKeyName fileSystemRepresentation];
	
	long returnVal = 0;
	
	// always set data as binary plist.
	NSData* dataToSendNS = nil;
	if (plistObject)
	{
		NSString *error = nil;
		dataToSendNS = [NSPropertyListSerialization dataFromPropertyList:plistObject
																				format:kCFPropertyListBinaryFormat_v1_0
																				errorDescription:&error];
		if (error)
		{
			[error release];
			[dataToSendNS release];
			dataToSendNS = nil;
			return OM_NoDataFromPropertyListError;
		}
	}
	
	
	if (dataToSendNS)
	{
		// also reject for tags over the maximum size:
		if ([dataToSendNS length] > kMaxDataSize)
			return OM_MetaTooBigError;
		
		returnVal = setxattr(pathUTF8, inKeyNameC, [dataToSendNS bytes], [dataToSendNS length], 0, XATTR_NOFOLLOW);
	}
	else
	{
		returnVal = removexattr(pathUTF8, inKeyNameC, XATTR_NOFOLLOW);
	}
	
	// only backup kOM - open meta stuff. 
	if ([inKeyName hasPrefix:@"kOM"] || [inKeyName hasPrefix:[self spotlightKey:@"kOM"]])
		[OpenMetaBackup backupMetadata:[url path]]; // backup all meta data changes. 
	
	if (returnVal == 0)
		return OM_NoError;
	
	return errno;
}

//----------------------------------------------------------------------
//	getXAttr
//
//	Purpose:	returns attribute
//
//	Inputs:		
//
//	Outputs:	plist object - whether nsarray (often) or nsstring, dictionary, number... 
//
//  Created by Tom Andersen on 2008/07/17 
//
//----------------------------------------------------------------------
+(id)getXAttr:(NSString*)inKeyName url:(NSURL*)url errorCode:(OMError*)errorCode;
{
	// we can't put restore meta here - as restoreMetadata calls us! 
	// I put the restore on the usertags and ratings. Users will have to manually call restore for other keys 
	//[OpenMetaBackup restoreMetadata:[url path]];
	
	NSString* path = [url path];
	const char *pathUTF8 = [path fileSystemRepresentation];
	if ([path length] == 0 || pathUTF8 == nil)
	{
		if (errorCode)
			*errorCode = OM_ParamError;
		return nil;
	}
	
	const char* inKeyNameC = [inKeyName fileSystemRepresentation];
	// retrieve data from store. 
	char* data[kMaxDataSize];
	ssize_t dataSize = kMaxDataSize; // ssize_t means SIGNED size_t as getXattr returns - 1 for no attribute found
	NSData* nsData = nil;
	dataSize = getxattr(pathUTF8, inKeyNameC, data, dataSize, 0, XATTR_NOFOLLOW);
	if (dataSize > 0)
	{
		nsData = [NSData dataWithBytes:data	length:dataSize];
	}
	else
	{
		if (*errorCode != ENOATTR) // it is not an error to have no attribute set 
			*errorCode = errno; // Most common ENOATTR - the attribute is not set on the file.
		return nil;
	}
	
	// ok, we have some data 
	NSPropertyListFormat formatFound;
	NSString* error;
	id outObject = [NSPropertyListSerialization propertyListFromData:nsData mutabilityOption:kCFPropertyListImmutable format:&formatFound errorDescription:&error];
	if (error)
	{
		[error release];
		if (errorCode)
			*errorCode = OM_NoDataFromPropertyListError;
		return nil;
	}
	
	if (errorCode)
		*errorCode = OM_NoError;
	return outObject;
}

//----------------------------------------------------------------------
//	validateAsArrayOfStrings
//
//	Purpose:	
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/06/14 
//
//----------------------------------------------------------------------
+(BOOL)validateAsArrayOfStrings:(NSArray*)array;
{
	if (![array isKindOfClass:[NSArray class]])
		return NO;
	
	NSEnumerator* enumerator = [array objectEnumerator];
	NSString* aString;
	while (aString = [enumerator nextObject])
	{
		if (![aString isKindOfClass:[NSString class]])
			return NO;
	}
	return YES;
}

//----------------------------------------------------------------------
//	orderedArrayWithDict
//
//	Purpose:	preserve order: The dict has the tags we want, while the sort hint is a superset of the tags, with the order correct
//
//	Inputs:		
//
//	Outputs:	
//
//  Created by Tom Andersen on 2008/11/25 
//
//----------------------------------------------------------------------
+(NSArray*)orderedArrayWithDict:(NSDictionary*)inTags sortHint:(NSArray*)inSortedItems;
{
	if ([inSortedItems count] == 0)
		return [inTags allValues];
	
	NSMutableDictionary* tagsWeWant = [NSMutableDictionary dictionaryWithDictionary:inTags];
	NSMutableArray* orderedArray = [NSMutableArray arrayWithCapacity:[inTags count]];
	for (NSString* aTag in inSortedItems)
	{
		if ([tagsWeWant objectForKey:[aTag lowercaseString]])
		{
			[tagsWeWant removeObjectForKey:[aTag lowercaseString]];
			[orderedArray addObject:aTag];
		}
	}
	
	// if the sort hint was deficient in some way, just add the remaining ones in.
	if ([tagsWeWant count] > 0)
		[orderedArray addObjectsFromArray:[tagsWeWant allValues]];
	
	return [NSArray arrayWithArray:orderedArray];
}

// turn umlats, etc into same format as file sys uses. There are two ways to represent ü , etc. (single or multiple code points in utf (8)).
+(NSArray*)decomposeArrayOfStrings:(NSArray*)inTags;
{
	NSMutableArray* outArray = [NSMutableArray arrayWithCapacity:[inTags count]];
	for (NSString* aTag in inTags)
		[outArray addObject:[aTag decomposedStringWithCanonicalMapping]];
	
	return outArray;
}

//----------------------------------------------------------------------
//	removeDuplicateTags
//
//	Purpose:	case preserving case insensitive removal of duplicate tags
//
//	Inputs:		
//
//	Outputs: Also decomposes the strings to a standardized UTF8 representation	
//
//  Created by Tom Andersen on 2008/07/17 
//
//----------------------------------------------------------------------
+(NSArray*)removeDuplicateTags:(NSArray*)tags;
{
	if (tags == nil)
		return nil;
	
	// we always store tags as decomposed UTF-8 strings:
	// turn umlats, etc into same format that the file system uses, for consistency 
	tags = [self decomposeArrayOfStrings:tags];
	
	NSMutableDictionary* dict = [NSMutableDictionary dictionary];
	for (NSString* aTag in tags)
		[dict setObject:aTag forKey:[aTag lowercaseString]];
	
	// preserve order.
	return [self orderedArrayWithDict:dict sortHint:tags];
}

@end
