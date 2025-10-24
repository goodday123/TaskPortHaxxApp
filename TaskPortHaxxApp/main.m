//
//  main.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "Header.h"

int spawn_launchd(void) {
    mach_port_t exception_port = MACH_PORT_NULL;
    bootstrap_look_up(bootstrap_port, "com.kdt.taskporthaxx.exception_server", &exception_port);
    assert(exception_port != MACH_PORT_NULL);
    task_set_exception_ports(mach_task_self(),
        EXC_MASK_ALL,
        exception_port,
        EXCEPTION_STATE | MACH_EXCEPTION_CODES,
        ARM_THREAD_STATE64);
    
    posix_spawnattr_t attr;
    if(posix_spawnattr_init(&attr) != 0) {
        perror("posix_spawnattr_init");
        return 1;
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
    
    raise(SIGTRAP);
    
    char *argv2[] = { "/sbin/launchd", "child", NULL };
    posix_spawn(NULL, argv2[0], NULL, &attr, argv2, environ);
    perror("posix_spawn");
    return 1;
}

int main(int argc, char * argv[]) {
    if(argc == 2 && strcmp(argv[1], "child") == 0) {
        return spawn_launchd();
    }
    
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
