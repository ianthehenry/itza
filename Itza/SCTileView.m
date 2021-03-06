//
//  SCTileView.m
//  Itza
//
//  Created by Ian Henry on 4/6/14.
//  Copyright (c) 2014 Ian Henry. All rights reserved.
//

#import "SCTileView.h"
#import "SCTile.h"

@interface SCTileView ()

@property (nonatomic, strong, readwrite) UILabel *label;

@end

@implementation SCTileView

- (id)initWithApothem:(CGFloat)apothem {
    if (self = [super initWithApothem:apothem]) {
        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_label];
    }
    return self;
}

@end
