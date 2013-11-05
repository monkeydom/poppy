//
//  LiveViewController.m
//  PoppyApp
//
//  Created by Ethan Lowry on 10/1/13.
//  Copyright (c) 2013 Ethan Lowry. All rights reserved.
//

// TAGGED VIEWS:
// 100 = the view containing the toggle switch
// 101 = the toggle label
// 102 = the "recording" light
// 103 = the movie player view
// 104 = the view containing the camera button

#import "LiveViewController.h"
#import "RBVolumeButtons.h"

@interface LiveViewController ()

@end

@implementation LiveViewController

int next = 1;
int prev = -1;

float scaleFactorX = 0.6;
float scaleFactorY = 0.7;

bool didFinishEffect = NO;
bool isRecording = NO;
bool isVideo = YES;
bool isWatching = NO;

NSTimer *timerDimmer;
ALAssetsGroup *assetsGroup;
ALAssetsLibrary *assetLibrary;

int currentIndex = -1;


- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Create a Poppy album if it doesn't already exist
    assetLibrary = [[ALAssetsLibrary alloc] init];
    [assetLibrary addAssetsGroupAlbumWithName:@"Poppy"
                                  resultBlock:^(ALAssetsGroup *group) {
                                      if (group) {
                                          NSLog(@"added album:%@", [group valueForProperty:ALAssetsGroupPropertyName]);
                                      } else {
                                          NSLog(@"no group created, probably because it already exists");
                                      }
                                      [self loadAlbumWithName:@"Poppy"];
                                  }
                                 failureBlock:^(NSError *error) {
                                     NSLog(@"error adding album");
                                 }];
    
    buttonStealer = [[RBVolumeButtons alloc] init];
    buttonStealer.upBlock = ^{
        // + volume button pressed
        NSLog(@"VOLUME UP!");
        currentIndex = -1;
        if (isWatching) {
            [self hideViewer];
            [self showToggleButton];
        } else {
            if (isVideo) {
                if (isRecording) {
                    isRecording = NO;
                    [self stopRecording];
                } else {
                    isRecording = YES;
                    [self startRecording];
                }
            } else {
                [self captureStill];
            }
        }
    };
    buttonStealer.downBlock = ^{
        // - volume button pressed
        NSLog(@"VOLUME DOWN!");
        [self showMedia:prev];
    };
    
    // NOTE: immediately steals volume button events. maybe we want to only do this in landscape mode
    [buttonStealer startStealingVolumeButtonEvents];
}

- (void)hideViewer
{
    // clear away the view mode UI
    isWatching = NO;
    [imgView setHidden:YES];
    [mainMoviePlayer stop];
    [[self.view viewWithTag:103] removeFromSuperview]; //remove the movie player
    [[self.view viewWithTag:104] removeFromSuperview]; //remove the camera button
}

- (void)viewDidAppear:(BOOL)animated
{
    imgView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.height, self.view.frame.size.width)];
    [imgView setContentMode: UIViewContentModeScaleAspectFill];
    [self.view addSubview:imgView];
    
    uberView = (GPUImageView *)self.view;
    
    // set up gestures
    UIView *touchView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.height, self.view.frame.size.width)];
    [self addGestures:touchView];
    [self.view addSubview:touchView];
    
    [self activateCamera];
    [self showToggleButton];

}

- (void)addGestures:(UIView *)touchView
{
    UITapGestureRecognizer *handleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapAction:)];
    [touchView addGestureRecognizer:handleTap];
    
    UISwipeGestureRecognizer *swipeLeftGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeScreenleft:)];
    swipeLeftGesture.numberOfTouchesRequired = 1;
    swipeLeftGesture.direction = (UISwipeGestureRecognizerDirectionLeft);
    [touchView addGestureRecognizer:swipeLeftGesture];
    
    UISwipeGestureRecognizer *swipeRightGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeScreenRight:)];
    swipeRightGesture.numberOfTouchesRequired = 1;
    swipeRightGesture.direction = (UISwipeGestureRecognizerDirectionRight);
    [touchView addGestureRecognizer:swipeRightGesture];
}


