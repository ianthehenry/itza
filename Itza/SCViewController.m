//
//  SCViewController.m
//  Itza
//
//  Created by Ian Henry on 4/2/14.
//  Copyright (c) 2014 Ian Henry. All rights reserved.
//

#import "SCViewController.h"
#import "SCScrollView.h"
#import "SCTileView.h"
#import "SCCity.h"
#import "SCRadialMenuView.h"
#import "SCPassthroughView.h"
#import "SCInputView.h"
#import "SCLabel.h"
#import "SCForegrounds.h"

static CGFloat RADIUS;
static CGFloat APOTHEM;
static CGFloat PADDING;

static const CGFloat menuAnimationSpringDamping = 0.75;
static const NSTimeInterval menuAnimationDuration = 0.5;
static NSDictionary *foregroundDisplayInfo;

@interface SCViewController () <UIScrollViewDelegate>

@property (strong, nonatomic) IBOutlet SCScrollView *scrollView;
@property (strong, nonatomic) UIView *tilesView;
@property (nonatomic, strong) SCCity *city;
@property (nonatomic, strong) NSMutableDictionary *tileViewForTile;

@property (strong, nonatomic) IBOutlet UIButton *endTurnButton;
@property (strong, nonatomic) IBOutlet UIView *commandView;
@property (strong, nonatomic) IBOutlet UIToolbar *toolbar;
@property (strong, nonatomic) IBOutlet UIButton *scienceButton;
@property (strong, nonatomic) IBOutlet UIButton *cheatButton;

@property (nonatomic, strong) SCRadialMenuView *currentMenuView;

@property (strong, nonatomic) UIView *detailView;

@property (nonatomic, strong) SCTile *selectedTile;

@property (nonatomic, assign) CGSize contentSize;
@property (nonatomic, assign) CGRect unobscuredFrame;
@property (nonatomic, assign) BOOL showingModal;

@end

@implementation SCViewController

+ (void)initialize {
    APOTHEM = 22;
    RADIUS = APOTHEM / 0.5 / sqrtf(3.0f);
    PADDING = APOTHEM * 3;
    
    UIColor *buildingColor = [UIColor brownColor];
    UIColor *greenColor = [UIColor colorWithHue:0.33 saturation:0.9 brightness:0.6 alpha:1];
    UIColor *blueColor = [UIColor colorWithHue:0.66 saturation:0.9 brightness:0.6 alpha:1];
    UIColor *yellowColor = [UIColor colorWithHue:0.15 saturation:1.0 brightness:0.7 alpha:1];
    
    foregroundDisplayInfo =
    @{
      SCGrass.class.pointerValue: RACTuplePack(@"Grass", @"", greenColor, @"You can build here"),
      SCForest.class.pointerValue: RACTuplePack(@"Forest", @"♣", greenColor, @"Possibly haunted"),
      SCRiver.class.pointerValue: RACTuplePack(@"River", @"", blueColor, @"You can fish in it"),
      SCTemple.class.pointerValue: RACTuplePack(@"Temple", @"T", yellowColor, @"A myserious temple"),
      SCFarm.class.pointerValue: RACTuplePack(@"Farm", @"=", yellowColor, @"Farms don't do anything yet."),
      SCGranary.class.pointerValue: RACTuplePack(@"Granary", @"G", buildingColor, @"95% preservation of up to 200 maize"),
      SCFishery.class.pointerValue: RACTuplePack(@"Fishery", @"F", buildingColor, @"+2 fish per labor in adjacent rivers and lakes"),
      SCLumberMill.class.pointerValue: RACTuplePack(@"Lumbery", @"L", buildingColor, @"+1 wood per labor in adjacent forests"),
      SCHouse.class.pointerValue: RACTuplePack(@"House", @"H", buildingColor, @"+100 max pop, +10 more for each adjacent house"),
      };
}

- (NSString *)nameForResource:(SCResource)resource {
    switch (resource) {
        case SCResourceLabor: return @"labor";
        case SCResourcePeople: return @"people";
        case SCResourceWood: return @"wood";
        case SCResourceFish: return @"fish";
        case SCResourceMaize: return @"maize";
        case SCResourceMeat: return @"meat";
        case SCResourceStone: return @"stone";
        case SCResourceConstruction: return @"construction";
    }
}

- (SCTileView *)tileViewForTile:(SCTile *)tile {
    if (tile == nil) {
        return nil;
    }
    SCTileView *tileView = self.tileViewForTile[tile.pointerValue];
    if (tileView == nil) {
        tileView =
        self.tileViewForTile[tile.pointerValue] = [self makeTileViewForTile:tile];
    }
    return tileView;
}

- (RACSignal *)foregroundInfoForTile:(SCTile *)tile {
    return [RACObserve(tile, foreground) map:^(SCForeground *foreground) {
        return foregroundDisplayInfo[foreground.class.pointerValue];
    }];
}

