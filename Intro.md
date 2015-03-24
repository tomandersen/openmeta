# Introduction #

OpenMeta uses setxattr(), getxattr() in a consistent manner to set and retrieve tags, ratings, and other metadata.


# Details #

Please feel free to download and evaluate the source - which I should have up in Dec 2008:
  * Initially, all changes will go through me (tom), but if it gets busy I would not mind any help!

Basically, OpenMeta will:

1) Allow programs to set/retrieve tags, ratings, etc on files using a simple API. This api will enforce a few 'rules' about tags - (eg no duplicates, case insensitive, case preserving, etc). Rules are generally 'good' - they allow for consistent user experiences.

2) These tags are automatically indexed with Spotlight.

3) Uses no Apple 'secret' api.

4) Allows the setting of (non spotlight indexed) 'larger but still small (<4k)' blobs of meta data, such as workflows , etc.

There are a few 'gotchas' that we found while working this all out, which is one reason why we thought it was important to not only release the idea, but also some source to implement it.

There are more and more applications using OpenMeta: See OpenMetaApplications.