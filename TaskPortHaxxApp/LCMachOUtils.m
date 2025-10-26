@import Darwin;
@import Foundation;
@import MachO;

static uint32_t rnd32(uint32_t v, uint32_t r) {
    r--;
    return (v + r) & ~r;
}

struct dyld_all_image_infos *_alt_dyld_get_all_image_infos(void) {
    static struct dyld_all_image_infos *result;
    if (result) {
        return result;
    }
    struct task_dyld_info dyld_info;
    mach_vm_address_t image_infos;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t ret;
    ret = task_info(mach_task_self_,
                    TASK_DYLD_INFO,
                    (task_info_t)&dyld_info,
                    &count);
    if (ret != KERN_SUCCESS) {
        return NULL;
    }
    image_infos = dyld_info.all_image_info_addr;
    result = (struct dyld_all_image_infos *)image_infos;
    return result;
}

NSString *LCParseMachO(const char *path, bool readOnly, LCParseMachOCallback callback) {
    int fd = open(path, readOnly ? O_RDONLY : O_RDWR, (mode_t)readOnly ? 0400 : 0600);
    struct stat s;
    fstat(fd, &s);
    void *map = mmap(NULL, s.st_size, readOnly ? PROT_READ : (PROT_READ | PROT_WRITE), readOnly ? MAP_PRIVATE : MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
    }

    uint32_t magic = *(uint32_t *)map;
    if (magic == FAT_CIGAM) {
        // Find compatible slice
        struct fat_header *header = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
        for (int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
            if (OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                callback(path, (struct mach_header_64 *)(map + OSSwapInt32(arch->offset)), fd, map);
            }
            arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
        }
    } else if (magic == MH_MAGIC_64 || magic == MH_MAGIC) {
        callback(path, (struct mach_header_64 *)map, fd, map);
    } else {
        return @"Not a Mach-O file";
    }

    msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
    return nil;
}

NSString *LCPatchMachOFixupARM64eSlice(const char *path) {
    int fd = open(path, O_RDWR, 0600);
    if(fd < 0) {
        return [NSString stringWithFormat:@"Failed to open %s: %s", path, strerror(errno)];
    }
    struct stat s = {0};
    fstat(fd, &s);
    void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if(map == MAP_FAILED) {
        close(fd);
        return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
    }

    uint32_t magic = *(uint32_t *)map;
    if(magic == FAT_CIGAM) {
        // Find arm64e slice without CPU_SUBTYPE_LIB64
        struct fat_header *header = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
        for(int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
            if(OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64 && OSSwapInt32(arch->cpusubtype) == CPU_SUBTYPE_ARM64E) {
                struct mach_header_64 *header = (struct mach_header_64 *)(map + OSSwapInt32(arch->offset));
                header->cpusubtype |= CPU_SUBTYPE_LIB64;
                arch->cpusubtype = htonl(header->cpusubtype);
                break;
            }
            arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
        }
    }

    msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
    return nil;
}

void LCPatchAppBundleFixupARM64eSlice(NSURL *bundleURL) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:bundleURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    for (NSURL *fileURL in enumerator) {
        if ([fileURL.pathExtension isEqualToString:@"dylib"]) {
            LCPatchMachOFixupARM64eSlice(fileURL.path.fileSystemRepresentation);
        } else if ([fileURL.pathExtension isEqualToString:@"framework"]) {
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[fileURL URLByAppendingPathComponent:@"Info.plist"]];
            NSString *executableName = info[@"CFBundleExecutable"];
            if(!executableName) {
                executableName = fileURL.lastPathComponent.stringByDeletingPathExtension;
            }
            NSURL *executableURL = [fileURL URLByAppendingPathComponent:executableName];
            LCPatchMachOFixupARM64eSlice(executableURL.path.fileSystemRepresentation);
        }
    }
}