- (SCTileView *)makeTileViewForTile:(SCTile *)tile {
    SCTileView *tileView = [[SCTileView alloc] initWithApothem:APOTHEM];
    
    RACSignal *foregroundInfo = [self foregroundInfoForTile:tile];
    
    RAC(tileView.label, text, @"?") = [foregroundInfo index:1];
    tileView.label.font = [UIFont fontWithName:@"Menlo" size:20];
    RAC(tileView, fillColor) = [foregroundInfo index:2];
    return tileView;
}

- (SCWorld *)world {
    return self.city.world;
}

- (void)setupGrid {
    self.tileViewForTile = [[NSMutableDictionary alloc] init];
    
    for (SCTile *tile in self.world.tiles) {
        SCTileView *tileView = [self tileViewForTile:tile];
        tileView.center = [self centerForPosition:tile.hex.position];
        [[tileView rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(SCTileView *tileView) {
            self.selectedTile = self.selectedTile == tile ? nil : tile;
        }];
        [self.tilesView addSubview:tileView];
    }
    self.scrollView.backgroundColor = UIColor.darkGrayColor;
    self.scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self.view layoutIfNeeded];
    RAC(self, contentSize) = [RACObserve(self, world.radius) map:^(NSNumber *worldRadius) {
        return [NSValue valueWithCGSize:boundingSizeForHexagons(APOTHEM, worldRadius.unsignedIntegerValue * 2 + 1)];
    }];
    RAC(self.scrollView, contentSize) = [self paddedContentSize];
    
    @weakify(self);
    [[RACSignal combineLatest:@[RACObserve(self, selectedTile), RACObserve(self, showingModal)]] subscribeNext:^(RACTuple *tuple) {
        RACTupleUnpack(SCTile *selectedTile, NSNumber *showingModal) = tuple;
        BOOL shouldShowMenu = selectedTile != nil && !showingModal.boolValue;
        [self removeCurrentMenuView];
        if (shouldShowMenu) {
            [self addMenuViewForTile:selectedTile];
        }
    }];
    
    [RACObserve(self, selectedTile) subscribeChanges:^(SCTile *previous, SCTile *current) {
        @strongify(self);
        [self tileViewForTile:previous].selected = NO;
        SCTileView *selectedTileView = [self tileViewForTile:current];
        selectedTileView.selected = YES;
        [selectedTileView.superview bringSubviewToFront:selectedTileView];
    } start:self.selectedTile];
}

- (RACSignal *)paddedContentSize {
    return [RACObserve(self, contentSize) map:^(NSValue *sizeValue) {
        CGSize size = sizeValue.CGSizeValue;
        size.width += PADDING * 2;
        size.height += PADDING * 2;
        return [NSValue valueWithCGSize:size];
    }];
}

- (void)removeCurrentMenuView {
    if (self.currentMenuView == nil) {
        return;
    }
    [self popClosed:self.currentMenuView];
    self.currentMenuView = nil;
}

