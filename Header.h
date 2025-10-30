//
//  Header.h
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

@import Darwin;
#include <crt_externs.h>

uint64_t _tmp_ptr;

#define RemoteArbCall(pc, ...) RemoteArbCallInternal((uint64_t)(pc), (uint64_t[]){__VA_ARGS__}, sizeof((uint64_t[]){__VA_ARGS__})/sizeof(uint64_t))
uint64_t RemoteArbCallInternal(uint64_t pc, uint64_t args[], int argCount);
uint64_t RemoteRead64(uint64_t address);
void RemoteWrite64(uint64_t address, uint64_t value);
void RemoteWriteMemory(uint64_t address, const void *data, size_t length);
void RemoteWriteString(uint64_t address, const char *string);
void RemoteDetach(void);

#define PT_DETACH 11
#define PT_ATTACHEXC 14

uintptr_t brX16Address;
BOOL wantsDetach;
mach_port_t GlobalChildTaskPort;
mach_port_t GlobalChildThreadPort;
extern char **environ;

uint64_t __atomic_load_8(uint64_t *ptr, int memorder);
void __atomic_store_8(uint64_t *ptr, uint64_t val, int memorder);

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
pid_t spawn_exploit_process(mach_port_t exception_port);
pid_t spawn_sleep_process(void);
mach_port_t psychicpaper_proxy(mach_port_t task);

@interface NSProcessInfo(Private)
- (NSDate *)systemStartTime;
@end
