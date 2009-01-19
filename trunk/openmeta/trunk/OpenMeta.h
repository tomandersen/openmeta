//
//  OpenMeta.h
//  OpenMeta
//
//  Created by Tom Andersen on 17/07/08.
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

#import <Cocoa/Cocoa.h>

/*
        Open Meta - why duplicate attributes that are already defined?
        
        To answer this, look at an example. kMDItemKeywords:
        
        When a file with keywords embedded in it is created or lands on the computer, say for example a PDF file, Spotlight
        will import it. The keywords will be stored under kMDItemKeywords in the Spotlight DB. 
        
        Now a user wants to set keywords (ie tags) on a file - any file on their computer - whether or not
        the file type supports keywords or not. If Open Meta used kMDItemKeywords to store these - it will work pretty well,
        until the user stored their own tags, on that PDF file that already had embedded keywords. Then all sorts of problems happen:
        1) The existing keywords are hidden from the user, as keywords set on the xattr will override the ones set in the meta data. 
        2) These hidden keywords will come back when the file is viewed with Preview, or Acrobat, etc. 
        3) If the keywords on the the file are changed inside Preview, then these changes will not show up in spotlight
        
        There are two solutions to this sort of problem. 
        
        One is to edit the 'actual keywords' inside the PDF. This solution quickly gets
        complicated, as for each file type there may be none (eg: text file), one (eg:PDF), several (eg: jpeg, word?) 
        places to store keywords, and the software to read and write keywords into all supported file types 
        quickly grows to be unmanagable. The solution for text and other non keywordable files 
        is to write the tags somewhere else (eg sidecar files). 
        
        The other solution is the tact taken by Open Meta. 
        Keywords are written to their own tag, which is indexed by Spotlight, (kOMUserTags). 
        These tags are independent of kMDItemkeywords. 
        They can be written in the exact same very simple manner to each and every file on the file system. 
        They do not hide the keywords set on the file. 
        Since they are stored in xattrs, they can easily be included or excluded from a file, when 
        that file is for instance shipped off to a third party. 
        This is useful in order to keep metadata 'in house'. BUT - the data set by OpenMeta is not 'in the file' the same 
        way that tags set on a jpeg are 'in' the EXIF portion of the file when bridge does it. 
        The Open Meta tags follow the file around on the OS - through backups, copies and moves. 
        
        This argument holds for many types of meta data. 
        
        What about namespaces?
        ----------------------
        Open Meta is a clean simple way to set user entered searchable metadata on any file on Mac OS X. 
        Concepts like namespaces are not encouraged, as most users have no idea what a namespace is. The tradeoff is a 
        small amount of _understandable_ ambiguity - searching for Tags:apple (i.e. kOMUserTags == "apple"cd) will find
        all files having to do with both the fruit one can eat, and the company that makes computers. Users expect this. 
        With namespaces an improperly constructed query will usually result in 'no matches'. 
*/


/*
    Note on Backup - "Time Machine", etc.
    When you set an xattr on a file, the modification date on the file is NOT changed, 
    but something called the status change time - does change.
    Time Machine, however, will only back up on modified time changes - i.e. it only looks at st_mtimespec, ignoring st_ctimespec. 
    This is a deliberate decision on TimeMachine's part.
    So if you want your xattrs backed up - you need to set the modifcation date on the file to a newer date - utimes() is the call for this. 
    It may be that you do not want to change the file modification date for each OpenMeta item that you write. If you do change the modification date, 
    it may make sense to not change it 'by much' - thus preserving most of the 
    meaning of the modification date, while still allowing TimeMachine to back the file up.
    
    You could/should ? also offer bulk backup of xattrs by creating a dictionary file of 
    paths (alias data) and xattrs that you would like to backup. A file like this
    will of course be backed up by time machine.
*/


// OpenMeta: Open metadata format for OS X. Data is stored in xattr.
// Some items are reflected in the Spotlight Database, others not. 
// ---------------------
// This system allows someone to set metadata on a file, and have that metadata searchable in spotlight.
// Several open meta keys are defined: See the schema.xml file in the OpenMeta spotlight plugin for the complete list.
// 
// User Entered Tags: Tags that users have added for workflow and organizational reasons. 
//
// Bookmarks: URLs associated with a document
// 
// Workflow: people, companies, etc that are in the workflow for this document
//
// Projects: Projects that this file is relevant to