- (NSArray *)buttonsForTile:(SCTile *)tile {
    SCButtonDescription *(^button)(NSString *name, NSString *text) = ^(NSString *name, NSString *text) {
        return [SCButtonDescription buttonWithText:name handler:^{
            [self flashMessage:text];
        }];
    };
    
    SCButtonDescription *(^laborInputRange)(NSString *buttonName,
                                            NSString *title,
                                            NSUInteger inputRate,
                                            NSUInteger outputRateMin,
                                            NSUInteger outputRateMax,
                                            SCResource resource
                                            ) = ^(NSString *buttonName,
                                                  NSString *title,
                                                  NSUInteger inputRate,
                                                  NSUInteger outputRateMin,
                                                  NSUInteger outputRateMax,
                                                  SCResource resource) {
        return [SCButtonDescription buttonWithText:buttonName handler:^{
            [self showCompoundModalWithInputs:[RACSequence return:RACTuplePack(@(SCResourceLabor), @(inputRate), self.city)]
                                      outputs:[RACSequence return:RACTuplePack(@(resource), @(outputRateMin), @(outputRateMax), self.city)]
                                        title:title];
        }];
    };
    
    // TODO: make a proper flashMessage for changes to your city
    
    if ([tile.foreground isKindOfClass:SCRiver.class]) {
        return @[laborInputRange(@"Fish", @"Fish for Fishes", 3, 0, 5, SCResourceFish)];
    }
    
    if ([tile.foreground isKindOfClass:SCGrass.class]) {
        return @[[SCButtonDescription buttonWithText:@"Build" handler:^{
            [self showBuildingModalForTile:tile];
        }]];
    }
    
    if ([tile.foreground isKindOfClass:SCTemple.class]) {
        return @[button(@"Pray", @"Praying..."), button(@"Kill", @"Sacrificing...")];
    }
    
    if ([tile.foreground isKindOfClass:SCForest.class]) {
        SCForest *forest = (SCForest *)tile.foreground;
        return @[laborInputRange(@"Hunt", @"Hunt for Animals", 1, 1, 2, SCResourceMeat),
                 laborInputRange(@"Gthr", @"Gather Maize", 2, 0, 2, SCResourceMaize),
                 [SCButtonDescription buttonWithText:@"Chop" handler:^{
                     [self showCompoundModalWithInputs:@[RACTuplePack(@(SCResourceLabor), @3, self.city),
                                                         RACTuplePack(@(SCResourceWood), @1, forest)].rac_sequence
                                               outputs:@[RACTuplePack(@(SCResourceWood), @1, @1, self.city)].rac_sequence
                                                 title:@"Chop Wood"];
                 }]];
    }
    
    if ([tile.foreground isKindOfClass:SCBuilding.class] && ![(SCBuilding *)tile.foreground isComplete]) {
        return @[[SCButtonDescription buttonWithText:@"Build" handler:^{
            [self showConstructionModalForBuilding:(SCBuilding *)tile.foreground];
        }], [SCButtonDescription buttonWithText:@"Raze" handler:^{
            [self flashMessage:@"you can't yet"];
        }]];
    }
    
    if ([tile.foreground isKindOfClass:SCFarm.class]) {
        SCFarm *farm = (SCFarm *)tile.foreground;
        switch (self.world.season) {
            case SCSeasonSpring:
                return @[[SCButtonDescription buttonWithText:@"Sow" handler:^{
                    [self showCompoundModalWithInputs:@[RACTuplePack(@(SCResourceLabor), @2, self.city),
                                                        RACTuplePack(@(SCResourceMaize), @1, self.city)].rac_sequence
                                              outputs:@[RACTuplePack(@(SCResourceMaize), @1, @1, farm)].rac_sequence
                                                title:@"Plant Maize"];
                }]];
            case SCSeasonSummer:
                return @[button(@"Wait", @"You can't do anything in the summer.")];
            case SCSeasonAutumn:
                return @[[SCButtonDescription buttonWithText:@"Reap" handler:^{
                    [self showCompoundModalWithInputs:@[RACTuplePack(@(SCResourceLabor), @2, self.city),
                                                        RACTuplePack(@(SCResourceMaize), @1, farm)].rac_sequence
                                              outputs:@[RACTuplePack(@(SCResourceMaize), @3, @6, self.city)].rac_sequence
                                                title:@"Harvest Maize"];
                }]];
            case SCSeasonWinter:
                return @[button(@"Wait", @"You can't do anything in the winter.")];
        }
    }
    
    return nil;
}

- (void)flashMessage:(NSString *)message {
    SCLabel *label = [[SCLabel alloc] initWithFrame:CGRectZero];
    [label size:@"k"];
    label.text = message;
    label.insets = UIEdgeInsetsMake(5, 5, 5, 5);
    [label sizeToFit];
    label.center = CGPointMake(CGRectGetMidX(self.view.bounds), 0);
    label.frameOriginY = CGRectGetMaxY(self.navigationController.navigationBar.frame) + 5;
    label.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
    label.layer.cornerRadius = label.frameHeight * 0.5;
    label.layer.masksToBounds = YES;
    
    [self popOpen:label inView:self.view completion:^(BOOL finished) {
        [self popClosed:label delay:0.25];
    }];
}

- (void)popOpen:(UIView *)view inView:(UIView *)superview {
    [self popOpen:view inView:superview completion:nil];
}

- (void)popOpen:(UIView *)view inView:(UIView *)superview completion:(void(^)(BOOL))completion {
    view.transform = CGAffineTransformMakeScale(0.1, 0.1);
    view.alpha = 0;
    [superview addSubview:view];
    
    [UIView animateWithDuration:menuAnimationDuration
                          delay:0
         usingSpringWithDamping:menuAnimationSpringDamping
          initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         view.alpha = 1;
                         view.transform = CGAffineTransformIdentity;
                     } completion:completion];
}

- (void)popClosed:(UIView *)view {
    [self popClosed:view delay:0];
}

- (void)popClosed:(UIView *)view delay:(NSTimeInterval)delay {
    [UIView animateWithDuration:menuAnimationDuration * 0.25
                          delay:delay
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         view.transform = CGAffineTransformMakeScale(1.1, 1.1);
                     } completion:^(BOOL finished) {
                         [UIView animateWithDuration:menuAnimationDuration * 0.25
                                               delay:0
                                             options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                                          animations:^{
                                              view.alpha = 0;
                                              view.transform = CGAffineTransformMakeScale(0.01, 0.01);
                                          } completion:^(BOOL finished) {
                                              [view removeFromSuperview];
                                          }];
                     }];
}

