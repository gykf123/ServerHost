//
//  main.mm
//  ServerHost
//
//  C++ HTTP Server + AVAudioEngine keepalive for iPad
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "httplib.h"

#include <unistd.h>
#include <string>
#include <cstring>
#include <dispatch/dispatch.h>

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
static httplib::Server g_server;
static AVAudioEngine   *g_audioEngine = nil;
static AVAudioPlayerNode *g_playerNode = nil;

// ---------------------------------------------------------------------------
// C++ HTTP Server
// ---------------------------------------------------------------------------
static void start_server(const std::string &base_dir) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        // Serve static files from the selected directory
        if (!g_server.set_base_dir(base_dir)) {
            NSLog(@"set_base_dir failed for: %s", base_dir.c_str());
        }

        // Simple health-check endpoint
        g_server.Get("/ping", [](const httplib::Request & /*req*/,
                                 httplib::Response &res) {
            res.set_content("pong", "text/plain");
        });

        NSLog(@"Server starting on 127.0.0.1:8080, base_dir=%s", base_dir.c_str());
        if (!g_server.listen("127.0.0.1", 8080)) {
            NSLog(@"Failed to listen on 127.0.0.1:8080");
        }
    });
}

// ---------------------------------------------------------------------------
// Silent audio keepalive (AVAudioEngine + looping zero buffer)
// ---------------------------------------------------------------------------
static void setup_silent_audio() {
    NSError *error = nil;

    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback
                    mode:AVAudioSessionModeDefault
                 options:AVAudioSessionCategoryOptionMixWithOthers
                   error:&error];
    if (error) {
        NSLog(@"AVAudioSession setCategory error: %@", error);
    }
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"AVAudioSession setActive error: %@", error);
    }

    g_audioEngine = [[AVAudioEngine alloc] init];
    g_playerNode  = [[AVAudioPlayerNode alloc] init];
    [g_audioEngine attachNode:g_playerNode];

    // 0.1 s of silence at 44.1 kHz mono float32  →  4410 frames
    AVAudioFormat *format =
        [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
    AVAudioPCMBuffer *buffer =
        [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:4410];
    buffer.frameLength = 4410;
    std::memset(buffer.floatChannelData[0], 0,
                4410 * sizeof(float));

    [g_audioEngine connect:g_playerNode to:g_audioEngine.mainMixerNode format:format];
    [g_audioEngine prepare];
    if (![g_audioEngine startAndReturnError:&error]) {
        NSLog(@"AVAudioEngine start error: %@", error);
        return;
    }

    [g_playerNode play];
    [g_playerNode scheduleBuffer:buffer
                          atTime:nil
                         options:AVAudioPlayerNodeBufferLoops
                  completionHandler:nil];

    NSLog(@"Silent audio keepalive started");
}

// ---------------------------------------------------------------------------
// View Controller
// ---------------------------------------------------------------------------
@interface ViewController : UIViewController <UIDocumentPickerDelegate>
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) NSURL  *selectedURL;
@property (assign, nonatomic) BOOL   pickerShown;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];

    CGFloat w = self.view.bounds.size.width;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 120, w - 40, 120)];
    self.statusLabel.text = @"正在启动...\n请选择 HTML 文件";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:16];
    [self.view addSubview:self.statusLabel];

    // A simple "Re-pick" button in case the user wants to choose another folder
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(w / 2 - 80, 260, 160, 44);
    [btn setTitle:@"重新选择文件" forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(presentPicker) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.pickerShown) {
        self.pickerShown = YES;
        [self presentPicker];
    }
}

- (void)presentPicker {
    NSArray<UTType *> *contentTypes = @[UTTypeHTML];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes
                                                           asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;

    NSURL *fileURL = urls.firstObject;

    // Keep the security-scoped resource alive
    if (self.selectedURL) {
        [self.selectedURL stopAccessingSecurityScopedResource];
    }
    [fileURL startAccessingSecurityScopedResource];
    self.selectedURL = fileURL;

    // Extract the directory containing the selected HTML file
    NSString *dirPath = [[fileURL URLByDeletingLastPathComponent] path];
    std::string baseDir = std::string([dirPath UTF8String]);

    // chdir() so relative paths in the server resolve correctly
    if (chdir(baseDir.c_str()) != 0) {
        NSLog(@"chdir(\"%s\") failed: %s", baseDir.c_str(), strerror(errno));
    }

    // Update UI
    NSString *fileName = [fileURL lastPathComponent];
    self.statusLabel.text =
        [NSString stringWithFormat:@"已选择：%@/%@\nServer 运行中 (127.0.0.1:8080)",
         dirPath, fileName];

    // Start the C++ HTTP server on a background thread
    start_server(baseDir);

    // Start silent audio keepalive
    setup_silent_audio();
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.statusLabel.text = @"已取消选择\nServer 未启动";
}

@end

// ---------------------------------------------------------------------------
// App Delegate
// ---------------------------------------------------------------------------
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

// ---------------------------------------------------------------------------
// main()
// ---------------------------------------------------------------------------
int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([AppDelegate class]));
    }
}
