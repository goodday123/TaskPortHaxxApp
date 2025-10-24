//
//  ViewController.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

#import "ViewController.h"
#include "Header.h"

@interface ViewController ()
@property(nonatomic) mach_port_t exceptionPort;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.exceptionPort = setup_exception_server();
    
    self.navigationItem.title = @"Task Port Haxx";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Test" style:UIBarButtonItemStylePlain target:self action:@selector(testButtonTapped)];
}

- (void)testButtonTapped {
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, /*persona_id=*/99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    posix_spawnattr_setexceptionports_np(&attr,
        EXC_MASK_ALL,
        self.exceptionPort,
        EXCEPTION_STATE | MACH_EXCEPTION_CODES,
        ARM_THREAD_STATE64);
    char *argv[] = {**_NSGetArgv(), "child", NULL};
    int ret = posix_spawn(NULL, argv[0], NULL, &attr, argv, environ);
    if (ret) {
        perror("posix_spawn");
        return;
    }
}

@end