- (void)showCompoundModalWithInputs:(RACSequence *)inputRates
                            outputs:(RACSequence *)outputRates
                              title:(NSString *)title {
    RACSignal *maxStepsSignal = [[RACSignal combineLatest:[[inputRates reduceEach:^(NSNumber *resource, NSNumber *rate, NSObject<SCResourceOwner> *source) {
        return [[source quantityOfResource:resource.unsignedIntegerValue] map:^(NSNumber *quantity) {
            return @(quantity.unsignedIntegerValue / rate.unsignedIntegerValue);
        }];
    }] concat:[outputRates reduceEach:^(NSNumber *resource, NSNumber *minRate, NSNumber *maxRate, NSObject<SCResourceOwner> *source) {
        return [[source unusedCapacityForResource:resource.unsignedIntegerValue] map:^(NSNumber *unusedCapacity) {
            NSAssert([source currentCapacityForResource:resource.unsignedIntegerValue] == NSUIntegerMax ||
                     [minRate isEqualToNumber:maxRate], @"We can't ensure a capacity invariant with randomized output (right now)");
            return @(unusedCapacity.unsignedIntegerValue / maxRate.unsignedIntegerValue);
        }];
    }]]] min];
    
    RACTupleUnpack(SCInputView *inputView, RACSignal *inputStepsSignal) = [self inputViewWithMaxValue:maxStepsSignal commit:^(NSUInteger inputSteps) {
        for (RACTuple *tuple in inputRates) {
            RACTupleUnpack(NSNumber *resource, NSNumber *rate, NSObject<SCResourceOwner> *source) = tuple;
            [source loseQuantity:(inputSteps * rate.unsignedIntegerValue) ofResource:resource.unsignedIntegerValue];
        }
        for (RACTuple *tuple in outputRates) {
            RACTupleUnpack(NSNumber *resource, NSNumber *minRate, NSNumber *maxRate, NSObject<SCResourceOwner> *source) = tuple;
            NSUInteger outputSpread = maxRate.unsignedIntegerValue - minRate.unsignedIntegerValue;
            NSUInteger output = 0;
            if (outputSpread == 0) {
                output = (inputSteps * minRate.unsignedIntegerValue);
            } else {
                for (NSUInteger i = 0; i < inputSteps; i++) {
                    output += arc4random_uniform((u_int32_t)outputSpread + 1) + minRate.unsignedIntegerValue;
                }
            }
            [source gainQuantity:output ofResource:resource.unsignedIntegerValue];
        }
    }];
    
    NSString *(^resourceRangeString)(RACSequence *tuples) = ^(RACSequence *tuples) {
        return [[[tuples reduceEach:^(NSNumber *resource, NSNumber *min, NSNumber *max) {
            NSString *resourceName = [self nameForResource:resource.unsignedIntegerValue];
            if ([min isEqualToNumber:max]) {
                return [NSString stringWithFormat:@"%@ %@", min, resourceName];
            } else {
                return [NSString stringWithFormat:@"%@-%@ %@", min, max, resourceName];
            }
        }] array] componentsJoinedByString:@", "];
    };
    
    NSString *(^resourceString)(RACSequence *tuples) = ^(RACSequence *tuples) {
        return resourceRangeString([tuples reduceEach:^(NSNumber *resource, NSNumber *x) {
            return RACTuplePack(resource, x, x);
        }]);
    };
    
    inputView.topLabel.text = [NSString stringWithFormat:@"%@ ➜ %@", resourceString(inputRates), resourceRangeString(outputRates)];
    inputView.titleLabel.text = title;
    
    RAC(inputView.bottomLabel, text) = [inputStepsSignal map:^(NSNumber *inputStepsNumber) {
        NSUInteger steps = inputStepsNumber.unsignedIntegerValue;
        if (steps == 0) {
            return @"How much labor?";
        } else {
            return [NSString stringWithFormat:@"%@ ➜ %@", resourceString([inputRates reduceEach:^(NSNumber *resource, NSNumber *rate) {
                return RACTuplePack(resource, @(steps * rate.unsignedIntegerValue));
            }]), resourceRangeString([outputRates reduceEach:^(NSNumber *resource, NSNumber *minRate, NSNumber *maxRate) {
                return RACTuplePack(resource, @(steps * minRate.unsignedIntegerValue), @(steps * maxRate.unsignedIntegerValue));
            }])];
        }
    }];
}

- (void)showConstructionModalForBuilding:(SCBuilding *)building {
    [self showCompoundModalWithInputs:[building.inputRates reduceEach:^(NSNumber *resource, NSNumber *rate) {
        return RACTuplePack(resource, rate, self.city);
    }]
                              outputs:@[RACTuplePack(@(SCResourceConstruction), @1, @1, building)].rac_sequence
                                title:[NSString stringWithFormat:@"Construct a %@", foregroundDisplayInfo[building.class.pointerValue][0]]];
}

