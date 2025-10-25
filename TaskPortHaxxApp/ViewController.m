//
//  ViewController.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

#import "ViewController.h"
#include "Header.h"
#include <sys/wait.h>

@interface ViewController ()
@property(nonatomic) mach_port_t exceptionPort;
@property(nonatomic) UITextView *logTextView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.exceptionPort = setup_exception_server();
    
    self.navigationItem.title = @"Task Port Haxx";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Test" style:UIBarButtonItemStylePlain target:self action:@selector(testButtonTapped)];
    
    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.editable = NO;
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.text = @"Log Output:\n";
    textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    [self.view addSubview:textView];
    self.logTextView = textView;
    [self redirectStdio];
}

- (void)redirectStdio {
    setvbuf(stdout, 0, _IOLBF, 0); // make stdout line-buffered
    setvbuf(stderr, 0, _IONBF, 0); // make stderr unbuffered
    
    /* create the pipe and redirect stdout and stderr */
    static int pfd[2];
    pipe(pfd);
    dup2(pfd[1], fileno(stdout));
    dup2(pfd[1], fileno(stderr));
    
    /* create the logging thread */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        static BOOL filteredSessionID;
        ssize_t rsize;
        char buf[2048];
        while((rsize = read(pfd[0], buf, sizeof(buf)-1)) > 0) {
            if (rsize < 2048) {
                buf[rsize] = '\0';
            }
            NSString *logLine = [NSString stringWithUTF8String:buf];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.logTextView.text = [self.logTextView.text stringByAppendingString:logLine];
                NSRange bottom = NSMakeRange(self.logTextView.text.length -1, 1);
                [self.logTextView scrollRangeToVisible:bottom];
            });
        }
    });
}

- (void)testButtonTapped {
    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, /*persona_id=*/99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    //posix_spawnattr_set_ptrauth_task_port_np(&attr, mach_task_self());
    char *argv[] = {**_NSGetArgv(), "child", NULL};
    int ret = posix_spawn(&pid, argv[0], NULL, &attr, argv, environ);
    if (ret) {
        perror("posix_spawn");
        return;
    }
    NSLog(@"Spawned child launchd with PID %d", pid);
}

@end
