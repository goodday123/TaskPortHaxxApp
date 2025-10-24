//
//  ViewController.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

#import "ViewController.h"
#include "Header.h"

int haxxTest(void) {
    char **argv = *_NSGetArgv();
    
    // parent process
    pid_t pid;
    char ppid_str[16];
    snprintf(ppid_str, sizeof(ppid_str), "%d", getpid());
    
    char *child_argv[] = { argv[0], "-parent", ppid_str, NULL };
    int status = posix_spawn(&pid, child_argv[0], NULL, NULL, child_argv, environ);
    if (status != 0) {
        perror("posix_spawn child failed");
        return 1;
    }
    printf("Child process spawned with PID: %d\n", pid);
    
    mach_port_t exception_port = MACH_PORT_NULL;
    do {
        kern_return_t kr = bootstrap_look_up(bootstrap_port, "com.kdt.taskporthaxx.exception_server", &exception_port);
        if (kr == KERN_SUCCESS) {
            break;
        }
        usleep(10000);
    } while(exception_port == MACH_PORT_NULL);
    
    posix_spawnattr_t attr;
    if(posix_spawnattr_init(&attr) != 0) {
        perror("posix_spawnattr_init");
        return 1;
    }
    if(getppid() == 1) {
        if(posix_spawnattr_set_launch_type_np(&attr, 1) != 0) {
            perror("posix_spawnattr_set_launch_type_np");
            return 1;
        }
    } else {
        printf("Not launched by launchd, might not work\n");
    }
    
    posix_spawnattr_setexceptionports_np(&attr,
        EXC_MASK_ALL,
        exception_port,
        EXCEPTION_STATE | MACH_EXCEPTION_CODES,
        ARM_THREAD_STATE64);
    
    if(posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC) != 0) {
        perror("posix_spawnattr_set_flags");
        return 1;
    }
    
    // /System/Library/CoreServices/SpringBoard.app/SpringBoard"
    char *argv2[] = { "/usr/libexec/runningboardd", "-parent", ppid_str, NULL };
    posix_spawn(NULL, argv2[0], NULL, &attr, argv2, environ);
    perror("posix_spawn");
    return 0;
}

@interface ViewController ()
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Task Port Haxx";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Test" style:UIBarButtonItemStylePlain target:self action:@selector(testButtonTapped)];
    
}

- (void)testButtonTapped {
    haxxTest();
}

@end