- (void)showBuildingModalForTile:(SCTile *)tile {
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 0)];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 300, 30)];
    titleLabel.text = @"Build a Building";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    SCScrollView *scrollView = [[SCScrollView alloc] initWithFrame:CGRectMake(0, 0, 300, 200)];
    scrollView.delaysContentTouches = NO;
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelButton.frame = CGRectMake(0, 0, 300, 44);
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    
    [view stackViewsVerticallyCentered:@[titleLabel, scrollView, cancelButton]];
    
    void (^dismiss)() = [self showModal:view];
    [[cancelButton rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        dismiss();
    }];
    
    NSArray *buildings =
    @[
      RACTuplePack(SCHouse.class, @20, @20, @0, nil),
      RACTuplePack(SCFarm.class, @10, @0, @0, @{@"capacity": @20}),
      RACTuplePack(SCGranary.class, @30, @30, @0, nil),
      RACTuplePack(SCTemple.class, @60, @0, @30, nil),
      RACTuplePack(SCLumberMill.class, @20, @10, @0, nil),
      RACTuplePack(SCFishery.class, @50, @30, @0, nil),
      ];
    CGFloat padding = 10;
    CGFloat top = 0;
    for (RACTuple *tuple in buildings) {
        RACTupleUnpack(Class class, NSNumber *labor, NSNumber *wood, NSNumber *stone, NSDictionary *args) = tuple;
        UIControl *control = [[UIControl alloc] initWithFrame:CGRectMake(0, top, 300, 30)];
        RAC(control, backgroundColor) = [RACObserve(control, highlighted) map:^(NSNumber *highlighted) {
            return highlighted.boolValue ? [UIColor colorWithWhite:0 alpha:0.1] : UIColor.clearColor;
        }];
        
        RACTupleUnpack(NSString *name, NSString *tileIcon, UIColor *tileColor, NSString *description) = foregroundDisplayInfo[class.pointerValue];
        
        SCTileView *tileView = [[SCTileView alloc] initWithApothem:APOTHEM];
        tileView.frameOriginX = padding;
        tileView.fillColor = tileColor;
        tileView.label.text = tileIcon;
        tileView.label.font = [UIFont fontWithName:@"Menlo" size:13];
        tileView.userInteractionEnabled = NO;
        [tileView size:@"hk"];
        [control addSubview:tileView];
        
        UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, CGRectGetMaxY(tileView.frame), CGRectGetWidth(tileView.frame), 22)];
        nameLabel.text = name;
        nameLabel.font = [UIFont fontWithName:@"Menlo" size:11];
        nameLabel.textAlignment = NSTextAlignmentCenter;
        [nameLabel size:@"hk"];
        [control addSubview:nameLabel];
        
        CGFloat left = CGRectGetMaxX(tileView.frame);
        UILabel *descriptionLabel = [[UILabel alloc] initWithFrame:CGRectMake(left, 0, control.bounds.size.width - left - padding, control.bounds.size.height)];
        descriptionLabel.numberOfLines = 0;
        descriptionLabel.text = [NSString stringWithFormat:@"%@ (%@w %@s %@l)", description, wood, stone, labor];
        [descriptionLabel size:@"hjkl"];
        [control addSubview:descriptionLabel];
        
        [[control rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
            dismiss();
            RACSequence *requiredResources = [@[RACTuplePack(@(SCResourceLabor), labor),
                                                RACTuplePack(@(SCResourceWood), wood),
                                                RACTuplePack(@(SCResourceStone), stone)].rac_sequence filter:^BOOL(RACTuple *tuple) {
                                                    return [tuple[1] unsignedIntegerValue] > 0;
                                                }];
            SCBuilding *building = (SCBuilding *)[[class alloc] initWithRequiredResources:requiredResources args:args];
            tile.foreground = building;
            [self showConstructionModalForBuilding:building];
        }];
        control.frameHeight = CGRectGetMaxY(nameLabel.frame);
        top = CGRectGetMaxY(control.frame);
        [scrollView addSubview:control];
    }
    scrollView.contentSize = CGSizeMake(300, top);
}

- (void(^)())showModal:(UIView *)view {
    __block BOOL dismissed = NO;
    return [self showModal:view dismissed:&dismissed];
}

