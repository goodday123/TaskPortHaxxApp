//
//  main.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "Header.h"

int child_execve(char *path) {
    mach_port_t exception_port = MACH_PORT_NULL;
    mach_port_t fake_bootstrap_port = MACH_PORT_NULL;
    bootstrap_look_up(bootstrap_port, "com.kdt.taskporthaxx.exception_server", &exception_port);
    assert(exception_port != MACH_PORT_NULL);
    bootstrap_look_up(bootstrap_port, "com.kdt.taskporthaxx.fake_bootstrap_port", &fake_bootstrap_port);
    assert(fake_bootstrap_port != MACH_PORT_NULL);
    
    task_set_exception_ports(mach_task_self(),
        EXC_MASK_ALL | EXC_MASK_CRASH,
        exception_port,
        EXCEPTION_STATE_IDENTITY | MACH_EXCEPTION_CODES,
        ARM_THREAD_STATE64);
    task_set_bootstrap_port(mach_task_self(), fake_bootstrap_port);
    
    posix_spawnattr_t attr;
    if(posix_spawnattr_init(&attr) != 0) {
        perror("posix_spawnattr_init");
        return 1;
    }
    
    if(posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC | POSIX_SPAWN_START_SUSPENDED) != 0) {
        perror("posix_spawnattr_set_flags");
        return 1;
    }
    
    posix_spawnattr_set_registered_ports_np(&attr, (mach_port_t[]){0, bootstrap_port, fake_bootstrap_port}, 3);
    posix_spawnattr_setexceptionports_np(&attr,
        EXC_MASK_ALL | EXC_MASK_CRASH,
        exception_port, EXCEPTION_STATE_IDENTITY | MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
    char *argv2[] = { path, NULL };
    posix_spawn(NULL, argv2[0], NULL, &attr, argv2, environ);
    perror("posix_spawn");
    return 1;
}

int main(int argc, char * argv[]) {
    if(argc >= 2) {
        if (argc > 2 && strcmp(argv[1], "attach") == 0) {
            pid_t launched_pid = atoi(argv[2]);
            int i = ptrace(14, launched_pid, 0, 0);
            printf("ptrace attach returned %d\n", i);
            if (i != 0) {
                return 1;
            }
            ptrace(7, launched_pid, (void*)1, 0);
            CFRunLoopRun();
        } else if (strcmp(argv[1], "dtsecurity") == 0) {
            sleep(1); // FIXME: how to sleep until ptrace attach?
            NSString *execDir = @"/var/db/com.apple.xpc.roleaccountd.staging/exec";
            [NSFileManager.defaultManager createDirectoryAtPath:execDir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *outDir = @"/var/db/com.apple.xpc.roleaccountd.staging/exec/TaskPortHaxx.xpc";
            if (![[NSFileManager defaultManager] fileExistsAtPath:outDir]) {
                NSError *error = nil;
                [NSFileManager.defaultManager copyItemAtPath:@"/System/Library/PrivateFrameworks/DVTInstrumentsFoundation.framework/XPCServices/com.apple.dt.instruments.dtsecurity.xpc" toPath:outDir error:&error];
                if (error) {
                    NSLog(@"Failed to copy dtsecurity.xpc: %@", error);
                    return 1;
                }
            }
            return child_execve("/var/db/com.apple.xpc.roleaccountd.staging/exec/TaskPortHaxx.xpc/com.apple.dt.instruments.dtsecurity");
//        } else if (strcmp(argv[1], "signal") == 0) {
//            assert(argc >= 3);
//            pid_t target_pid = (pid_t)atoi(argv[2]);
//            kill(target_pid, SIGTRAP);
//            return 0;
        }
    }
    
//    if (getuid() != 0) {
//        launchTest(nil);
//        return 0;
//    }
    
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
