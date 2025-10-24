//
//  ViewController.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

#import "ViewController.h"
#include "Header.h"

@interface ViewController ()
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Task Port Haxx";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Test" style:UIBarButtonItemStylePlain target:self action:@selector(testButtonTapped)];
    
}

- (void)testButtonTapped {
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID);
    posix_spawnattr_set_persona_np(&attr, /*persona_id=*/99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    //int pid = 0;
    char **argv = *_NSGetArgv();
    char *argv2[] = { argv[0], "/usr/libexec/runningboardd", NULL };
    int ret = posix_spawn(NULL, argv2[0], NULL, &attr, argv2, environ);
    if (ret) {
        perror("posix_spawn");
        return;
    }
    exit(0);
}

@end
