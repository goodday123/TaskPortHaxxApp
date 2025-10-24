//
//  Header.h
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

@import Darwin;
#include <crt_externs.h>

extern char **environ;

kern_return_t
bootstrap_register(mach_port_t bp, const char *service_name, mach_port_t sp);
kern_return_t
bootstrap_look_up(mach_port_t bp, const char *service_name, mach_port_t *sp);
int posix_spawnattr_set_launch_type_np(posix_spawnattr_t *attr, uint8_t launch_type);
int posix_spawnattr_setexceptionports_np(posix_spawnattr_t *attr,
         exception_mask_t mask, mach_port_t new_port,
         exception_behavior_t behavior, thread_state_flavor_t flavor);
