//
//  main.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#include "Header.h"
// These are provided by mig
#include "mach_exc.h"
#include "mach_excServer.h"

void spawn_opainject_for_task(pid_t pid) {
    // spawn opainject here lol
    char pidStr[16];
    snprintf(pidStr, sizeof(pidStr), "%d", pid);
    NSString *opainjectPath = [[NSBundle mainBundle] pathForResource:@"opainject" ofType:nil];
    char *argsToPass[] = {(char *)opainjectPath.fileSystemRepresentation, pidStr, "/usr/lib/libFaultOrdering.dylib", NULL};
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, /*persona_id=*/99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    //posix_spawnattr_set_ptrauth_task_port_np(&attr, task);
    int status = -200;
    pid_t opainjectPid;
    int rc = posix_spawn(&opainjectPid, argsToPass[0], NULL, &attr, argsToPass, NULL);
    posix_spawnattr_destroy(&attr);
    if(rc != KERN_SUCCESS) {
        printf("[TaskPortHaxxSpawn] posix_spawn failed: %d (%s)\n", rc, mach_error_string(rc));
    }
    do {
        if (waitpid(opainjectPid, &status, 0) != -1) {
            printf("[TaskPortHaxxSpawn] Child returned %d\n", WEXITSTATUS(status));
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));
}

BOOL done = NO;
kern_return_t catch_mach_exception_raise_state (mach_port_t exception_port,
                                                exception_type_t exception,
                                                const mach_exception_data_t code,
                                                mach_msg_type_number_t code_cnt,
                                                int *flavor,
                                                const thread_state_t old_state_,
                                                mach_msg_type_number_t old_state_cnt,
                                                thread_state_t new_state_,
                                                mach_msg_type_number_t *new_state_cnt)
{
    // unused
    return KERN_FAILURE;
}

// unused, just here to satisfy the linker / mig bits
kern_return_t catch_mach_exception_raise_state_identity (mach_port_t exception_port,
                                                         mach_port_t thread,
                                                         mach_port_t task,
                                                         exception_type_t exception,
                                                         mach_exception_data_t code,
                                                         mach_msg_type_number_t codeCnt,
                                                         int *flavor,
                                                         const thread_state_t old_state_,
                                                         mach_msg_type_number_t old_state_cnt,
                                                         thread_state_t new_state_,
                                                         mach_msg_type_number_t *new_state_cnt)
{
    printf("got task port: %d\n", task);
    
    NSLog(@"exception handler raise state - exception %d", exception);
    if (*flavor == ARM_THREAD_STATE64) {
        const arm_thread_state64_t *old_state = (const arm_thread_state64_t*)old_state_;
        if (done) {
            return KERN_FAILURE;
        }
        done = YES;
        
        task_set_bootstrap_port(task, bootstrap_port);
        
        arm_thread_state64_t *new_state = (arm_thread_state64_t*)new_state_;
        //NSLog(@"fault address: %p", __darwin_arm_thread_state64_get_pc_fptr(*new_state));
        memcpy(new_state, old_state, sizeof(arm_thread_state64_t));
        //__darwin_arm_thread_state64_set_lr_fptr(*new_state, (void *)0x4242424200);
        for (int i = 0; i < 29; i++) {
            new_state->__x[i] = 0x4141414100 + i;
        }
        
        void *pc = __darwin_arm_thread_state64_get_pc_fptr(*new_state);
        pc = ptrauth_strip(pc, ptrauth_key_function_pointer);
        
        __darwin_arm_thread_state64_set_pc_fptr(*new_state, (void *)ptrauth_sign_unauthenticated(ptrauth_strip((void*)((uintptr_t)pc + 4000000), ptrauth_key_function_pointer), ptrauth_key_function_pointer, 0));
        NSLog(@"resume address: %p", __darwin_arm_thread_state64_get_pc_fptr(*new_state));
        *new_state_cnt = old_state_cnt;
        
        // i'm too lazy to pass mach port so let's give it to launchd
        pid_t pid = 0;
        kern_return_t kr = pid_for_task(task, &pid);
        NSCAssert(kr == KERN_SUCCESS, @"pid_for_task failed: %d", kr);
        char service_name[64];
        snprintf(service_name, sizeof(service_name), "com.kdt.taskporthaxx.task_for_pid_%d", pid);
        kr = bootstrap_register(bootstrap_port, service_name, task);
        NSCAssert(kr == KERN_SUCCESS, @"bootstrap_register failed: %d", kr);
        
        NSLog(@"reading memory at pc: 0x%llx", (uint64_t)pc);
        uint8_t buffer[16];
        mach_vm_size_t size = sizeof(buffer);
        kr = vm_read_overwrite(task, (vm_address_t)pc, size, (mach_vm_address_t)buffer, &size);
        if (kr == KERN_SUCCESS) {
            NSLog(@"read %llu bytes from 0x%llx:", size, pc);
            for (mach_vm_size_t i = 0; i < size; i++) {
                printf("%02x ", buffer[i]);
            }
            printf("\n");
        } else {
            NSLog(@"mach_vm_read_overwrite failed: %d", kr);
        }
        
        // create a test thread
        arm_thread_state64_t test_state;
        memcpy(&test_state, new_state, sizeof(arm_thread_state64_t));
        __darwin_arm_thread_state64_set_pc_fptr(test_state, (void *)ptrauth_sign_unauthenticated(ptrauth_strip((void*)0x47474747470, ptrauth_key_function_pointer), ptrauth_key_function_pointer, 0));
        thread_t test_thread;
        kr = thread_create_running(task, ARM_THREAD_STATE64, (thread_state_t)&test_state, ARM_THREAD_STATE64_COUNT, &test_thread);
        if(kr != KERN_SUCCESS)
        {
            NSLog(@"[createRemotePthread] ERROR: Failed to create running thread: %s.", mach_error_string(kr));
        }
        NSLog(@"created test thread: %d", test_thread);
        
        task_suspend(task);
        return KERN_SUCCESS;
    }
    return KERN_SUCCESS;
}
 
