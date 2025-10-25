//
//  Header.h
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

@import Darwin;
#include <crt_externs.h>

mach_port_t GlobalChildTaskPort;
mach_port_t GlobalChildThreadPort;
extern char **environ;

kern_return_t
bootstrap_register(mach_port_t bp, const char *service_name, mach_port_t sp);
kern_return_t
bootstrap_look_up(mach_port_t bp, const char *service_name, mach_port_t *sp);

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);
int posix_spawnattr_set_launch_type_np(posix_spawnattr_t *attr, uint8_t launch_type);
int posix_spawnattr_set_ptrauth_task_port_np(posix_spawnattr_t * __restrict attr, mach_port_t port);
int posix_spawnattr_setexceptionports_np(posix_spawnattr_t *attr,
         exception_mask_t mask, mach_port_t new_port,
         exception_behavior_t behavior, thread_state_flavor_t flavor);

mach_port_t setup_exception_server(void);
pid_t child_spawn(void);
mach_port_t psychicpaper_proxy(mach_port_t task);