- (void)showMedia:(int)direction
{
    // show image or play video
    int assetCount = [assetsGroup numberOfAssets];
    NSLog(@"album count %d", assetCount);
    if (assetCount > 0) {
        if (!isWatching) {
            [self showCameraButton];
            [self dimView:0.0 withAlpha:0.1 withView:[self.view viewWithTag:104] withTimer:NO];
        }
        isWatching = YES; // we're in view mode, not capture mode
        //[self hideToggleButton];
        [self hideView:[self.view viewWithTag:100]];
        
        [mainMoviePlayer stop];
        [[self.view viewWithTag:103] removeFromSuperview];
        
        NSLog(@"Current index before = %d", currentIndex);
        
        if (direction == prev) {
            if (currentIndex > 0) {
                currentIndex = currentIndex - 1;
            } else {
                currentIndex = assetCount - 1;
            }
        } else {
            if (currentIndex < assetCount - 1) {
                currentIndex = currentIndex + 1;
            } else {
                currentIndex = 0;
            }
        }
        NSLog(@"Current index after = %d", currentIndex);
        
        [assetsGroup enumerateAssetsAtIndexes:[NSIndexSet indexSetWithIndex:currentIndex] options:0 usingBlock: ^(ALAsset *asset, NSUInteger index, BOOL *stop)
             {
                 if (asset) {
                     NSLog(@"got the asset: %d", index);
                     ALAssetRepresentation *assetRepresentation = [asset defaultRepresentation];
                     UIImage *fullScreenImage = [UIImage imageWithCGImage:[assetRepresentation fullScreenImage] scale:[assetRepresentation scale] orientation:UIImageOrientationLeft];
                     NSLog(@"image stuff, wide: %f height: %f", fullScreenImage.size.width, fullScreenImage.size.height);
                     
                     [imgView setImage:fullScreenImage];
                     [imgView setHidden:NO];
                     
                     if ([asset valueForProperty:ALAssetPropertyType] == ALAssetTypeVideo) {
                         NSLog(@"It's a video");
                         [self playMovie:asset];
                     } else {
                         NSLog(@"It's a photo");
                     }
                     *stop = YES;
                 }
             }];
    }

}

- (void)loadAlbumWithName:(NSString *)name
{
    [assetLibrary enumerateGroupsWithTypes:ALAssetsGroupAlbum
                                usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
                                    if ([[group valueForProperty:ALAssetsGroupPropertyName] isEqualToString:name]) {
                                        NSLog(@"found album %@", [group valueForProperty:ALAssetsGroupPropertyName]);
                                        assetsGroup = group;
                                        NSLog(@"assetGroup is now %@", [assetsGroup valueForProperty:ALAssetsGroupPropertyName]);
                                     }
                                }
                              failureBlock:^(NSError* error) {
                                  NSLog(@"failed to enumerate albums:\nError: %@", [error localizedDescription]);
                              }];
}

- (void)playMovie:(ALAsset*)asset {
    mainMoviePlayer = [[MPMoviePlayerController alloc] initWithContentURL:[[asset defaultRepresentation] url]];
    mainMoviePlayer.shouldAutoplay=YES;
    mainMoviePlayer.controlStyle = MPMovieControlStyleNone;
    [mainMoviePlayer setMovieSourceType: MPMovieSourceTypeFile];
    [mainMoviePlayer setFullscreen:YES animated:YES];
    [mainMoviePlayer prepareToPlay];
    [mainMoviePlayer.view setFrame: CGRectMake(0, 0, self.view.frame.size.height, self.view.frame.size.width)];
    [mainMoviePlayer.view setTag:103];
    [self.view addSubview: mainMoviePlayer.view];
    mainMoviePlayer.repeatMode = MPMovieRepeatModeOne;
    [mainMoviePlayer play];
    
    //now add gesture controls
    UIView *touchView = [[UIView alloc] initWithFrame:mainMoviePlayer.view.bounds];
    [self addGestures:touchView];
    [mainMoviePlayer.view addSubview:touchView];
    
    [self.view bringSubviewToFront:[self.view viewWithTag:104]];
    
}

