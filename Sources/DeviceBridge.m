// Local command-line adapter for the MobileDevice framework supplied with macOS.
// No device restore, uninstall, re-signing or credential APIs are exposed.
#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef const void *DeviceRef;
typedef struct { DeviceRef device; unsigned int message; } DeviceNotice;
typedef void (*NoticeCallback)(DeviceNotice *, void *);
typedef int (*ProgressCallback)(CFDictionaryRef, void *);

static void *mobile;
static int (*subscribeDevices)(NoticeCallback, unsigned int, unsigned int, void *, void **);
static int (*unsubscribeDevices)(void *);
static int (*connectDevice)(DeviceRef), (*disconnectDevice)(DeviceRef);
static int (*isPaired)(DeviceRef), (*pairDevice)(DeviceRef);
static int (*validatePairing)(DeviceRef), (*startSession)(DeviceRef), (*stopSession)(DeviceRef);
static int (*interfaceType)(DeviceRef);
static CFStringRef (*copyIdentifier)(DeviceRef);
static CFTypeRef (*copyValue)(DeviceRef, CFStringRef, CFStringRef);
static int (*lookupApplications)(DeviceRef, CFDictionaryRef, CFDictionaryRef *);
static int (*transferPackage)(int, DeviceRef, CFURLRef, CFDictionaryRef, ProgressCallback, void *);
static int (*installPackage)(int, DeviceRef, CFURLRef, CFDictionaryRef, ProgressCallback, void *);
static const char *(*errorString)(int);
static NSMutableDictionary<NSString *, NSValue *> *foundDevices;

// The stable libarchive ABI is part of macOS. Declare only the functions used here.
struct archive; struct archive_entry;
extern struct archive *archive_read_new(void);
extern int archive_read_support_format_zip(struct archive *);
extern int archive_read_open_filename(struct archive *, const char *, size_t);
extern int archive_read_next_header(struct archive *, struct archive_entry **);
extern const char *archive_entry_pathname(struct archive_entry *);
extern int64_t archive_entry_size(struct archive_entry *);
extern ssize_t archive_read_data(struct archive *, void *, size_t);
extern int archive_read_data_skip(struct archive *);
extern int archive_read_free(struct archive *);

static void emit(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
    if (!data) data = [@"{\"ok\":false,\"error\":\"Ошибка формирования ответа\"}" dataUsingEncoding:NSUTF8StringEncoding];
    fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); fflush(stdout);
}

static NSString *deviceError(NSString *action, int code) {
    const char *description = errorString ? errorString(code) : NULL;
    return [NSString stringWithFormat:@"%@: %@ (0x%08x). Разблокируй iPhone и проверь доверие этому Mac.",
            action, description ? @(description) : @"ошибка iOS", (unsigned int)code];
}

static BOOL loadMobile(NSString **error) {
    mobile = dlopen("/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_NOW | RTLD_LOCAL);
    if (!mobile) mobile = dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_NOW | RTLD_LOCAL);
    if (!mobile) { *error = @"MobileDevice.framework не найден. Обнови macOS и поддержку подключённых iPhone через Finder."; return NO; }
#define LOAD(symbol, variable) do { *(void **)(&variable) = dlsym(mobile, symbol); if (!variable) { *error = @"В этой версии macOS отсутствует " @symbol; return NO; } } while (0)
    LOAD("AMDeviceNotificationSubscribe", subscribeDevices);
    LOAD("AMDeviceNotificationUnsubscribe", unsubscribeDevices);
    LOAD("AMDeviceConnect", connectDevice); LOAD("AMDeviceDisconnect", disconnectDevice);
    LOAD("AMDeviceIsPaired", isPaired); LOAD("AMDevicePair", pairDevice);
    LOAD("AMDeviceValidatePairing", validatePairing);
    LOAD("AMDeviceStartSession", startSession); LOAD("AMDeviceStopSession", stopSession);
    LOAD("AMDeviceGetInterfaceType", interfaceType);
    LOAD("AMDeviceCopyDeviceIdentifier", copyIdentifier); LOAD("AMDeviceCopyValue", copyValue);
    LOAD("AMDeviceLookupApplications", lookupApplications);
    LOAD("AMDeviceSecureTransferPath", transferPackage);
    LOAD("AMDeviceSecureInstallApplication", installPackage);
    *(void **)(&errorString) = dlsym(mobile, "AMDErrorString");
#undef LOAD
    return YES;
}

static NSString *identifier(DeviceRef device) { return CFBridgingRelease(copyIdentifier(device)) ?: @""; }
static id value(DeviceRef device, NSString *key) { return CFBridgingRelease(copyValue(device, NULL, (__bridge CFStringRef)key)); }
static NSString *stringValue(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return @"";
}