// error codes
typedef long OMError;
// on success return 0
// If setting/getting user tags failed we return a negative error code for one of our errors, or the error code from the underlying api (currently setxattr)
// If there is errno set after a call we return that. errno codes seem to be positive numbers
#define OM_NoError (0)
#define OM_ParamError (-1)
#define OM_NoDataFromPropertyListError (-2)
#define OM_NoMDItemFoundError (-3)
#define OM_CantSetMetadataError (-4)
#define OM_MetaTooBigError (-5)
#define OM_WillNotSetkMDItemKey (-6)
// OM_MetaDataNotChanged is returned from addUserTags if nothing had to be done.
#define OM_MetaDataNotChanged (-7) 
// A very common error code is ENOATTR - the attribute is not set on the file. 

extern NSString* const kOMUserTags;
extern NSString* const kOMBookmarks; // list of urls - bookmarks as nsarray nsstring 
extern NSString* const kOMApproved;
extern NSString* const kOMWorkflow;
extern NSString* const kOMProjects;
extern NSString* const kOMStarRating;	// ns number - 0 to 5 (i guess floats are allowed)- (itunes apparently also stores ratings as 0 to 100?)
extern NSString* const kOMHidden;
extern const double kOMMaxRating;

// kMDItemKeywords
@interface OpenMeta : NSObject {

}

// User tags - an array of tags as entered by the user. This is not the place to 
// store program generated gook, like GUIDs or urls, etc.
// It is not nice to erase tags that are already set (unless the user has deleted them using your UI)
// so ususally you would do a getUserTags, then merge/edit/ etc, followed by a setUserTags
// Tags - NSStrings - conceptually utf8 - any characters allowed, spaces, commas, etc.
// Case sensitive or not? Case preserving. Order of tags is not guaranteed.
// setUserTags will remove duplicates from the array, using case preserving rules. 
+(OMError)setUserTags:(NSArray*)tags url:(NSURL*)url;
+(NSArray*)getUserTags:(NSURL*)url errorCode:(OMError*)errorCode;
+(OMError)addUserTags:(NSArray*)tags url:(NSURL*)url; // returns OM_MetaDataNotChanged if no tags needed to be added
+(OMError)clearUserTags:(NSArray*)tags url:(NSURL*)url;// returns OM_MetaDataNotChanged if no tags cleared


+(NSArray*)urlsFromFilePaths:(NSArray*)inFilePaths;

// To change tags on groups of files: 
// You first obtain the common tags in a list of files, 
// then edit those common tags, then set the changes
// you need to pass in the original common tags when writing the new tags out, 
// so that we can be sure we are not overwriting other changes made by other users, etc 
// during the edit cycle:
// These calls are case preserving and case insensitive. So Apple and apple will both be the 'same' tag on reading
+(OMError)setCommonUserTags:(NSArray*)urls originalCommonTags:(NSArray*)originalTags replaceWith:(NSArray*)newTags;
+(NSArray*)getCommonUserTags:(NSArray*)urls errorCode:(OMError*)errorCode;


// Ratings are 0 - 5 stars. If a rating on a file is not set, that is different from 0
// so - you need to check the error returned by getRating in order to find out if the rating was really there
// rating is 0 - 5 floating point, so you have plenty of room. I clamp 0 - 5 on setting it.
// passing kRatingNotSet to setRating removes the rating. Also I return kRatingNotSet if I can't find a rating.
+(OMError)setRating:(double)rating05 url:(NSURL*)url;
+(double)getRating:(NSURL*)url errorCode:(OMError*)errorCode;

// simplest way to set metadata that will be picked up by spotlight:
// The string will be stored in the spotlight datastore. Likely you will not want 
// to set large strings with this, as it will be hard on the spotlight db.
+(OMError)setString:(NSString*)string keyName:(NSString*)keyName url:(NSURL*)url;
+(NSString*)getString:(NSString*)keyName url:(NSURL*)url errorCode:(OMError*)errorCode;

// hide adds a key to the Database kOMHidden = "YES"
// unhide removes the key. 
// Hidden is meant to be applied on a file by file basis by a user. 
// The hide will follow the user around
// ----------------------------------
+(OMError)hide:(NSURL*)url;
+(OMError)unhide:(NSURL*)url;
+(BOOL)isHidden:(NSURL*)url errorCode:(OMError*)errorCode;

