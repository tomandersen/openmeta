#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h> 

/* -----------------------------------------------------------------------------
   Step 1
   Set the UTI types the importer supports
  
   Modify the CFBundleDocumentTypes entry in Info.plist to contain
   an array of Uniform Type Identifiers (UTI) for the LSItemContentTypes 
   that your importer can handle
   
   -- Tom Dec 15 2008 - Added com.openmeta.openmetaschema to the document types in info.plist
  
   ----------------------------------------------------------------------------- */

/* -----------------------------------------------------------------------------
   Step 2 
   Implement the GetMetadataForFile function
  
   Implement the GetMetadataForFile function below to scrape the relevant
   metadata from your document and return it as a CFDictionary using standard keys
   (defined in MDItem.h) whenever possible.
   
   -- Tom Dec 15 2008 - See comments in this GetMetadataForFile. 
   
   ----------------------------------------------------------------------------- */

/* -----------------------------------------------------------------------------
   Step 3 (optional) 
   If you have defined new attributes, update the schema.xml file
  
   Edit the schema.xml file to include the metadata keys that your importer returns.
   Add them to the <allattrs> and <displayattrs> elements.
  
   Add any custom types that your importer requires to the <attributes> element
  
   <attribute name="com_mycompany_metadatakey" type="CFString" multivalued="true"/>
  
   ----------------------------------------------------------------------------- */



/* -----------------------------------------------------------------------------
    Get metadata attributes from file
   
   This function's job is to extract useful information your file format supports
   and return it as a dictionary
   ----------------------------------------------------------------------------- */

Boolean GetMetadataForFile(void* thisInterface, 
			   CFMutableDictionaryRef attributes, 
			   CFStringRef contentTypeUTI,
			   CFStringRef pathToFile)
{
	/* Pull any available metadata from the file at the specified path */
    /* Return the attribute keys and attribute values in the dict */
    /* Return TRUE if successful, FALSE if there was no data provided */
    
	// the idea is that we want have the importer run on our file type - "com.ironic.openmetaschema"
	// WITH only one  ".openmetaschema" file on the computer. What this does is make the Spotlight metadata engine look at the 
	// open meta schema file, and generate entries in the user interface and file system where appropriate.
	
	// The end result is that we allow users to search for "Tags:foobar" in the spotlight top right (leopard - snow leopard) 
	// spotlight search area, and only search for files with a kOMUserTags of foobar.
	
	// The idea is for Tagger or some other OpenMeta application to have this spotlight plugin installed, then create just one
	// file in a relatively out of the way place called for example "schemaDefs.openmetaschema" Then this spotlight plugin will run, installing all of the 
	// OpenMeta schema info into the spotlight system.
	CFMutableArrayRef tags = CFArrayCreateMutable(nil, 20, &kCFTypeArrayCallBacks);
	CFArrayAppendValue(tags, CFSTR("openmeta567778"));
	CFArrayAppendValue(tags, CFSTR("openmeta22"));
	
	CFDictionarySetValue(attributes, CFSTR("kOMUserTags"), tags);
    return TRUE;
	
	
	// I am not sure if I actually have to return a document with entries, I try it without. 
    return FALSE;
}