- (void)moviePlayBackDidFinish:(id)sender {
    NSLog(@"Movie playback finished");
    [mainMoviePlayer stop];
    [[self.view viewWithTag:103] removeFromSuperview];
}


- (void)activateCamera
{
    if (isVideo) {
        // video camera setup
        videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset1280x720 cameraPosition:AVCaptureDevicePositionBack];
        videoCamera.outputImageOrientation = UIInterfaceOrientationLandscapeLeft;
        videoCamera.horizontallyMirrorRearFacingCamera = NO;
        [self applyFilters:videoCamera];
        [videoCamera startCameraCapture];
    } else {
        //still camera setup
        stillCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:AVCaptureSessionPreset1280x720 cameraPosition:AVCaptureDevicePositionBack];
        stillCamera.outputImageOrientation = UIInterfaceOrientationLandscapeLeft;
        stillCamera.horizontallyMirrorRearFacingCamera = NO;
        [self applyFilters:stillCamera];
        [stillCamera startCameraCapture];
    }
    [finalFilter addTarget:uberView];
}

- (void)applyFilters:(id)camera
{
    
    // SKEW THE IMAGE FROM BOTH A LEFT AND RIGHT PERSPECTIVE
    CATransform3D perspectiveTransformLeft = CATransform3DIdentity;
    perspectiveTransformLeft.m34 = .4;
    perspectiveTransformLeft = CATransform3DRotate(perspectiveTransformLeft, 0.4, 0.0, 1.0, 0.0);
    GPUImageTransformFilter *filterLeft = [[GPUImageTransformFilter alloc] init];
    [filterLeft setTransform3D:perspectiveTransformLeft];
    
    GPUImageTransformFilter *filterRight = [[GPUImageTransformFilter alloc] init];
    CATransform3D perspectiveTransformRight = CATransform3DIdentity;
    perspectiveTransformRight.m34 = .4;
    perspectiveTransformRight = CATransform3DRotate(perspectiveTransformRight, -0.4, 0.0, 1.0, 0.0);
    [(GPUImageTransformFilter *)filterRight setTransform3D:perspectiveTransformRight];
    
    //CROP THE IMAGE INTO A LEFT AND RIGHT HALF
    GPUImageCropFilter *cropLeft = [[GPUImageCropFilter alloc] init];
    GPUImageCropFilter *cropRight = [[GPUImageCropFilter alloc] init];
    
    CGRect cropRectLeft = CGRectMake((1.0 - scaleFactorX)/2, (1.0 - scaleFactorY)/2, scaleFactorX/2, scaleFactorY);
    CGRect cropRectRight = CGRectMake(.5, (1.0 - scaleFactorY)/2, scaleFactorX/2, scaleFactorY);
    
    cropLeft = [[GPUImageCropFilter alloc] initWithCropRegion:cropRectLeft];
    cropRight = [[GPUImageCropFilter alloc] initWithCropRegion:cropRectRight];
    
    //SHIFT THE LEFT AND RIGHT HALVES OVER SO THAT THEY CAN BE OVERLAID
    CGAffineTransform landscapeTransformLeft = CGAffineTransformTranslate (CGAffineTransformScale(CGAffineTransformIdentity, 0.5, 1.0), -1.0, 0.0);
    GPUImageTransformFilter *transformLeft = [[GPUImageTransformFilter alloc] init];
    transformLeft.affineTransform = landscapeTransformLeft;
    
    CGAffineTransform landscapeTransformRight = CGAffineTransformTranslate (CGAffineTransformScale(CGAffineTransformIdentity, 0.5, 1.0), 1.0, 0.0);
    GPUImageTransformFilter *transformRight = [[GPUImageTransformFilter alloc] init];
    transformRight.affineTransform = landscapeTransformRight;
    
    //CREATE A DUMMY FULL-WIDTH IMAGE
    UIImage *blankPic = [UIImage imageNamed:@"blank"];
    blankImage = [[GPUImagePicture alloc] initWithImage: blankPic];
    GPUImageAddBlendFilter *blendImages = [[GPUImageAddBlendFilter alloc] init];
    
    //STACK ALL THESE FILTERS TOGETHER
    [camera addTarget:filterLeft];
    [filterLeft addTarget:cropLeft];
    [cropLeft addTarget:transformLeft];
    
    [camera addTarget:filterRight];
    [filterRight addTarget:cropRight];
    [cropRight addTarget:transformRight];
    
    [blankImage addTarget:blendImages];
    [blankImage processImage];
    [transformLeft addTarget:blendImages];
    
    finalFilter = [[GPUImageAddBlendFilter alloc] init];
    [blendImages addTarget:finalFilter];
    [transformRight addTarget:finalFilter];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)shouldAutorotate
{
    return YES;
}


- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscapeLeft;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void) showToggleButton
{
    NSLog(@"show toggle");
    UIView *viewMode = (id)[self.view viewWithTag:100];
    
    if (!viewMode)
    {
        NSLog(@"add the toggle button");
        UIView *viewCaptureMode = [[UIView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 200, self.view.bounds.size.height - 100, 170, 75)];
        [viewCaptureMode setAutoresizingMask: UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin];
        [viewCaptureMode setTag:100];
        
        UIView *viewShadow = [[UIView alloc] initWithFrame:CGRectMake(0,0,viewCaptureMode.frame.size.width, viewCaptureMode.frame.size.height)];
        [viewShadow setBackgroundColor:[UIColor blackColor]];
        [viewShadow setAlpha:0.3];
        
        UILabel *labelCaptureMode = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 50, 20)];
        [labelCaptureMode setTag: 101];
        [labelCaptureMode setTextColor:[UIColor whiteColor]];
        [labelCaptureMode setTextAlignment:NSTextAlignmentCenter];
        
        UISwitch *switchCaptureMode = [[UISwitch alloc] initWithFrame:CGRectMake(10, 35, 50, 20)];
        [switchCaptureMode addTarget: self action: @selector(toggleCaptureMode:) forControlEvents:UIControlEventValueChanged];
        
        if(isVideo){
            [labelCaptureMode setText:@"Video"];
            [switchCaptureMode setOn: YES];
        } else {
            [labelCaptureMode setText:@"Photo"];
            [switchCaptureMode setOn: NO];
        }
        
        [viewCaptureMode addSubview: viewShadow];
        [viewCaptureMode addSubview: labelCaptureMode];
        [viewCaptureMode addSubview: switchCaptureMode];
        [self.view addSubview:viewCaptureMode];
        
        [self.view bringSubviewToFront:viewCaptureMode];
        viewMode = viewCaptureMode;
    }
    [self dimView:0.2 withAlpha:1.0 withView:viewMode withTimer:YES];

}

- (void) showCameraButton
{
    NSLog(@"show toggle");
    UIView *viewCamera = (id)[self.view viewWithTag:104];
    
    if (!viewCamera)
    {
        NSLog(@"add the camera button");
        UIView *viewCameraMode = [[UIView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 100, self.view.bounds.size.height - 100, 70, 75)];
        [viewCameraMode setAutoresizingMask: UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin];
        [viewCameraMode setTag:104];
        
        UIView *viewShadow = [[UIView alloc] initWithFrame:CGRectMake(0,0,viewCameraMode.frame.size.width, viewCameraMode.frame.size.height)];
        [viewShadow setBackgroundColor:[UIColor blackColor]];
        [viewShadow setAlpha:0.3];
        
        UIButton *buttonCamera = [[UIButton alloc] initWithFrame: CGRectMake(0, 0, 70, 75)];
        [buttonCamera setImage:[UIImage imageNamed:@"camera"] forState:UIControlStateNormal];
        [buttonCamera addTarget:self action:@selector(switchToCameraMode:) forControlEvents:UIControlEventTouchUpInside];
        [viewCameraMode addSubview: viewShadow];
        [viewCameraMode addSubview: buttonCamera];
        [self.view addSubview:viewCameraMode];
        
        [self.view bringSubviewToFront:viewCameraMode];
        viewCamera = viewCameraMode;
    }
    [self dimView:0.2 withAlpha:1.0 withView:viewCamera withTimer:YES];
    
}

- (void) switchToCameraMode: (id) sender
{
    [self hideView:[self.view viewWithTag:104]];
    [self hideViewer];
    [self showToggleButton];
}