static void deviceNotice(DeviceNotice *notice, void *context) {
    if (notice->message == 1 && interfaceType(notice->device) == 1) {
        NSString *key = identifier(notice->device);
        if (key.length && !foundDevices[key]) {
            CFRetain(notice->device);
            foundDevices[key] = [NSValue valueWithPointer:notice->device];
        }
    } else if (notice->message == 2) {
        NSString *key = identifier(notice->device);
        NSValue *previous = foundDevices[key];
        if (previous) { CFRelease(previous.pointerValue); [foundDevices removeObjectForKey:key]; }
    }
}

static NSDictionary *describeDevice(DeviceRef device) {
    int code = connectDevice(device);
    if (code) return @{ @"id": identifier(device), @"name": @"iPhone", @"productType": @"", @"iosVersion": @"", @"trusted": @NO, @"error": deviceError(@"Подключение", code) };
    NSString *name = stringValue(value(device, @"DeviceName"));
    NSString *type = stringValue(value(device, @"ProductType"));
    NSString *version = stringValue(value(device, @"ProductVersion"));
    BOOL trusted = isPaired(device) && validatePairing(device) == 0;
    disconnectDevice(device);
    return @{ @"id": identifier(device), @"name": name.length ? name : @"iPhone", @"productType": type, @"iosVersion": version, @"trusted": @(trusted) };
}

static BOOL openSession(DeviceRef device, BOOL requestPair, NSString **error) {
    int code = connectDevice(device);
    if (code) { *error = deviceError(@"Подключение", code); return NO; }
    if (!isPaired(device)) {
        if (requestPair) code = pairDevice(device);
        else code = -1;
        if (code || !isPaired(device)) {
            *error = @"Разблокируй iPhone, нажми «Доверять» на его экране и повтори действие. Если запрос не появился, выбери iPhone в Finder.";
            disconnectDevice(device); return NO;
        }
    }
    code = validatePairing(device);
    if (!code) code = startSession(device);
    if (code) { *error = deviceError(@"Открытие сессии", code); disconnectDevice(device); return NO; }
    return YES;
}

static NSDictionary *getApplications(DeviceRef device, NSString **error) {
    CFDictionaryRef result = NULL;
    NSDictionary *options = @{ @"ApplicationType": @"User", @"ReturnAttributes": @[
        @"CFBundleIdentifier", @"CFBundleDisplayName", @"CFBundleName", @"CFBundleShortVersionString",
        @"CFBundleVersion", @"ApplicationType", @"iTunesMetadata", @"iTunesStoreItemIdentifier",
        @"MinimumOSVersion", @"IsPlaceholder", @"UIDeviceFamily"
    ] };
    int code = lookupApplications(device, (__bridge CFDictionaryRef)options, &result);
    if (code) { if (result) CFRelease(result); *error = deviceError(@"Чтение приложений", code); return nil; }
    id applications = CFBridgingRelease(result);
    if (![applications isKindOfClass:NSDictionary.class]) { *error = @"iPhone вернул некорректный список приложений."; return nil; }
    return applications;
}

static NSDictionary *dictionaryMetadata(id metadata) {
    if ([metadata isKindOfClass:NSDictionary.class]) return metadata;
    if ([metadata isKindOfClass:NSData.class]) {
        id plist = [NSPropertyListSerialization propertyListWithData:metadata options:NSPropertyListImmutable format:NULL error:nil];
        if ([plist isKindOfClass:NSDictionary.class]) return plist;
    }
    return @{};
}