// If you have a 'lot' (ie 200 bytes to 4k) to set as a metadata on a file, then what you want to do
// is use the setDictionaries call. You organize your data in an array of dictionaries, 
// and each dict will be put into the metadata store and NOT be indexed by spotlight. 
// In each dictionary, you set one item with the key @"name" and THAT information will be stored in the spotlight DB
// the 'name' would usually be used for search purposes. Other data can be 'anything'

// arrays of dictionaries:
// Spotlight can't have dictionaries in it's database. 
// We can store an array of dictionaries, and in spotlight have an array of names of the
// dictionaries. The names are assumed to be in each dictionary, with the key @"name"
// @"name" can be a string (usually), date, or nsnumber.  
+(OMError)setDictionaries:(NSArray*)arrayOfDicts keyName:(NSString*)keyName url:(NSURL*)url;
+(NSArray*)getDictionaries:(NSString*)keyName url:(NSURL*)url errorCode:(OMError*)errorCode;
+(NSArray*)getDictionariesNames:(NSString*)keyName url:(NSURL*)url errorCode:(OMError*)errorCode; // returns array of names as strings, dates, or numbers

// optional keys on any dict
//					key "date" the date of the request time set, etc.


// kOMBookmarks -	array of dictionaries
//					key "name" searchable user entered name - page name, etc 
//					key "url"	the url that the bookmark points to

// kOMApproved -	array of dictionaries
//					key "name" searchable name like "jim simpson" or "talisker" 
//					key "date" the date of the approval

// kOMWorkflow -	array of dictionaries
//					key "name" searchable name like "jim simpson" or "taligent" 
//					key "what" what needs done by that person/company - user entered - no robot commands!
//					key "duedate" the due date of the request
//					key "auto" dictionary of instructions for an automatic or robotic task

// kOMProjects -	array of dictionaries (AKA cases in legal world)
//					key "name" searchable name like "sampson" or "Orion Project" 

// for meta data in arrays: The add call weeds out duplicates 
+(NSArray*)getNSArrayMetaData:(NSString*)metaDataKey url:(NSURL*)url errorCode:(OMError*)errorCode;
+(OMError)setNSArrayMetaData:(NSArray*)array metaDataKey:(NSString*)metaDataKey url:(NSURL*)url;
+(OMError)addToNSArrayMetaData:(NSArray*)itemsToAdd metaDataKey:(NSString*)metaDataKey url:(NSURL*)url;


// extended attributes:
// These getters and setters are to set xattr data that will be read and indexed by spotlight
// If you pass large amounts of data or objects like dictionaries that spotlght cannot index, results are undefined.
// The only things that spotlight can handle (as far as I know) are small arrays and nsstrings. 
+(id)getXAttrMetaData:(NSString*)metaDataKey url:(NSURL*)url errorCode:(OMError*)errorCode;
+(OMError)setXAttrMetaData:(id)plistObject metaDataKey:(NSString*)metaDataKey url:(NSURL*)url;

// These getters and setters are to set xattr data that will be NOT read and indexed by spotlight
// The passed plist object will be converted to data as a binary plist object. (plist object is for example an nsdictionary or nsarray)
// You can pass data up to 4k (or close to that depending on how much the data takes up in binary plist format)
+(id)getXAttr:(NSString*)inKeyName url:(NSURL*)url errorCode:(OMError*)errorCode;
+(OMError)setXAttr:(id)plistObject forKey:(NSString*)inKeyName url:(NSURL*)url;


// utils
+(NSArray*)orderedArrayWithDict:(NSDictionary*)inTags sortHint:(NSArray*)inSortedItems;

// prefs support - this allows a common set of recently entered tags to be kept:
// recently entered tags support:
+ (NSArray*)recentTags;		// an array of NSStrings, sorted by most recently added at the top. Case preserved.
// this call is how you maintain the list of recent tags. When a user edits a list of tags on a doc, pass in the originals as 'old' and the entire set of changed ones as new. 
+ (void)updatePrefsNewTags:(NSArray*)oldTags newTags:(NSArray*)newTags;
+ (void)synchRecentTagsPrefs;


@end