kern_return_t catch_mach_exception_raise (mach_port_t exception_port,
                                          mach_port_t thread,
                                          mach_port_t task,
                                          exception_type_t exception,
                                          mach_exception_data_t code,
                                          mach_msg_type_number_t codeCnt) {
    printf("catch_mach_exception_raise called\n");
    return KERN_FAILURE;
}
 
extern boolean_t mach_exc_server (mach_msg_header_t *msg, mach_msg_header_t *reply);
static void exception_server(mach_port_t exceptionPort)
{
    mach_msg_return_t rt;
    mach_msg_header_t *msg;
    mach_msg_header_t *reply;
 
    msg = malloc(sizeof(union __RequestUnion__mach_exc_subsystem));
    reply = malloc(sizeof(union __ReplyUnion__mach_exc_subsystem));
    NSLog(@"server starting");
    while (1) {
        rt = mach_msg(msg, MACH_RCV_MSG, 0, sizeof(union __RequestUnion__mach_exc_subsystem), exceptionPort, 0, MACH_PORT_NULL);
        assert(rt == MACH_MSG_SUCCESS);
 
        NSLog(@"server received message");
        
        // Call out to the mach_exc_server generated by mig and mach_exc.defs.
        // This will in turn invoke one of:
        // mach_catch_exception_raise()
        // mach_catch_exception_raise_state()
        // mach_catch_exception_raise_state_identity()
        // .. depending on the behavior specified when registering the Mach exception port.
        mach_exc_server(msg, reply);
 
        // Send the now-initialized reply
        rt = mach_msg(reply, MACH_SEND_MSG, reply->msgh_size, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
        assert(rt == MACH_MSG_SUCCESS);
    }
}

mach_port_t setup_exception_server(void) {
    mach_port_t server_port;
    kern_return_t kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &server_port);
    assert(kr == KERN_SUCCESS);
    kr = mach_port_insert_right(mach_task_self(), server_port, server_port, MACH_MSG_TYPE_MAKE_SEND);
    assert(kr == KERN_SUCCESS);
    kr = bootstrap_register(bootstrap_port, "com.kdt.taskporthaxx.exception_server", server_port);
    assert(kr == KERN_SUCCESS);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        exception_server(server_port);
    });
    return server_port;
}