static NSDictionary *normalizeApp(NSDictionary *app, NSString *bundleKey) {
    NSDictionary *metadata = dictionaryMetadata(app[@"iTunesMetadata"]);
    NSString *bundle = stringValue(app[@"CFBundleIdentifier"]); if (!bundle.length) bundle = bundleKey;
    NSString *name = stringValue(app[@"CFBundleDisplayName"]);
    if (!name.length) name = stringValue(app[@"CFBundleName"]);
    if (!name.length) name = stringValue(metadata[@"itemName"]);
    if (!name.length) name = bundle;
    NSString *storeID = stringValue(metadata[@"itemId"]);
    if (!storeID.length) storeID = stringValue(app[@"iTunesStoreItemIdentifier"]);
    if ([storeID rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound || [storeID longLongValue] <= 0) storeID = @"";
    NSString *version = stringValue(app[@"CFBundleShortVersionString"]);
    if (!version.length) version = stringValue(app[@"CFBundleVersion"]);
    return @{ @"bundleID": bundle ?: @"", @"name": name ?: @"", @"version": version,
              @"storeID": storeID, @"minimumOS": stringValue(app[@"MinimumOSVersion"]),
              @"placeholder": @([app[@"IsPlaceholder"] boolValue]) };
}

static NSDictionary *inspectIPA(NSString *path, NSString **error) {
    BOOL isDirectory = NO;
    if (![[path.pathExtension lowercaseString] isEqual:@"ipa"] || ![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
        *error = @"Выбери существующий установочный файл с расширением .ipa."; return nil;
    }
    struct archive *reader = archive_read_new();
    archive_read_support_format_zip(reader);
    if (archive_read_open_filename(reader, path.fileSystemRepresentation, 10240) != 0) {
        archive_read_free(reader); *error = @"Не удалось открыть IPA: файл повреждён или не является ZIP-архивом."; return nil;
    }
    NSMutableArray *manifests = [NSMutableArray array];
    NSDictionary *metadata = @{};
    struct archive_entry *entry = NULL;
    int status = 0, count = 0;
    while ((status = archive_read_next_header(reader, &entry)) == 0) {
        if (++count > 200000) { *error = @"Слишком много записей в IPA."; break; }
        const char *rawName = archive_entry_pathname(entry);
        NSString *name = rawName ? [NSString stringWithUTF8String:rawName] : nil;
        NSArray *parts = name.pathComponents;
        BOOL isManifest = parts.count == 3 && [parts[0] isEqual:@"Payload"] && [parts[1] hasSuffix:@".app"] && [parts[2] isEqual:@"Info.plist"];
        BOOL isMetadata = [name isEqual:@"iTunesMetadata.plist"];
        if (isManifest || isMetadata) {
            int64_t length = archive_entry_size(entry);
            if (length <= 0 || length > 2 * 1024 * 1024) { *error = @"Некорректный размер метаданных IPA."; break; }
            NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)length];
            size_t total = 0;
            while (total < (size_t)length) {
                ssize_t bytes = archive_read_data(reader, (char *)data.mutableBytes + total, (size_t)length - total);
                if (bytes <= 0) break;
                total += (size_t)bytes;
            }
            if (total != (size_t)length) { *error = @"IPA содержит повреждённые метаданные."; break; }
            id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
            if (![plist isKindOfClass:NSDictionary.class]) { *error = @"Не удалось прочитать Info.plist из IPA."; break; }
            if (isManifest) [manifests addObject:plist]; else metadata = plist;
        } else if (archive_read_data_skip(reader) < 0) {
            *error = @"Не удалось прочитать структуру IPA."; break;
        }
    }
    archive_read_free(reader);
    if (*error) return nil;
    if (status != 1 || manifests.count != 1) { *error = @"В IPA должен быть ровно один основной пакет Payload/*.app/Info.plist."; return nil; }
    NSMutableDictionary *manifest = [manifests.firstObject mutableCopy];
    NSString *bundle = stringValue(manifest[@"CFBundleIdentifier"]);
    if (!bundle.length || [bundle rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"].invertedSet].location != NSNotFound) {
        *error = @"В IPA отсутствует корректный идентификатор приложения."; return nil;
    }
    NSArray *family = manifest[@"UIDeviceFamily"];
    if ([family isKindOfClass:NSArray.class] && ![family containsObject:@1]) { *error = @"Это приложение не предназначено для iPhone."; return nil; }
    manifest[@"iTunesMetadata"] = metadata;
    return normalizeApp(manifest, bundle);
}

static int progress(CFDictionaryRef details, void *context) {
    NSDictionary *dict = (__bridge NSDictionary *)details;
    NSString *status = stringValue(dict[@"Status"]);
    if (dict[@"Error"]) fprintf(stderr, "iOS: %s\n", [stringValue(dict[@"Error"]) UTF8String]);
    emit(@{ @"event": @"progress", @"status": status, @"percent": dict[@"PercentComplete"] ?: @0 });
    return 0;
}

static NSDictionary *perform(NSArray<NSString *> *args) {
    NSString *command = args.count > 1 ? args[1] : @"";
    NSString *error = nil;
    if ([command isEqual:@"ipa-info"] && args.count == 3) {
        NSDictionary *app = inspectIPA(args[2], &error);
        return app ? @{ @"ok": @YES, @"app": app } : @{ @"ok": @NO, @"error": error ?: @"Некорректный IPA." };
    }
    if (![@[@"devices", @"apps", @"pair", @"install"] containsObject:command]) return @{ @"ok": @NO, @"error": @"Неизвестная команда." };
    if (![command isEqual:@"devices"] && args.count < 3) return @{ @"ok": @NO, @"error": @"Не выбран iPhone." };
    if ([command isEqual:@"install"] && args.count != 6) return @{ @"ok": @NO, @"error": @"Нужны устройство, IPA, идентификатор приложения и исходный iPhone." };
    // Reject a source/target mix-up before loading frameworks or touching a device.
    if ([command isEqual:@"install"] && args[5].length && [args[2] isEqual:args[5]]) return @{ @"ok": @NO, @"error": @"Исходный и новый iPhone совпадают. Выбери другой телефон для установки." };
    if (!loadMobile(&error)) return @{ @"ok": @NO, @"error": error };
    foundDevices = [NSMutableDictionary dictionary];
    void *subscription = NULL;
    int code = subscribeDevices(deviceNotice, 0, 0, NULL, &subscription);
    if (code) return @{ @"ok": @NO, @"error": deviceError(@"Поиск iPhone", code) };
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.5];
    while (deadline.timeIntervalSinceNow > 0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
    NSDictionary *response = nil;
    if ([command isEqual:@"devices"]) {
        NSMutableArray *devices = [NSMutableArray array];
        for (NSString *key in [[foundDevices allKeys] sortedArrayUsingSelector:@selector(compare:)]) [devices addObject:describeDevice(foundDevices[key].pointerValue)];
        response = @{ @"ok": @YES, @"devices": devices };
    } else {
        DeviceRef device = foundDevices[args[2]].pointerValue;
        if (!device) response = @{ @"ok": @NO, @"error": @"Выбранный iPhone не подключён по USB. Подключи его кабелем и разблокируй." };
        else if ([command isEqual:@"install"]) {
            NSDictionary *app = inspectIPA(args[3], &error);
            if (app && ![app[@"bundleID"] isEqual:args[4]]) error = @"Этот IPA относится к другому приложению. Установка отменена.";
            if (!error && openSession(device, NO, &error)) {
                NSString *os = stringValue(value(device, @"ProductVersion"));
                if ([app[@"minimumOS"] length] && [os compare:app[@"minimumOS"] options:NSNumericSearch] == NSOrderedAscending) error = @"Для этого IPA нужна более новая версия iOS.";
                NSDictionary *installed = error ? nil : getApplications(device, &error);
                NSDictionary *existing = installed[app[@"bundleID"]];
                BOOL alreadyInstalled = existing && ![existing[@"IsPlaceholder"] boolValue];
                stopSession(device); disconnectDevice(device);
                if (!error && alreadyInstalled) response = @{ @"ok": @YES, @"alreadyInstalled": @YES, @"bundleID": app[@"bundleID"] };
                else if (!error) {
                    NSURL *url = [NSURL fileURLWithPath:args[3]];
                    // Empty options preserve the IPA's original distribution type and signature.
                    NSDictionary *options = @{};
                    code = transferPackage(0, device, (__bridge CFURLRef)url, (__bridge CFDictionaryRef)options, progress, NULL);
                    if (code) error = deviceError(@"Передача IPA", code);
                    if (!error && openSession(device, NO, &error)) {
                        code = installPackage(0, device, (__bridge CFURLRef)url, (__bridge CFDictionaryRef)options, progress, NULL);
                        if (code) error = deviceError(@"Установка: проверь совместимость IPA и Apple ID", code);
                        if (!error) {
                            NSDictionary *verified = getApplications(device, &error);
                            NSDictionary *record = verified[app[@"bundleID"]];
                            if (!record || [record[@"IsPlaceholder"] boolValue]) error = @"iOS завершила установку, но приложение не найдено. Проверь экран iPhone.";
                        }
                        stopSession(device); disconnectDevice(device);
                    }
                    if (!error) response = @{ @"ok": @YES, @"alreadyInstalled": @NO, @"bundleID": app[@"bundleID"] };
                }
            }
        } else if (openSession(device, [command isEqual:@"pair"] || [command isEqual:@"apps"], &error)) {
            if ([command isEqual:@"pair"]) response = @{ @"ok": @YES };
            else {
                NSDictionary *applications = getApplications(device, &error);
                if (applications) {
                    NSMutableArray *apps = [NSMutableArray array];
                    for (NSString *bundle in applications) {
                        NSDictionary *record = applications[bundle];
                        if ([record isKindOfClass:NSDictionary.class]) [apps addObject:normalizeApp(record, bundle)];
                    }
                    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
                    response = @{ @"ok": @YES, @"apps": apps };
                }
            }
            stopSession(device); disconnectDevice(device);
        }
    }
    unsubscribeDevices(subscription);
    for (NSValue *device in foundDevices.allValues) CFRelease(device.pointerValue);
    return response ?: @{ @"ok": @NO, @"error": error ?: @"Операция не завершена." };
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSDictionary *result = perform(NSProcessInfo.processInfo.arguments);
        emit(result); return [result[@"ok"] boolValue] ? 0 : 1;
    }
}