- (void(^)())showModal:(UIView *)view dismissed:(BOOL *)dismissed {
    view.backgroundColor = [UIColor colorWithWhite:1 alpha:0.9];
    view.layer.cornerRadius = 10;
    [view size:@""];
    CGFloat top = CGRectGetMaxY([self.view convertRect:self.navigationController.navigationBar.frame fromView:self.navigationController.navigationBar.superview]);
    UIView *backdropView = [[UIView alloc] initWithFrame:CGRectMake(0, top, self.view.bounds.size.width, CGRectGetMinY(self.toolbar.frame) - top)];
    [backdropView size:@"hjkl"];
    backdropView.userInteractionEnabled = YES;
    backdropView.backgroundColor = UIColor.blackColor;
    backdropView.alpha = 0;
    
    NSAssert(*dismissed == NO, @"Must pass a pointer to NO");
    void (^dismiss)() = ^{
        *dismissed = YES;
        self.showingModal = NO;
        [self popClosed:view];
        backdropView.userInteractionEnabled = NO;
        [UIView animateWithDuration:0.25 animations:^{
            backdropView.alpha = 0;
        } completion:^(BOOL finished) {
            [backdropView removeFromSuperview];
        }];
    };
    
    UITapGestureRecognizer *backgroundTapRecognizer = [[UITapGestureRecognizer alloc] init];
    [backdropView addGestureRecognizer:backgroundTapRecognizer];
    [backgroundTapRecognizer.rac_gestureSignal subscribeNext:^(UITapGestureRecognizer *recognizer) {
        if (recognizer.state == UIGestureRecognizerStateRecognized) {
            dismiss();
        }
    }];
    
    RAC(view, center) = [[RACObserve(self, unobscuredFrame) map:^(NSValue *frame) {
        return [NSValue valueWithCGPoint:CGRectGetCenter(frame.CGRectValue)];
    }] takeUntilBlock:^BOOL(id x) {
        return *dismissed;
    }];
    
    [self.view insertSubview:backdropView belowSubview:self.toolbar];
    [UIView animateWithDuration:0.25 animations:^{
        backdropView.alpha = 0.5;
    }];
    [self popOpen:view inView:self.view];
    self.showingModal = YES;
    
    return dismiss;
}

- (RACTuple *)inputViewWithMaxValue:(RACSignal *)maxValueSignal
                             commit:(void(^)(NSUInteger steps))commitBlock {
    SCInputView *inputView = [[UINib nibWithNibName:@"SCInputView" bundle:nil] instantiateWithOwner:nil options:nil][0];
    __block BOOL dismissed = NO;
    
    inputView.slider.minimumValue = 0;
    inputView.slider.value = 0;
    [[maxValueSignal takeUntilBlock:^BOOL(id x) {
        return dismissed;
    }] subscribeNext:^(NSNumber *maxSteps) {
        inputView.slider.maximumValue = maxSteps.unsignedIntegerValue;
        [inputView.slider sendActionsForControlEvents:UIControlEventValueChanged];
    }];
    
    RACSignal *inputSignal = [[[RACSignal defer:^{
        return [RACSignal return:@(inputView.slider.value)];
    }] concat:[[inputView.slider rac_signalForControlEvents:UIControlEventValueChanged] map:^(UISlider *slider) {
        return @(slider.value);
    }]] map:^(NSNumber *sliderValue) {
        return @((NSUInteger)roundf(sliderValue.floatValue));
    }];
    
    [inputView.button setTitle:@"Commit" forState:UIControlStateNormal];
    [inputView layoutIfNeeded];
    inputView.frameHeight = CGRectGetMaxY(inputView.button.frame);
    RAC(inputView.button, enabled) = [[inputSignal is:@0] not];
    
    void (^dismissModal)() = [self showModal:inputView dismissed:&dismissed];
    
    [[inputView.button rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        dismissed = YES;
        NSUInteger input = [[inputSignal first] unsignedIntegerValue];
        assert(input > 0);
        commitBlock(input);
        dismissModal();
    }];
    
    [[inputView.cancelButton rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        dismissModal();
    }];
    
    return RACTuplePack(inputView, inputSignal);
}

- (void)addMenuViewForTile:(SCTile *)tile {
    if (tile == nil) {
        return;
    }
    self.currentMenuView = [[SCRadialMenuView alloc] initWithApothem:APOTHEM buttons:[self buttonsForTile:tile]];
    self.currentMenuView.center = [self centerForPosition:tile.hex.position];
    
    [self popOpen:self.currentMenuView inView:self.tilesView];
}

- (NSArray *)iterate {
    [self.world iterate];
    return [self.city iterate];
}

