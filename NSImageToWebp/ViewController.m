//
//  ViewController.m
//  NSImageToWebp
//
//  Created by great Lock on 2018/6/10.
//  Copyright © 2018年 great Lock. All rights reserved.
//

#import "ViewController.h"
#import "NSImage+Webp.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSImage *image = [NSImage imageNamed:@"3.jpeg"];
    NSData *webpData = [image toWebpImageDataWithLossLess:false quality:0.01f];
    [webpData writeToFile:@"/Users/greatlock/Desktop/1.webp" atomically:true];
}

@end
