#import "MGLMapViewIntegrationTest.h"
#import "MGLMockApplication.h"

@interface MGLMapView (BackgroundTests)
@property (nonatomic) id<MGLApplication> application;
@property (nonatomic, getter=isDormant) BOOL dormant;
@property (nonatomic) CADisplayLink *displayLink;
- (void)updateFromDisplayLink:(CADisplayLink *)displayLink;
@end

@protocol MGLApplication;

typedef void (^MGLNotificationBlock)(NSNotification*);

#pragma mark - MGLBackgroundIntegrationTestMapView

@interface MGLBackgroundIntegrationTestMapView : MGLMapView
@property (nonatomic, copy) dispatch_block_t displayLinkDidUpdate;
@end

@implementation MGLBackgroundIntegrationTestMapView
- (void)updateFromDisplayLink:(CADisplayLink *)displayLink {
    [super updateFromDisplayLink:displayLink];
    
    if (self.displayLinkDidUpdate) {
        self.displayLinkDidUpdate();
    }
}
@end

#pragma mark - MGLBackgroundIntegrationTest

@interface MGLBackgroundIntegrationTest : MGLMapViewIntegrationTest
@property (nonatomic) id<MGLApplication> oldApplication;
@property (nonatomic) MGLMockApplication *mockApplication;
@property (nonatomic, copy) MGLNotificationBlock willEnterForeground;
@property (nonatomic, copy) MGLNotificationBlock didEnterBackground;
@property (nonatomic, copy) dispatch_block_t displayLinkDidUpdate;
@end

@implementation MGLBackgroundIntegrationTest

- (void)setUp {

    self.mockApplication = [[MGLMockApplication alloc] init];

    // Register notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:self.mockApplication];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:self.mockApplication];
    
    [super setUp];
    
    // Setup MGLMapView to use our new mocked application
    // Change notification handling here.
    self.oldApplication = self.mapView.application;
    self.mockApplication.delegate = self.oldApplication.delegate;
    self.mapView.application = self.mockApplication;
}

- (void)tearDown {

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Swap back
    self.mapView.application = self.oldApplication;
    self.oldApplication = nil;
    self.mockApplication.delegate = nil;
    self.mockApplication = nil;
    
    [super tearDown];
}

#pragma mark - Notifications

- (void)willEnterForeground:(NSNotification*)notification {
    NSLog(@"Test willEnterForeground");
    if (self.willEnterForeground) {
        self.willEnterForeground(notification);
    }
}

- (void)didEnterBackground:(NSNotification*)notification {
    NSLog(@"Test didEnterBackground");
    if (self.didEnterBackground) {
        self.didEnterBackground(notification);
    }
}

- (MGLMapView*)testMapViewWithFrame:(CGRect)frame styleURL:(NSURL *)styleURL {
    MGLBackgroundIntegrationTestMapView *mapView = [[MGLBackgroundIntegrationTestMapView alloc] initWithFrame:frame styleURL:styleURL];
    
    mapView.displayLinkDidUpdate = ^{
        if (self.displayLinkDidUpdate) {
            self.displayLinkDidUpdate();
        }
    };
    
    return mapView;
}

#pragma mark - Tests

- (void)testRendererWhenGoingIntoBackground {
    
    XCTAssertFalse(self.mapView.isDormant);
    XCTAssertFalse(self.mapView.displayLink.isPaused);
    XCTAssert(self.mapView.application.applicationState == UIApplicationStateActive);

    __weak typeof(self) weakSelf = self;

    //
    // Enter background
    //
    
    XCTestExpectation *didEnterBackgroundExpectation = [self expectationWithDescription:@"didEnterBackground"];
    didEnterBackgroundExpectation.expectedFulfillmentCount = 1;
    didEnterBackgroundExpectation.assertForOverFulfill = YES;

    self.didEnterBackground = ^(__unused NSNotification *notification){
        typeof(self) strongSelf = weakSelf;
        MGLMapView *mapView = strongSelf.mapView;
        
        // In general, because order of notifications is not guaranteed
        // the following asserts are somewhat meaningless (don't do this in
        // production) - however, because we're mocking their delivery (and
        // we're tracking a bug)...

        // MGLMapView responds to UIApplicationDidEnterBackgroundNotification and
        // marks the map view as dormant. However, depending on the order of
        // creation it's totally possible for client code also responding to
        // this notification to be called first - and then trigger a scenario where
        // GL can be rendering in the background - which can cause crashes.
        
        MGLTestAssert(strongSelf, !mapView.isDormant);
        
        // However, the display should be paused (because this has now moved
        // to ...WillResignActive...
        MGLTestAssert(strongSelf, mapView.displayLink.isPaused);
        
        [didEnterBackgroundExpectation fulfill];
    };
    
    [self.mockApplication enterBackground];
    [self waitForExpectations:@[didEnterBackgroundExpectation] timeout:1.0];
    
    XCTAssert(self.mapView.isDormant);
    
    // TODO: What do we want here?
    XCTAssert(!self.mapView.displayLink || self.mapView.displayLink.isPaused);
    XCTAssert(self.mapView.application.applicationState == UIApplicationStateBackground);

    //
    // Enter foreground
    //

    XCTestExpectation *willEnterForegroundExpectation = [self expectationWithDescription:@"willEnterForeground"];
    willEnterForegroundExpectation.expectedFulfillmentCount = 1;
    willEnterForegroundExpectation.assertForOverFulfill = YES;

    self.willEnterForeground = ^(NSNotification *notification) {
        [willEnterForegroundExpectation fulfill];
    };
    
    [self.mockApplication enterForeground];
    [self waitForExpectations:@[willEnterForegroundExpectation] timeout:1.0];
    
    XCTAssertFalse(self.mapView.isDormant);
    XCTAssert(self.mapView.displayLink && !self.mapView.displayLink.isPaused);
    XCTAssert(self.mapView.application.applicationState == UIApplicationStateActive);
}