- (UIView *)tileDetailViewForTile:(SCTile *)tile {
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 500, APOTHEM * 3)];
    
    SCTileView *tileView = [self makeTileViewForTile:tile];
    [view addSubview:tileView];
    tileView.center = CGPointMake(RADIUS, APOTHEM);
    [tileView size:@"hk"];
    @weakify(self);
    [[tileView rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        @strongify(self);
        [self scrollToTile:tile];
    }];
    
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, APOTHEM * 2, RADIUS * 2, APOTHEM)];
    [nameLabel size:@"hj"];
    RAC(nameLabel, text) = [[self foregroundInfoForTile:tile] index:0];
    nameLabel.font = [UIFont fontWithName:@"Menlo" size:11];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    [view addSubview:nameLabel];
    
    UILabel *detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(RADIUS * 2, 0, view.bounds.size.width - RADIUS * 2, view.bounds.size.height)];
    detailLabel.font = [UIFont fontWithName:@"Menlo" size:13];
    detailLabel.numberOfLines = 0;
    [detailLabel size:@"hjkl"];
    
    RACSignal *descriptionSignal = [[self foregroundInfoForTile:tile] index:3];
    RACSignal *prefixSignal = [[RACObserve(tile, foreground) map:^(SCForeground *foreground) {
        if ([foreground isKindOfClass:SCForest.class]) {
            SCForest *forest = (SCForest *)foreground;
            return [[forest quantityOfResource:SCResourceWood] map:^(NSNumber *wood) {
                return [NSString stringWithFormat:@"%@ trees", wood];
            }];
        } else if ([foreground isKindOfClass:SCBuilding.class]) {
            SCBuilding *building = (SCBuilding *)foreground;
            return [RACSignal combineLatest:@[[building quantityOfResource:SCResourceConstruction],
                                              [building capacityForResource:SCResourceConstruction],
                                              ] reduce:^(NSNumber *taken, NSNumber *total) {
                                                  return [taken isEqual:total] ? @"" : [NSString stringWithFormat:@"(%@ / %@)", taken, total];
                                              }];
        } else {
            return [RACSignal return:nil];
        }
    }] switchToLatest];
    
    RAC(detailLabel, text) = [RACSignal combineLatest:@[prefixSignal, descriptionSignal] reduce:^(NSString *prefix, NSString *description){
        return prefix == nil ? description : [NSString stringWithFormat:@"%@\n%@", prefix, description];
    }];
    [view addSubview:detailLabel];
    
    return view;
}

- (void)setUnobscuredFrame:(CGRect)unobscuredFrame withAnimationFromUserInfo:(NSDictionary *)userInfo {
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationCurve:[userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue]];
    [UIView setAnimationDuration:[userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    self.unobscuredFrame = unobscuredFrame;
    [UIView commitAnimations];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.unobscuredFrame = self.view.bounds;
}

- (void)viewDidLoad {
    @weakify(self);
    [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillShowNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        @strongify(self);
        CGRect keyboardFrame = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
        CGRect obscured = CGRectIntersection(self.view.bounds, keyboardFrame);
        CGRect bounds = self.view.bounds;
        bounds.size.height -= obscured.size.height;
        [self setUnobscuredFrame:bounds withAnimationFromUserInfo:note.userInfo];
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillHideNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        @strongify(self);
        [self setUnobscuredFrame:self.view.bounds withAnimationFromUserInfo:note.userInfo];
    }];
    
    self.tilesView = [[SCPassthroughView alloc] initWithFrame:self.scrollView.contentView.bounds];
    [self.scrollView.contentView addSubview:self.tilesView];
    
    RAC(self.tilesView, bounds) = [self.paddedContentSize map:^(NSValue *contentSizeValue) {
        CGSize contentSize = contentSizeValue.CGSizeValue;
        CGRect bounds = CGRectMake(contentSize.width * -0.5, contentSize.height * -0.5, contentSize.width, contentSize.height);
        return [NSValue valueWithCGRect:bounds];
    }];
    RAC(self.tilesView, frame) = [self.paddedContentSize map:^(NSValue *contentSizeValue) {
        return [NSValue valueWithCGRect:CGRectMakeSize(0, 0, contentSizeValue.CGSizeValue)];
    }];
    
    self.city = [SCCity cityWithWorld:[SCWorld worldWithRadius:6]];
    [self setupGrid];
    [self.view layoutIfNeeded];
    
    UILabel *infoLabel = [[UILabel alloc] init];
    infoLabel.font = [UIFont fontWithName:@"Menlo" size:13];
    infoLabel.numberOfLines = 0;
    infoLabel.textAlignment = NSTextAlignmentCenter;
    self.navigationItem.titleView = infoLabel;
    infoLabel.frame = self.navigationController.navigationBar.bounds;
    
    RAC(self, detailView) = [RACObserve(self, selectedTile) map:^(SCTile *tile) {
        @strongify(self);
        return tile == nil ? self.commandView : [self tileDetailViewForTile:tile];
    }];
    
    [RACObserve(self, detailView) subscribeChanges:^(UIView *previous, UIView *current) {
        [previous removeFromSuperview];
        current.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        current.frameWidth = self.toolbar.frameWidth;
        current.frame = self.toolbar.bounds;
        [self.toolbar addSubview:current];
    } start:nil];
    
    RAC(self, title) = [RACObserve(self.world, turn) map:^(NSNumber *turn) {
        return [NSString stringWithFormat:@"turn %@", turn];
    }];
    
    static NSDictionary *seasonNameMap = nil;
    if (seasonNameMap == nil) {
        seasonNameMap = @{@(SCSeasonSpring): @"Spring",
                          @(SCSeasonSummer): @"Summer",
                          @(SCSeasonAutumn): @"Autumn",
                          @(SCSeasonWinter): @"Winter"};
    }
    
    RAC(infoLabel, text) =
    [RACSignal combineLatest:@[RACObserve(self.world, turn),
                               [self.city quantityOfResource:SCResourcePeople],
                               [self.city quantityOfFood],
                               [self.city quantityOfResource:SCResourceLabor],
                               [self.city quantityOfResource:SCResourceWood],
                               [self.city quantityOfResource:SCResourceStone],
                               ]
                      reduce:^(NSNumber *turn, NSNumber *population, NSNumber *food, NSNumber *labor, NSNumber *wood, NSNumber *stone) {
                          NSUInteger year = turn.unsignedIntegerValue / 4;
                          NSString *season = seasonNameMap[@(self.world.season)];
                          return [NSString stringWithFormat:@"%@ - Year %@\n%@l %@p %@f %@w %@s", season, @(year), labor, population, food, wood, stone];
                      }];
    
    [[self.endTurnButton rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        NSUInteger year = self.world.turn / 4;
        NSString *season = seasonNameMap[@(self.world.season)];
        NSString *title = [NSString stringWithFormat:@"Summary for %@ - Year %@", season, @(year)];
        NSArray *messages = [self iterate];
        [self showWallOfTextModalWithTitle:title body:[messages componentsJoinedByString:@"\n"]];
    }];
    
    [[self.scienceButton rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        [self flashMessage:@"there's no science...yet"];
    }];
    
    [[self.cheatButton rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        [self flashMessage:@"+100 people"];
        [self.city gainQuantity:100 ofResource:SCResourcePeople];
        [self.city gainQuantity:100 ofResource:SCResourceLabor];
    }];
    
    [[[self rac_signalForSelector:@selector(viewWillAppear:)] take:1] subscribeNext:^(id x) {
        [self scrollToTile:[self.world tileAt:[SCPosition origin]]];
    }];
}