void LCChangeMachOUUID(struct mach_header_64 *header) {
    struct load_command *command = (struct load_command *)(header + 1);
    for(int i = 0; i < header->ncmds; i++) {
        if(command->cmd == LC_UUID) {
            struct uuid_command *uuidCmd = (struct uuid_command *)command;
            // let's add the first byte by 1
            uuidCmd->uuid[0] += 1;
            break;
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }
}

const uint8_t* LCGetMachOUUID(struct mach_header_64 *header) {
    if (!header) return NULL;

    // Find load commands
    const struct load_command* command = (const struct load_command*)(header + 1);

    // Iterate through load commands to find LC_SYMTAB
    for(uint32_t i = 0; i < header->ncmds; i++) {
        if(command->cmd == LC_UUID) {
            return ((const struct uuid_command*)command)->uuid;
        }
        command = (const struct load_command*)((void *)command + command->cmdsize);
    }
    return NULL;
}

uint64_t LCFindSymbolOffset(const char *basePath, const char *symbol) {
#if !TARGET_OS_SIMULATOR
    const char *path = basePath;
#else
    char path[PATH_MAX];
    const char *rootPath = getenv("DYLD_ROOT_PATH") ?: "";
    snprintf(path, sizeof(path), "%s%s", rootPath, basePath);
#endif
    __block uint64_t offset = 0;
    LCParseMachO(path, true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
        if(header->cputype != CPU_TYPE_ARM64) return;
        void *result = litehook_find_symbol_file(header, symbol);
        offset = (uint64_t)result - (uint64_t)header;
    });
    NSCAssert(offset != 0, @"Failed to find symbol %s in %s", symbol, path);
    return offset;
}

mach_header_u *LCGetLoadedImageHeader(int i0, const char* name) {
    for(uint32_t i = i0; i < _dyld_image_count(); ++i) {
        const char* imgName = _dyld_get_image_name(i);
        // cover simulator path aswell
        if(imgName && strcmp(imgName + (strlen(imgName) - strlen(name)), name) == 0) {
            return (struct mach_header_64*)_dyld_get_image_header(i);
        }
    }
    return NULL;
}

#if TARGET_OS_SIMULATOR
// Make it init first on simulator to find dyld_sim
__attribute__((constructor))
#endif
void *getDyldBase(void) {
    void *dyldBase = (void *)_alt_dyld_get_all_image_infos()->dyldImageLoadAddress;
#if !TARGET_OS_SIMULATOR
    return dyldBase;
#else
    static void *dyldSimBase = NULL;
    if(!dyldSimBase) {
        __block size_t textSize = 0;
        LCParseMachO("/usr/lib/dyld", true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
            if(header->cputype != CPU_TYPE_ARM64) return;
            getsegmentdata(header, SEG_TEXT, &textSize);
        });
        NSArray *callStack = [NSThread callStackReturnAddresses];
        for(NSNumber *addr in callStack.reverseObjectEnumerator) {
            // the first addresss outside of dyld's text is dyld_sim
            uintptr_t addrValue = addr.unsignedLongLongValue;
            if(addrValue < (uintptr_t)dyldBase || addrValue >= (uintptr_t)dyldBase + textSize) {
                dyldSimBase = (void *)(addrValue & ~PAGE_MASK);
                break;
            }
        }
    }
    return dyldSimBase;
#endif
}

struct code_signature_command {
    uint32_t    cmd;
    uint32_t    cmdsize;
    uint32_t    dataoff;
    uint32_t    datasize;
};

// from zsign
struct ui_CS_BlobIndex {
    uint32_t type;                    /* type of entry */
    uint32_t offset;                /* offset of entry */
};

struct ui_CS_SuperBlob {
    uint32_t magic;                    /* magic number */
    uint32_t length;                /* total length of SuperBlob */
    uint32_t count;                    /* number of index entries following */
    //CS_BlobIndex index[];            /* (count) entries */
    /* followed by Blobs in no particular order as indicated by offsets in index */
};

struct ui_CS_blob {
    uint32_t magic;
    uint32_t length;
};