- (void)testRendererAdjustingViewsWhenGoingIntoBackground {
    
    XCTAssertFalse(self.mapView.isDormant);
    XCTAssertFalse(self.mapView.displayLink.isPaused);
    XCTAssert(self.mapView.application.applicationState == UIApplicationStateActive);
    
    __weak typeof(self) weakSelf = self;
    
    //
    // Enter background
    //
    
    XCTestExpectation *didEnterBackgroundExpectation = [self expectationWithDescription:@"didEnterBackground"];
    didEnterBackgroundExpectation.expectedFulfillmentCount = 1;
    didEnterBackgroundExpectation.assertForOverFulfill = YES;
    
    __block NSInteger displayLinkCount = 0;
    
    self.displayLinkDidUpdate = ^{
        displayLinkCount++;
    };
    
    self.didEnterBackground = ^(__unused NSNotification *notification){
        typeof(self) strongSelf = weakSelf;
        MGLMapView *mapView = strongSelf.mapView;
        
        // In general, because order of notifications is not guaranteed
        // the following asserts are somewhat meaningless (don't do this in
        // production) - however, because we're mocking their delivery (and
        // we're tracking a bug)...
        
        // MGLMapView responds to UIApplicationDidEnterBackgroundNotification and
        // marks the map view as dormant. However, depending on the order of
        // creation it's totally possible for client code also responding to
        // this notification to be called first - and then trigger a scenario where
        // GL can be rendering in the background - which can cause crashes.
        
        MGLTestAssert(strongSelf, !mapView.isDormant);
        
        // However, the display should be paused (because this has now moved
        // to ...WillResignActive...
        MGLTestAssert(strongSelf, mapView.displayLink.isPaused);
        
        displayLinkCount = 0;
        
        // Remove the map view, and re-add to try and force a bad situation
        // This will delete/re-create the display link
        UIView *parentView = mapView.superview;
        
        NSLog(@"Removing MGLMapView from super view");
        [mapView removeFromSuperview];
        
        // Re-add
        NSLog(@"Re-adding MGLMapView as child");
        [parentView addSubview:mapView];
        
        MGLTestAssert(strongSelf, displayLinkCount == 0, @"updateDisplayLink was called %ld times", displayLinkCount);
        
        [mapView.topAnchor constraintEqualToAnchor:parentView.topAnchor].active = YES;
        [mapView.leftAnchor constraintEqualToAnchor:parentView.leftAnchor].active = YES;
        [mapView.rightAnchor constraintEqualToAnchor:parentView.rightAnchor].active = YES;
        [mapView.bottomAnchor constraintEqualToAnchor:parentView.bottomAnchor].active = YES;
        
        [didEnterBackgroundExpectation fulfill];
    };
    
    [self.mockApplication enterBackground];
    [self waitForExpectations:@[didEnterBackgroundExpectation] timeout:1.0];
    
    XCTAssert(self.mapView.isDormant);
    
    // TODO: What do we want here?
    XCTAssert(!self.mapView.displayLink || self.mapView.displayLink.isPaused);
    XCTAssert(self.mapView.application.applicationState == UIApplicationStateBackground);
    
    //
    // Enter foreground
    //
    
    XCTestExpectation *willEnterForegroundExpectation = [self expectationWithDescription:@"willEnterForeground"];
    willEnterForegroundExpectation.expectedFulfillmentCount = 1;
    willEnterForegroundExpectation.assertForOverFulfill = YES;
    
    self.willEnterForeground = ^(NSNotification *notification) {
        displayLinkCount = 0;
        [willEnterForegroundExpectation fulfill];
    };
    
    [self.mockApplication enterForeground];
    XCTAssert(displayLinkCount == 0, @"updateDisplayLink was called %ld times", displayLinkCount);
    [self waitForExpectations:@[willEnterForegroundExpectation] timeout:1.0];
    
    XCTAssertFalse(self.mapView.isDormant);
    XCTAssert(self.mapView.displayLink && !self.mapView.displayLink.isPaused);
    XCTAssert(self.mapView.application.applicationState == UIApplicationStateActive);
}

@end
