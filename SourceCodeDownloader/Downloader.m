//
//  Downloader.m
//  SourceCodeDownloader
//
//  Created by Bluelich on 28/12/2017.
//  Copyright © 2017 Bluelich. All rights reserved.
//

#import "Downloader.h"
#import "Ono.h"
#import <pthread.h>
#import "tarballs.h"

NSString *opensource_apple_com_tarballs = @"https://opensource.apple.com/tarballs/";

@interface NSArray (index)
- (id)safe_objectAtIndex:(NSUInteger)index;
@end
@implementation NSArray(index)
- (id)safe_objectAtIndex:(NSUInteger)index
{
    if (index >= self.count) {
        return nil;
    }
    return [self objectAtIndex:index];
}
@end
@interface NSString (compare)
- (BOOL)isNewerThan:(NSString *)obj;
@end
@implementation NSString (compare)
- (BOOL)isNewerThan:(NSString *)obj
{
    if (!obj) {
        return YES;
    }
    NSArray *array_self = [self componentsSeparatedByString:@"."];
    NSArray *array_obj  = [obj  componentsSeparatedByString:@"."];
    NSUInteger max = MAX(array_self.count, array_obj.count);
    for (int i = 0; i < max; i++) {
        NSString *v_self = [array_self safe_objectAtIndex:i];
        NSString *v_obj  = [array_obj  safe_objectAtIndex:i];
        if ([v_self isEqualToString:v_obj]) {
            continue;
        }
        return [v_self compare:v_obj options:NSNumericSearch] == NSOrderedDescending;
    }
    return NO;
}
@end
@implementation Downloader
+ (void)downloadViaJSON
{
    NSString *path = [[[NSHomeDirectory() stringByAppendingPathComponent:@"Code"] stringByAppendingPathComponent:@"apple.opensource"] stringByAppendingPathComponent:@"tarballs"];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSError *error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{} error:&error]) {
            printf("error:%s",error.description.UTF8String);
            return;
        }
    }
    NSData *data = [allTarballs dataUsingEncoding:NSUTF8StringEncoding];
    NSArray<NSString *> *tarballs = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    //因为CLT的某些原因,最好是一次只创建一个下载任务
    __block pthread_mutex_t lock;
    pthread_mutex_init(&lock, NULL);
    [tarballs enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        pthread_mutex_lock(&lock);
        NSString *fileName = [obj componentsSeparatedByString:@"/"].lastObject;
        NSString *dstPath = [path stringByAppendingFormat:@"/%@",fileName];
        if (![NSFileManager.defaultManager fileExistsAtPath:dstPath]) {
            printf("download started:%s\t",fileName.UTF8String);
            [[[NSURLSession sharedSession] downloadTaskWithURL:[NSURL URLWithString:obj] completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                NSError *err = nil;
                if (!location) {
                    printf("tmp file location miss\n");
                    return;
                }
                if (![NSFileManager.defaultManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:dstPath] error:&err]) {
                    printf("error:%s\n\n",err.description.UTF8String);
                }else{
                    printf("success\n\n");
                }
                pthread_mutex_unlock(&lock);
            }]resume];
        }else{
            printf("file exists:%s\n\n",fileName.UTF8String);
            pthread_mutex_unlock(&lock);
        }
    }];
    pthread_mutex_destroy(&lock);
    printf("completed");
}
+ (void)start
{
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:opensource_apple_com_tarballs] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (data.length == 0) {
            printf("error:%s\n",error.description.UTF8String);
            return;
        }
        [Downloader parserList:data];
    }]resume];
}
+ (void)parserList:(NSData *)listData
{
    NSArray<NSString *>  *list = [self listFromData:listData url:nil];
    NSMutableArray<NSString *>  *tarballs = [NSMutableArray array];
    [list enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:obj]];
        NSString *tarball = [self getLatestFileURLFromSubList:data url:obj];
        [tarballs addObject:tarball];
    }];
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES).lastObject stringByAppendingString:@"/tarballs.json"];
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:tarballs options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted error:&error];
    [data writeToFile:path atomically:YES];
    printf("success\n");
}
+ (NSString *)getLatestFileURLFromSubList:(NSData *)data url:(NSString *)url
{
    NSArray<NSString *> *tarballs = [self listFromData:data url:url];
    __block NSString *tarball = nil;
    __block NSString *latestVersion = nil;
    [tarballs enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *version = [[obj componentsSeparatedByString:@"-"].lastObject stringByReplacingOccurrencesOfString:@".tar.gz" withString:@""];
        if (!latestVersion) {
            latestVersion = version;
            tarball = obj;
        }else{
            if ([version isNewerThan:latestVersion]) {
                printf("%s > %s\n",version.UTF8String,latestVersion.UTF8String);
                latestVersion = version;
                tarball = obj;
            }else{
                printf("%s <= %s\n",version.UTF8String,latestVersion.UTF8String);
            }
        }
    }];
    printf("\n");
    return tarball;
}
+ (NSArray<NSString *> *)listFromData:(NSData *)data  url:(NSString *)url
{
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    NSError *error = nil;
    ONOXMLDocument *document = [ONOXMLDocument HTMLDocumentWithData:data error:&error];
    for (ONOXMLElement *obj in [document XPath:@"//table[1]//tr"]){
        NSArray<ONOXMLElement *> *tds = obj.children;
        if (tds.count != 3) {
            continue;
        }
        ONOXMLElement *td = tds[1];
        if (![td.tag isEqualToString:@"td"]) {
            continue;
        }
        ONOXMLElement *a = td.children.firstObject;
        if (![a.tag isEqualToString:@"a"]) {
            continue;
        }
        NSString *href = [a.attributes objectForKey:@"href"];
        if (href.length == 0 || [href hasPrefix:@"."]) {
            continue;
        }
        NSString *link = nil;
        if (url) {
            link = [url stringByAppendingString:href];
        }else{
            link = [opensource_apple_com_tarballs stringByAppendingString:href];
        }
        [list addObject:link];
    }
    return list.copy;
}
@end
