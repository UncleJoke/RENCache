//
//  RENCache.m
//  RENCacheDemo
//
//  Created by renlei on 15/6/12.
//  Copyright (c) 2015年 renlei. All rights reserved.
//

#import "RENCache.h"

static NSString *const kDefaultPlist = @"RENCache.plist";

static inline NSString *defaultCachePath() {
    NSString *cachesDirectory = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
    return  [[[cachesDirectory stringByAppendingPathComponent:[[NSProcessInfo processInfo] processName]] stringByAppendingPathComponent:@"RENCache"] copy];
}

static inline NSString *cachePathForKey(NSString* key) {
    return [[defaultCachePath() stringByAppendingPathComponent:key] copy];
}

@interface RENCache ()

/// 磁盘中的缓存，plist管理
@property (strong, nonatomic) NSMutableDictionary *diskCachePlist;

@property (strong, nonatomic) dispatch_queue_t cacheInfoQueue;

@property (strong, nonatomic) NSCache *memoryCache;

@end

@implementation RENCache

- (void)dealloc {
    
    [[NSNotificationCenter defaultCenter]
     removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

- (instancetype)init {
    
    if (self = [super init]) {
        
        _cacheInfoQueue = dispatch_queue_create("com.rencache.info", NULL);
        dispatch_queue_t priority = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        dispatch_set_target_queue(priority, _cacheInfoQueue);
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearMemoryCache) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        
        _defaultTimeoutInterval = 0;
        _defaultCacheMemoryLimit = 10;
        
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = _defaultCacheMemoryLimit;
        
        _diskCachePlist = [NSMutableDictionary dictionaryWithContentsOfFile:cachePathForKey(kDefaultPlist)];

        if (!_diskCachePlist) {
            
            _diskCachePlist = [[NSMutableDictionary alloc] init];
        }
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        if([fileManager fileExistsAtPath:defaultCachePath()]) {
            
            NSMutableArray *removedKeys = [[NSMutableArray alloc] init];
            
            NSTimeInterval now = [[NSDate date] timeIntervalSinceReferenceDate];
            
            dispatch_sync(_cacheInfoQueue, ^{
                
                BOOL isChange = NO;
                for(NSString *key in _diskCachePlist.allKeys) {
                    
                    if ([_diskCachePlist[key] isKindOfClass:[NSDate class]]) {
                        
                        if([_diskCachePlist[key] timeIntervalSinceReferenceDate] <= now) {
                            
                            isChange = YES;
                            [fileManager removeItemAtPath:cachePathForKey(key) error:NULL];
                            [removedKeys addObject:key];
                        }
                    }
                }
                if (isChange) {
                    [_diskCachePlist writeToFile:cachePathForKey(kDefaultPlist) atomically:YES];
                }
            });
        } else {
            
            [fileManager createDirectoryAtPath:defaultCachePath() withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    return self;
}

+ (RENCache *)sharedGlobalCache {
    
    static RENCache *instanceCache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instanceCache = [[self alloc] init];
    });
    
    return instanceCache;
}
#pragma mark -
#pragma mark - cacheSize methods
- (NSUInteger)getAllCacheCount {
    
    return _diskCachePlist.count;
}

#pragma mark -
#pragma mark - cacheSize methods
- (NSUInteger)getAllCacheSize {
    
    NSUInteger size = 0;
    
    for (NSString *key in [self allKeys]) {
        
        NSString *path = cachePathForKey(key);
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        size += [attrs fileSize];
    }
    return size;
}

- (NSUInteger)getSingleCacheSizeForKey:(NSString *)key {
    
    NSUInteger size = 0;
    
    NSFileManager* manager = [NSFileManager defaultManager];
    
    if ([manager fileExistsAtPath:cachePathForKey(key)]) {
        
        size = ([[manager attributesOfItemAtPath:cachePathForKey(key) error:nil] fileSize]);
    }
    return size;
}

#pragma mark -
#pragma mark - getAllKeys methods
- (NSArray *)allKeys {
    
    return [_diskCachePlist allKeys];
}


#pragma mark -
#pragma mark - has methods
- (BOOL)hasCacheForKey:(NSString *)key {
    
    __block BOOL res = NO;
    dispatch_sync(_cacheInfoQueue, ^{
        
        res = [[NSFileManager defaultManager] fileExistsAtPath:cachePathForKey(key)];
    });
    return res;
}

#pragma mark -
#pragma mark - remove methods
- (void)clearAllCache {
    
    dispatch_sync(_cacheInfoQueue, ^{
        
        for(NSString* key in _diskCachePlist) {
            [[NSFileManager defaultManager] removeItemAtPath:cachePathForKey(key) error:NULL];
        }
        
        [_diskCachePlist removeAllObjects];
        [_diskCachePlist writeToFile:cachePathForKey(kDefaultPlist) atomically:YES];
        [self clearMemoryCache];
    });
    
}

- (void)clearMemoryCache {
    
    [_memoryCache removeAllObjects];
    
}

- (void)removeCacheForKey:(NSString *)key {
    
    NSAssert(![key isEqualToString:kDefaultPlist] , @"RENCache.plist 不可以删除");
    
    dispatch_async(_cacheInfoQueue, ^{
        
        [[NSFileManager defaultManager] removeItemAtPath:cachePathForKey(key) error:NULL];
        [_diskCachePlist removeObjectForKey:key];
        [_diskCachePlist writeToFile:cachePathForKey(kDefaultPlist) atomically:YES];
        
        [_memoryCache removeObjectForKey:key];
        
    });
}

#pragma mark -
#pragma mark - image methods
- (UIImage *)imageObjectForKey:(NSString *)key {
    
    UIImage *image = nil;
    
    if (key) {
        
        NSData *data = [self objectForKey:key];
        
        if (data) {
            image =  [UIImage imageWithData:data];
        }
    }
    return image;
}
- (void)setImage:(UIImage *)image forKey:(NSString *)key {
    
    [self setImage:image forKey:key withTimeoutInterval:0];
    
}
- (void)setImage:(UIImage *)image forKey:(NSString *)key withTimeoutInterval:(NSTimeInterval)timeoutInterval {
    
    if (!image || !key) {
        return;
    }
    
    NSData *data = UIImagePNGRepresentation(image);
    data = data?data:UIImageJPEGRepresentation(image, 1.0f);
    [self setObjectValue:data forKey:key withTimeoutInterval:timeoutInterval];
}

#pragma mark -
#pragma mark - object methods
- (id)objectForKey:(NSString *)key {
    
    if (key) {
        
        if ([_memoryCache objectForKey:key]) {
            
            return [_memoryCache objectForKey:key];
        }
        
        if ([self hasCacheForKey:key]) {
            
            NSData *data = [NSData dataWithContentsOfFile:cachePathForKey(key) options:0 error:NULL];
            
            if (data) {

                return [NSKeyedUnarchiver unarchiveObjectWithData:data];
            }
        }
    }
    
    return nil;
}

- (void)setObjectValue:(id)value forKey:(NSString *)key {
    
    [self setObjectValue:value forKey:key withTimeoutInterval:_defaultTimeoutInterval];
}

- (void)setObjectValue:(id)value forKey:(NSString *)key withTimeoutInterval:(NSTimeInterval)timeoutInterval {
    
    if (!value || !key) {
        return;
    }
    
    [_memoryCache setObject:value forKey:key];
    
    [self setDataValue:[NSKeyedArchiver archivedDataWithRootObject:value] forKey:key withTimeoutInterval:timeoutInterval];
}

#pragma mark -
#pragma mark - data methods
- (void)setDataValue:(NSData *)value forKey:(NSString*)key withTimeoutInterval:(NSTimeInterval)timeoutInterval {
    
    NSAssert(![key isEqualToString:kDefaultPlist] , @"RENCache.plist 不可保存或修改默认的plist");
    
    dispatch_sync(_cacheInfoQueue, ^{
        
        [value writeToFile:cachePathForKey(key) atomically:YES];
        id obj = timeoutInterval > 0 ? [NSDate dateWithTimeIntervalSinceNow:timeoutInterval] : @0;
        [_diskCachePlist setObject:obj forKey:key];
        [_diskCachePlist writeToFile:cachePathForKey(kDefaultPlist) atomically:YES];
    });
    
}

#pragma mark -
#pragma mark - CacheMemoryLimit
- (void)setDefaultCacheMemoryLimit:(NSInteger)defaultCacheMemoryLimit {
    _defaultCacheMemoryLimit = defaultCacheMemoryLimit;
    _memoryCache.countLimit = defaultCacheMemoryLimit;
}

@end