- (void)cameraButtonTimerFired:(NSTimer *)toggleTimer
{
    [self dimView:0.5 withAlpha:0.1 withView:[self.view viewWithTag:104] withTimer:NO];
}

- (void)dimmerTimerFired:(NSTimer *)timer
{
    [self dimView:0.5 withAlpha:0.1 withView:[self.view viewWithTag:104] withTimer:NO]; // hide the switch to camera button
    [self dimView:0.5 withAlpha:0.1 withView:[self.view viewWithTag:100] withTimer:NO]; // hide the toggle view
}

- (void)hideView:(UIView *)view
{
    [self dimView:0 withAlpha:0 withView:view withTimer:NO];
}

- (void)dimView:(float)duration withAlpha:(float)alpha withView:(UIView *)view withTimer:(BOOL)showTimer
{
    NSLog(@"dim the toggle button");
    [timerDimmer invalidate];
    timerDimmer = nil;
    [UIView animateWithDuration:duration delay:0.0
                        options: (UIViewAnimationOptionCurveEaseInOut & UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{
                         view.alpha = alpha;
                     }
                     completion:^(BOOL complete){
                         timerDimmer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(dimmerTimerFired:) userInfo:nil repeats:NO];
                     }];
}

- (void) toggleCaptureMode: (id) sender {
    [self showToggleButton];
    UISwitch *toggle = (UISwitch *) sender;
    NSLog(@"%@", toggle.on ? @"Video" : @"Still");
    UILabel *toggleLabel = (id)[self.view viewWithTag:101];
    isVideo = toggle.on;
    id camera = stillCamera;
    if (toggle.on) {
        [toggleLabel setText: @"Video"];
        
    } else {
        camera = videoCamera;
        [toggleLabel setText: @"Photo"];
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
    ^{
        [camera stopCameraCapture];
        [self activateCamera];
    });
}

- (void)captureStill
{
    NSLog(@"CAPTURING STILL");
    [stillCamera capturePhotoAsJPEGProcessedUpToFilter:finalFilter withCompletionHandler:^(NSData *processedJPEG, NSError *error){
        
        // Save to assets library
        [assetLibrary writeImageDataToSavedPhotosAlbum:processedJPEG metadata:stillCamera.currentCaptureMetadata completionBlock:^(NSURL *assetURL, NSError *error2)
         {
             if (error2) {
                 NSLog(@"ERROR: the image failed to be written");
             }
             else {
                 NSLog(@"PHOTO SAVED - assetURL: %@", assetURL);
                 
                 [assetLibrary assetForURL:assetURL
                               resultBlock:^(ALAsset *asset) {
                                   // assign the photo to the album
                                   [assetsGroup addAsset:asset];
                                   NSLog(@"Added %@ to %@", [[asset defaultRepresentation] filename], [assetsGroup valueForProperty:ALAssetsGroupPropertyName]);
                               }
                              failureBlock:^(NSError* error) {
                                  NSLog(@"failed to retrieve image asset:\nError: %@ ", [error localizedDescription]);
                              }];
             }
             
             runOnMainQueueWithoutDeadlocking(^{
                 //[photoCaptureButton setEnabled:YES];
             });
         }];
    }];
}

- (void)startRecording
{
    //[self hideToggleButton];
    [self hideView:[self.view viewWithTag:100]];
    
    // Show the red "record" light
    UIImageView *imgRecord = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"record"]];
    [imgRecord setFrame:CGRectMake(self.view.bounds.size.width - 45, 20, 25, 25)];
    [imgRecord setAutoresizingMask: UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin];
    [imgRecord setTag:102];
    [self.view addSubview:imgRecord];

    // start recording the movie
    didFinishEffect = NO;
    NSString *pathToMovie = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Movie.m4v"];
    unlink([pathToMovie UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
    NSURL *movieURL = [NSURL fileURLWithPath:pathToMovie];
    movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:movieURL size:CGSizeMake(1280.0, 720.0)];
    
    
    //__unsafe_unretained typeof(self) weakSelf = self;
    
    movieWriter.completionBlock = ^{
        NSLog(@"in the completion block");
        if (didFinishEffect)
        {
            NSLog(@"already called for this video - ignoring");
        } else
        {
            didFinishEffect = YES;
            NSLog(@"GPU FILTER complete");
            [self writeMovieToLibraryWithPath:movieURL];
        }
    };
    
    [finalFilter addTarget:movieWriter];
    
    dispatch_async(dispatch_get_main_queue(),
       ^{
           NSLog(@"Start recording");
           
           videoCamera.audioEncodingTarget = movieWriter;
           [movieWriter startRecording];
       });
}

