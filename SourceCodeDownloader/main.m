//
//  main.m
//  SourceCodeDownloader
//
//  Created by Bluelich on 28/12/2017.
//  Copyright © 2017 Bluelich. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Downloader.h"

int main(int argc, const char * argv[]) {
    [Downloader downloadViaJSON];
    [NSRunLoop.currentRunLoop run];
    return 0;
}