struct code_signature_command* findSignatureCommand(struct mach_header_64* header) {
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    struct code_signature_command* codeSignCommand = 0;
    for(int i = 0; i < header->ncmds; i++) {
        if(command->cmd == LC_CODE_SIGNATURE) {
            codeSignCommand = (struct code_signature_command*)command;
            break;
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }
    return codeSignCommand;
}

NSString* getEntitlementXML(struct mach_header_64* header, void** entitlementXMLPtrOut) {
    struct code_signature_command* codeSignCommand = findSignatureCommand(header);

    if(!codeSignCommand) {
        return @"Unable to find LC_CODE_SIGNATURE command.";
    }
    struct ui_CS_SuperBlob* blob = (void*)header + codeSignCommand->dataoff;
    if(blob->magic != OSSwapInt32(0xfade0cc0)) {
        return [NSString stringWithFormat:@"CodeSign blob magic mismatch %8x.", blob->magic];
    }
    struct ui_CS_BlobIndex* entitlementBlobIndex = 0;
    struct ui_CS_BlobIndex* nowIndex = (void*)blob + sizeof(struct ui_CS_SuperBlob);
    for(int i = 0; i < OSSwapInt32(blob->count); i++) {
        if(OSSwapInt32(nowIndex->type) == 5) {
            entitlementBlobIndex = nowIndex;
            break;
        }
        nowIndex = (void*)nowIndex + sizeof(struct ui_CS_BlobIndex);
    }
    if(entitlementBlobIndex == 0) {
        return @"[LC] entitlement blob index not found.";
    }
    struct ui_CS_blob* entitlementBlob = (void*)blob + OSSwapInt32(entitlementBlobIndex->offset);
    if(entitlementBlob->magic != OSSwapInt32(0xfade7171)) {
        return [NSString stringWithFormat:@"EntitlementBlob magic mismatch %8x.", blob->magic];
    };
    int32_t xmlLength = OSSwapInt32(entitlementBlob->length) - sizeof(struct ui_CS_blob);
    void* xmlPtr = (void*)entitlementBlob + sizeof(struct ui_CS_blob);
    
    if(entitlementXMLPtrOut) {
        *entitlementXMLPtrOut = xmlPtr;
    }

    // entitlement xml in executable don't have \0 so we have to copy it first
    char* xmlString = malloc(xmlLength + 1);
    memcpy(xmlString, xmlPtr, xmlLength);
    xmlString[xmlLength] = 0;

    NSString* ans = [NSString stringWithUTF8String:xmlString];
    free(xmlString);
    return ans;
}

bool checkCodeSignature(const char* path) {
    __block bool checked = false;
    __block bool ans = false;
    LCParseMachO(path, true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
        if(checked || header->cputype != CPU_TYPE_ARM64) {
            return;
        }
        checked = true;
        
        struct code_signature_command* codeSignatureCommand = findSignatureCommand(header);
        if(!codeSignatureCommand) {
            return;
        }
        off_t sliceOffset = (void*)header - filePtr;
        fsignatures_t siginfo;
        siginfo.fs_file_start = sliceOffset;
        siginfo.fs_blob_start = (void*)(long)(codeSignatureCommand->dataoff);
        siginfo.fs_blob_size  = codeSignatureCommand->datasize;
        int addFileSigsReault = fcntl(fd, F_ADDFILESIGS_RETURN, &siginfo);
        if ( addFileSigsReault == -1 ) {
            ans = false;
            return;
        }
        
        fchecklv_t checkInfo;
        char     messageBuffer[512];
        messageBuffer[0]                = '\0';
        checkInfo.lv_error_message_size = sizeof(messageBuffer);
        checkInfo.lv_error_message      = messageBuffer;
        checkInfo.lv_file_start= sliceOffset;
        int checkLVresult = fcntl(fd, F_CHECK_LV, &checkInfo);
        
        if (checkLVresult == 0) {
            ans = true;
            return;
        } else {
            ans = false;
            return;
        }
    });
    return ans;
}

NSString* getLCEntitlementXML(void) {
    __block NSString* ans = @"Failed to find main executable?";
    // it seems the debug build messes the code signature region up, so we search the executable file on the disk instead.
    LCParseMachO(NSBundle.mainBundle.executablePath.UTF8String, true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
        ans = getEntitlementXML(header, 0);
    });
    return ans;
}