- (void)showWallOfTextModalWithTitle:(NSString *)title body:(NSString *)body {
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 0)];
    view.backgroundColor = UIColor.whiteColor;
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 300, 44)];
    titleLabel.font = [UIFont fontWithName:@"Menlo" size:13];
    titleLabel.text = title;
    titleLabel.textAlignment = NSTextAlignmentCenter;
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 300, 0)];
    textView.backgroundColor = UIColor.clearColor;
    textView.font = [UIFont fontWithName:@"Menlo" size:13];
    textView.editable = NO;
    textView.selectable = NO;
    textView.text = body;
    textView.frameHeight = MIN([textView sizeThatFits:CGSizeMake(300, CGFLOAT_MAX)].height, 200);
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"Done" forState:UIControlStateNormal];
    closeButton.frame = CGRectMake(0, 0, 300, 44);
    [view stackViewsVerticallyCentered:@[titleLabel, textView, closeButton]];
    void (^dismiss)() = [self showModal:view];
    [[closeButton rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(id x) {
        dismiss();
    }];
}

- (void)scrollToTile:(SCTile *)tile {
    UIView *tileView = [self tileViewForTile:tile];
    CGRect rect = [self.scrollView.contentView convertRect:tileView.frame fromView:tileView.superview];
    [self.scrollView zoomToRect:rect animated:YES];
}

- (CGPoint)centerForPosition:(SCPosition *)position {
    return hexCenter(position.x, position.y, APOTHEM);
}

- (void)centerCanvas {
    UIScrollView *scrollView = self.scrollView;
    UIEdgeInsets contentInsets = self.scrollView.contentInset;
    CGFloat logicalWidth = scrollView.bounds.size.width - contentInsets.left - contentInsets.right;
    CGFloat logicalHeight = scrollView.bounds.size.height - contentInsets.top - contentInsets.bottom;
    
    CGFloat offsetX = MAX(0, (logicalWidth - scrollView.contentSize.width) * 0.5);
    CGFloat offsetY = MAX(0, (logicalHeight - scrollView.contentSize.height) * 0.5);
    
    self.scrollView.contentView.center = CGPointMake(scrollView.contentSize.width * 0.5 + offsetX,
                                                     scrollView.contentSize.height * 0.5 + offsetY);
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self centerCanvas];
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale {
    CGFloat velocity = scrollView.pinchGestureRecognizer.velocity;
    if (ABS(velocity) < 1) {
        return;
    }
    [UIView animateWithDuration:0.25 animations:^{
        scrollView.zoomScale = scrollView.zoomScale + velocity * 0.25;
    }];
}

- (UIView *)viewForZoomingInScrollView:(SCScrollView *)scrollView {
    return scrollView.contentView;
}

@end