-(void)stopRecording
{
    videoCamera.audioEncodingTarget = nil;
    [finalFilter removeTarget:movieWriter];
    [movieWriter finishRecording];
    NSLog(@"Movie completed");
    [[self.view viewWithTag:102] removeFromSuperview]; // remove the "recording" light
    [self dimView:0.5 withAlpha:0.1 withView:[self.view viewWithTag:100] withTimer:NO];
    //[self dimToggleButton:0.5 withAlpha:0.1];
}

- (void)swipeScreenleft:(UITapGestureRecognizer *)tgr
{
    NSLog(@"SWIPED LEFT");
    [self showMedia:next];
}

- (void)swipeScreenRight:(UITapGestureRecognizer *)tgr
{
    NSLog(@"SWIPED RIGHT");
    [self showMedia:prev];
}

- (void)handleTapAction:(UITapGestureRecognizer *)tgr
{
    if (tgr.state == UIGestureRecognizerStateRecognized) {
        
        if (isWatching) {
            NSLog(@"VIEWER TAPPED!");
            [self showCameraButton];
            
        } else {
            NSLog(@"CAMERA TAPPED!");
            [self showToggleButton];
            CGPoint location = [tgr locationInView:uberView];
            [self setCameraFocus:location];
        }
    }
}


- (void)setCameraFocus:(CGPoint)location
{
    if (isVideo) {
        device = videoCamera.inputCamera;
    } else {
        device = stillCamera.inputCamera;
    }
    
    CGSize frameSize = [uberView frame].size;
    
    // translate the location to the position in the image coming from the device
    CGPoint pointOfInterest = CGPointMake((1.f + scaleFactorX)/2 - location.x * scaleFactorX / frameSize.height, (1.f + scaleFactorY)/2 - location.y * scaleFactorY / frameSize.width);
    
    NSLog(@"frame width = %f height = %f", frameSize.width, frameSize.height);
    NSLog(@"location x = %f y = %f", location.x, location.y);
    NSLog(@"POI x = %f y = %f", pointOfInterest.x, pointOfInterest.y);
    
    if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            [device setFocusPointOfInterest:pointOfInterest];
            
            [device setFocusMode:AVCaptureFocusModeAutoFocus];
            
            if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            {
                
                [device setExposurePointOfInterest:pointOfInterest];
                [device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
            }
            
            [device unlockForConfiguration];
            
            NSLog(@"FOCUS OK");
        } else {
            NSLog(@"ERROR = %@", error);
        }
    }
}

- (void)writeMovieToLibraryWithPath:(NSURL *)path
{
    NSLog(@"writing %@ to library", path);
    [assetLibrary writeVideoAtPathToSavedPhotosAlbum:path
                                completionBlock:^(NSURL *assetURL, NSError *error) {
                                    if (error)
                                    {
                                        NSLog(@"Error saving to library%@", [error localizedDescription]);
                                    } else
                                    {
                                        NSLog(@"SAVED %@ to photo lib",path);
                                        [assetLibrary assetForURL:assetURL
                                                      resultBlock:^(ALAsset *asset) {
                                                          // assign the photo to the album
                                                          [assetsGroup addAsset:asset];
                                                          NSLog(@"Added %@ to %@", [[asset defaultRepresentation] filename], [assetsGroup valueForProperty:ALAssetsGroupPropertyName]);
                                                      }
                                                     failureBlock:^(NSError* error) {
                                                         NSLog(@"failed to retrieve image asset:\nError: %@ ", [error localizedDescription]);
                                                     }];
                                    }
                                }];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationLandscapeLeft);
}


@end
