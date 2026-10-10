#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#define __USE_MINGW_ANSI_STDIO 1
#define COBJMACROS
#include <windows.h>
#include <mmsystem.h>
#include <wincodec.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

/* Paint before starting Godot: device/autoload work occurs under the native
 * animation. WIC ships with Windows; no external player/runtime is needed.
 * Each launch has its own handshake folder and child; there is no mutex. */
#define PACK_NAME L"native-startup.frames"
#define WINDOW_CLASS L"GriddyTranslateEarlySplash"
#define EXIT_MS 450
#define LOGO_FRAME 33
#define FIRST_FRAME 10
#define FRAME_CACHE_SIZE 4
#define FRAME_DECODED (WM_APP+1)
#define CHILD_CREATED (WM_APP+2)

typedef struct {
    wchar_t *command;
    const wchar_t *folder;
    PROCESS_INFORMATION child;
    BOOL succeeded;
    DWORD elapsed_ms;
    HWND window;
} ChildLaunch;

typedef struct {
    BYTE *pixels;
    int frame, state; /* 0: reusable, 1: decoder owns it, 2: ready */
} CachedFrame;
typedef struct {
    CRITICAL_SECTION lock;
    HANDLE wake, stop, thread;
    CachedFrame frames[FRAME_CACHE_SIZE];
    LONG requested, presented, failed, max_decode_us;
    BOOL initialized;
} FrameDecoder;
typedef struct {
    HDC dc;
    HBITMAP bitmap, original;
    BYTE *pixels;
    int width, height, frame;
} PaintSurface;

typedef struct {
    HANDLE file, mapping;
    const BYTE *data;
    DWORD size, width, height, fps_num, fps_den, count;
    const uint32_t *offsets;
    IWICImagingFactory *factory;
    BYTE *pixels;
    BITMAPINFO bitmap;
    int decoded_frame;
} FramePack;
typedef struct {
    FramePack pack;
    FrameDecoder decoder;
    PaintSurface surface, exit_surface;
    PROCESS_INFORMATION child;
    HWND window, child_window;
    ULONGLONG entered, shown, full_logo, ready, exit_started, finished, heartbeat_tick;
    DWORD rejected_inputs, exit_inputs, accepted_frame;
    BOOL ready_seen, skip_requested, done, auto_skip, native_test, runtime_covered, first_window_visible, topmost;
    BOOL test_early_sent, test_valid_sent, test_exit_sent, exit_capture_saved;
    BOOL borderless, decorated_child_seen, performance_only;
    RECT last_child_rect;
    DWORD paints, frame_changes, layout_changes, max_paint_us, max_frame_gap_ms, max_follow_us, launch_ms;
    ULONGLONG last_frame_tick;
    BYTE opacity;
    wchar_t handshake[32768], profile[32768];
} Splash;
static Splash splash;
static LARGE_INTEGER clock_frequency;

static DWORD elapsed_us(LARGE_INTEGER start) {
    LARGE_INTEGER end;QueryPerformanceCounter(&end);
    return (DWORD)((end.QuadPart-start.QuadPart)*1000000/clock_frequency.QuadPart);
}

static ULONGLONG unix_ms(void) {
    FILETIME ft; ULARGE_INTEGER value;
    GetSystemTimeAsFileTime(&ft);
    value.LowPart=ft.dwLowDateTime; value.HighPart=ft.dwHighDateTime;
    return (value.QuadPart-116444736000000000ULL)/10000ULL;
}
static void path_join(wchar_t *target, size_t capacity, const wchar_t *folder, const wchar_t *leaf) {
    _snwprintf(target,capacity,L"%ls\\%ls",folder,leaf); target[capacity-1]=0;
}
static BOOL argument_present(const wchar_t *arguments, const wchar_t *option) {
    size_t length=wcslen(option); const wchar_t *cursor=arguments;
    while ((cursor=wcsstr(cursor,option))!=NULL) {
        BOOL start=cursor==arguments||cursor[-1]==L' '||cursor[-1]==L'\t'||cursor[-1]==L'"';
        wchar_t next=cursor[length];
        if(start&&(next==0||next==L' '||next==L'\t'||next==L'"'||next==L'='))return TRUE;
        cursor+=length;
    } return FALSE;
}
static BOOL preference_enabled(const wchar_t *property, BOOL fallback) {
    wchar_t roaming[32768],path[32768],value[32];
    if(!GetEnvironmentVariableW(L"APPDATA",roaming,32768))return fallback;
    path_join(path,32768,roaming,L"Godot\\app_userdata\\GriddyTranslate\\translator.cfg");
    GetPrivateProfileStringW(L"visual",property,fallback?L"true":L"false",value,32,path);
    return _wcsicmp(value,L"false")!=0&&wcscmp(value,L"0")!=0;
}
static void save_profile(void) {
    if(!splash.profile[0])return;
    HANDLE log=CreateFileW(splash.profile,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if(log==INVALID_HANDLE_VALUE)return;
    char text[1600];
    int length=snprintf(text,sizeof(text),
        "{\"launcher_pid\":%lu,\"runtime_pid\":%lu,\"first_paint_ms\":%llu,"
        "\"logo_complete_ms\":%llu,\"ready_ms\":%llu,\"exit_start_ms\":%llu,"
        "\"exit_end_ms\":%llu,\"skip_requested\":%s,\"rejected_inputs\":%lu,\"exit_inputs\":%lu,"
        "\"first_frame_index\":%u,\"accepted_frame_index\":%lu,\"frame_count\":%lu,\"width\":%lu,\"height\":%lu,"
        "\"first_window_visible\":%s,\"runtime_covered\":%s,\"borderless\":%s,\"decorated_child_seen\":%s,"
        "\"paints\":%lu,\"frame_changes\":%lu,\"layout_changes\":%lu,"
        "\"max_paint_us\":%lu,\"max_decode_us\":%ld,\"max_frame_gap_ms\":%lu,\"max_follow_us\":%lu,\"child_launch_ms\":%lu}\n",
        (unsigned long)GetCurrentProcessId(),(unsigned long)splash.child.dwProcessId,
        (unsigned long long)(splash.shown?splash.shown-splash.entered:0),
        (unsigned long long)(splash.full_logo?splash.full_logo-splash.entered:0),
        (unsigned long long)(splash.ready?splash.ready-splash.entered:0),
        (unsigned long long)(splash.exit_started?splash.exit_started-splash.entered:0),
        (unsigned long long)(splash.finished?splash.finished-splash.entered:0),
        splash.skip_requested?"true":"false",(unsigned long)splash.rejected_inputs,(unsigned long)splash.exit_inputs,
        FIRST_FRAME,(unsigned long)splash.accepted_frame,(unsigned long)splash.pack.count,(unsigned long)splash.pack.width,(unsigned long)splash.pack.height,
        splash.first_window_visible?"true":"false",splash.runtime_covered?"true":"false",splash.borderless?"true":"false",splash.decorated_child_seen?"true":"false",
        (unsigned long)splash.paints,(unsigned long)splash.frame_changes,(unsigned long)splash.layout_changes,
        (unsigned long)splash.max_paint_us,(long)InterlockedCompareExchange(&splash.decoder.max_decode_us,0,0),(unsigned long)splash.max_frame_gap_ms,(unsigned long)splash.max_follow_us,(unsigned long)splash.launch_ms);
    DWORD written;
    if(length>0){WriteFile(log,text,(DWORD)length,&written,NULL);FlushFileBuffers(log);}CloseHandle(log);
}
static void marker(const wchar_t *name,const char *content) {
    if(!splash.handshake[0])return;
    wchar_t path[32768];path_join(path,32768,splash.handshake,name);
    HANDLE file=CreateFileW(path,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if(file==INVALID_HANDLE_VALUE)return;
    DWORD written;WriteFile(file,content,(DWORD)strlen(content),&written,NULL);CloseHandle(file);
}
static BOOL marker_exists(const wchar_t *name) {
    wchar_t path[32768];path_join(path,32768,splash.handshake,name);
    return GetFileAttributesW(path)!=INVALID_FILE_ATTRIBUTES;
}
static void cleanup_handshake(void) {
    if(!splash.handshake[0])return;
    const wchar_t *names[]={L"shown",L"logo",L"ready",L"skip",L"exiting",L"done",L"cancel",L"heartbeat"};
    wchar_t path[32768];
    for(size_t index=0;index<sizeof(names)/sizeof(names[0]);++index) {
        path_join(path,32768,splash.handshake,names[index]);DeleteFileW(path);
    }
    RemoveDirectoryW(splash.handshake);
}
static void write_heartbeat(void) {
    char value[64];
    snprintf(value,sizeof(value),"%llu",(unsigned long long)unix_ms());
    marker(L"heartbeat",value);
    splash.heartbeat_tick=GetTickCount64();
}
static void release_pack(FramePack *pack) {
    if(pack->factory)IWICImagingFactory_Release(pack->factory);
    if(pack->pixels)HeapFree(GetProcessHeap(),0,pack->pixels);
    if(pack->data)UnmapViewOfFile(pack->data);
    if(pack->mapping)CloseHandle(pack->mapping);
    if(pack->file&&pack->file!=INVALID_HANDLE_VALUE)CloseHandle(pack->file);
    ZeroMemory(pack,sizeof(*pack));
}
static BOOL decode_frame(FramePack *pack,DWORD index) {
    if((int)index==pack->decoded_frame)return TRUE;
    if(index>=pack->count)return FALSE;
    DWORD begin=pack->offsets[index],end=pack->offsets[index+1];
    if(begin>=end||end>pack->size)return FALSE;
    IWICStream *stream=NULL;IWICBitmapDecoder *decoder=NULL;
    IWICBitmapFrameDecode *frame=NULL;IWICFormatConverter *converter=NULL;
    HRESULT result=IWICImagingFactory_CreateStream(pack->factory,&stream);
    if(SUCCEEDED(result))result=IWICStream_InitializeFromMemory(stream,(BYTE*)pack->data+begin,end-begin);
    if(SUCCEEDED(result))result=IWICImagingFactory_CreateDecoderFromStream(pack->factory,(IStream*)stream,NULL,WICDecodeMetadataCacheOnDemand,&decoder);
    if(SUCCEEDED(result))result=IWICBitmapDecoder_GetFrame(decoder,0,&frame);
    UINT width=0,height=0;
    if(SUCCEEDED(result))result=IWICBitmapFrameDecode_GetSize(frame,&width,&height);
    if(width!=pack->width||height!=pack->height)result=E_INVALIDARG;
    if(SUCCEEDED(result))result=IWICImagingFactory_CreateFormatConverter(pack->factory,&converter);
    if(SUCCEEDED(result))result=IWICFormatConverter_Initialize(converter,(IWICBitmapSource*)frame,&GUID_WICPixelFormat32bppBGR,WICBitmapDitherTypeNone,NULL,0,WICBitmapPaletteTypeCustom);
    if(SUCCEEDED(result))result=IWICFormatConverter_CopyPixels(converter,NULL,pack->width*4,pack->width*pack->height*4,pack->pixels);
    if(converter)IWICFormatConverter_Release(converter);
    if(frame)IWICBitmapFrameDecode_Release(frame);
    if(decoder)IWICBitmapDecoder_Release(decoder);
    if(stream)IWICStream_Release(stream);
    if(SUCCEEDED(result))pack->decoded_frame=(int)index;
    return SUCCEEDED(result);
}
static BOOL load_pack(FramePack *pack,const wchar_t *folder) {
    wchar_t path[32768];path_join(path,32768,folder,PACK_NAME);pack->decoded_frame=-1;
    pack->file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
    if(pack->file==INVALID_HANDLE_VALUE)return FALSE;
    LARGE_INTEGER size;
    if(!GetFileSizeEx(pack->file,&size)||size.QuadPart<32||size.QuadPart>512*1024*1024)return FALSE;
    pack->size=(DWORD)size.QuadPart;
    pack->mapping=CreateFileMappingW(pack->file,NULL,PAGE_READONLY,0,0,NULL);
    if(!pack->mapping)return FALSE;
    pack->data=MapViewOfFile(pack->mapping,FILE_MAP_READ,0,0,0);
    if(!pack->data||memcmp(pack->data,"CYBRF01\0",8)!=0)return FALSE;
    const uint32_t *header=(const uint32_t*)(pack->data+8);
    pack->width=header[0];pack->height=header[1];pack->fps_num=header[2];pack->fps_den=header[3];pack->count=header[4];
    if(pack->width<640||pack->width>3840||pack->height<360||pack->height>2160||pack->width*9!=pack->height*16||pack->fps_num!=30||pack->fps_den!=1||pack->count<320||pack->count>1000)return FALSE;
    if(28+(pack->count+1)*4>pack->size)return FALSE;
    pack->offsets=(const uint32_t*)(pack->data+28);
    if(pack->offsets[0]<28+(pack->count+1)*4||pack->offsets[pack->count]>pack->size)return FALSE;
    HRESULT result=CoCreateInstance(&CLSID_WICImagingFactory,NULL,CLSCTX_INPROC_SERVER,&IID_IWICImagingFactory,(void**)&pack->factory);
    if(FAILED(result))return FALSE;
    SIZE_T pixels=(SIZE_T)pack->width*pack->height*4;
    pack->pixels=HeapAlloc(GetProcessHeap(),0,pixels);
    if(!pack->pixels)return FALSE;
    pack->bitmap.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);pack->bitmap.bmiHeader.biWidth=pack->width;
    pack->bitmap.bmiHeader.biHeight=-(LONG)pack->height;pack->bitmap.bmiHeader.biPlanes=1;
    pack->bitmap.bmiHeader.biBitCount=32;pack->bitmap.bmiHeader.biCompression=BI_RGB;
    return decode_frame(pack,FIRST_FRAME);
}

/* A bounded WIC queue keeps JPEG decoding off the window/message thread.
 * The UI only swaps a completed buffer; it never waits for a slow decoder. */
static DWORD WINAPI decode_worker(void *unused) {
    (void)unused;FrameDecoder *cache=&splash.decoder;
    FramePack local=splash.pack;local.factory=NULL;
    HRESULT com=CoInitializeEx(NULL,COINIT_MULTITHREADED);
    HRESULT result=FAILED(com)?com:CoCreateInstance(&CLSID_WICImagingFactory,NULL,CLSCTX_INPROC_SERVER,&IID_IWICImagingFactory,(void**)&local.factory);
    if(FAILED(result)){InterlockedExchange(&cache->failed,1);PostMessageW(splash.window,FRAME_DECODED,0,0);if(SUCCEEDED(com))CoUninitialize();return 1;}
    while(WaitForSingleObject(cache->stop,0)!=WAIT_OBJECT_0) {
        int wanted=-1,slot=-1;
        EnterCriticalSection(&cache->lock);
        int requested=cache->requested,presented=cache->presented;
        for(int next=requested;next<requested+FRAME_CACHE_SIZE&&next<(int)local.count;++next) {
            if(next==presented)continue;
            BOOL exists=FALSE;
            for(int i=0;i<FRAME_CACHE_SIZE;++i)if(cache->frames[i].state&&cache->frames[i].frame==next)exists=TRUE;
            if(!exists){wanted=next;break;}
        }
        if(wanted>=0)for(int i=0;i<FRAME_CACHE_SIZE;++i) {
            CachedFrame *frame=&cache->frames[i];
            if(!frame->state||(frame->state==2&&(frame->frame<requested||frame->frame>=requested+FRAME_CACHE_SIZE))) {
                slot=i;frame->frame=wanted;frame->state=1;local.pixels=frame->pixels;break;
            }
        }
        LeaveCriticalSection(&cache->lock);
        if(slot<0){HANDLE events[]={cache->stop,cache->wake};WaitForMultipleObjects(2,events,FALSE,INFINITE);continue;}
        local.decoded_frame=-1;LARGE_INTEGER began;QueryPerformanceCounter(&began);
        BOOL decoded=decode_frame(&local,(DWORD)wanted);
        LONG duration=(LONG)elapsed_us(began);
        if(duration>cache->max_decode_us)InterlockedExchange(&cache->max_decode_us,duration);
        EnterCriticalSection(&cache->lock);
        cache->frames[slot].state=decoded?2:0;
        if(!decoded)cache->failed=1;
        BOOL current=wanted==cache->requested;
        LeaveCriticalSection(&cache->lock);
        if(current||!decoded)PostMessageW(splash.window,FRAME_DECODED,0,0);
        if(!decoded)break;
    }
    IWICImagingFactory_Release(local.factory);CoUninitialize();return 0;
}
static void stop_decoder(void) {
    FrameDecoder *cache=&splash.decoder;
    if(!cache->initialized)return;
    if(cache->stop)SetEvent(cache->stop);
    if(cache->thread){WaitForSingleObject(cache->thread,INFINITE);CloseHandle(cache->thread);}
    for(int i=0;i<FRAME_CACHE_SIZE;++i)if(cache->frames[i].pixels)HeapFree(GetProcessHeap(),0,cache->frames[i].pixels);
    if(cache->stop)CloseHandle(cache->stop);
    if(cache->wake)CloseHandle(cache->wake);
    DeleteCriticalSection(&cache->lock);cache->initialized=FALSE;
}
static BOOL start_decoder(void) {
    FrameDecoder *cache=&splash.decoder;
    InitializeCriticalSection(&cache->lock);cache->initialized=TRUE;
    cache->requested=cache->presented=(LONG)FIRST_FRAME;
    cache->stop=CreateEventW(NULL,TRUE,FALSE,NULL);cache->wake=CreateEventW(NULL,FALSE,FALSE,NULL);
    if(!cache->stop||!cache->wake){stop_decoder();return FALSE;}
    for(int i=0;i<FRAME_CACHE_SIZE;++i) {
        cache->frames[i].pixels=HeapAlloc(GetProcessHeap(),0,(SIZE_T)splash.pack.width*splash.pack.height*4);
        if(!cache->frames[i].pixels){stop_decoder();return FALSE;}
    }
    cache->thread=CreateThread(NULL,0,decode_worker,NULL,0,NULL);
    if(!cache->thread){stop_decoder();return FALSE;}
    return TRUE;
}
static BOOL present_frame(DWORD index) {
    FrameDecoder *cache=&splash.decoder;
    if(!cache->initialized) {
        /* A machine that cannot allocate the small queue still runs normally. */
        return decode_frame(&splash.pack,index);
    }
    EnterCriticalSection(&cache->lock);
    BOOL changed=cache->requested!=(LONG)index;cache->requested=(LONG)index;
    if((int)index!=splash.pack.decoded_frame)for(int i=0;i<FRAME_CACHE_SIZE;++i) {
        CachedFrame *frame=&cache->frames[i];
        if(frame->state==2&&frame->frame==(int)index) {
            BYTE *old=splash.pack.pixels;splash.pack.pixels=frame->pixels;frame->pixels=old;
            splash.pack.decoded_frame=(int)index;cache->presented=(LONG)index;frame->state=0;changed=TRUE;break;
        }
    }
    BOOL healthy=!cache->failed;LeaveCriticalSection(&cache->lock);
    if(changed)SetEvent(cache->wake);
    return healthy;
}
static void release_surface(PaintSurface *surface) {
    if(surface->dc&&surface->original)SelectObject(surface->dc,surface->original);
    if(surface->bitmap)DeleteObject(surface->bitmap);
    if(surface->dc)DeleteDC(surface->dc);
    ZeroMemory(surface,sizeof(*surface));surface->frame=-1;
}
static BOOL resize_surface(PaintSurface *surface,HDC screen,int width,int height) {
    if(surface->dc&&surface->width==width&&surface->height==height)return TRUE;
    release_surface(surface);BITMAPINFO bitmap={0};bitmap.bmiHeader=splash.pack.bitmap.bmiHeader;
    bitmap.bmiHeader.biWidth=width;bitmap.bmiHeader.biHeight=-height;
    surface->dc=CreateCompatibleDC(screen);
    surface->bitmap=CreateDIBSection(screen,&bitmap,DIB_RGB_COLORS,(void**)&surface->pixels,NULL,0);
    if(!surface->dc||!surface->bitmap){release_surface(surface);return FALSE;}
    surface->original=SelectObject(surface->dc,surface->bitmap);surface->width=width;surface->height=height;return TRUE;
}
static BOOL make_handshake(void) {
    wchar_t temporary[MAX_PATH],path[MAX_PATH];
    if(!GetTempPathW(MAX_PATH,temporary)||!GetTempFileNameW(temporary,L"GTS",0,path))return FALSE;
    DeleteFileW(path);if(!CreateDirectoryW(path,NULL))return FALSE;wcscpy(splash.handshake,path);
    SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_DIR",splash.handshake);
    SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_ACTIVE",L"1");
    wchar_t value[64];_snwprintf(value,64,L"%I64u",(unsigned long long)unix_ms());
    SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_START_MS",value);
    write_heartbeat();return TRUE;
}
static void capture_frame_png(const wchar_t *name, const BYTE *pixels, DWORD width, DWORD height) {
    if(!splash.native_test||splash.performance_only)return;
    GdiFlush(); /* Only screenshot readback needs to synchronize the DIB. */
    wchar_t folder[32768],path[32768];
    if(!GetEnvironmentVariableW(L"GRIDDY_TEST_OUTPUT",folder,32768))return;
    path_join(path,32768,folder,name);
    IWICStream *stream=NULL;IWICBitmapEncoder *encoder=NULL;IWICBitmapFrameEncode *frame=NULL;
    IPropertyBag2 *properties=NULL;BYTE *bgr=NULL;
    HRESULT result=IWICImagingFactory_CreateStream(splash.pack.factory,&stream);
    if(SUCCEEDED(result))result=IWICStream_InitializeFromFilename(stream,path,GENERIC_WRITE);
    if(SUCCEEDED(result))result=IWICImagingFactory_CreateEncoder(splash.pack.factory,&GUID_ContainerFormatPng,NULL,&encoder);
    if(SUCCEEDED(result))result=IWICBitmapEncoder_Initialize(encoder,(IStream*)stream,WICBitmapEncoderNoCache);
    if(SUCCEEDED(result))result=IWICBitmapEncoder_CreateNewFrame(encoder,&frame,&properties);
    if(SUCCEEDED(result))result=IWICBitmapFrameEncode_Initialize(frame,properties);
    if(SUCCEEDED(result))result=IWICBitmapFrameEncode_SetSize(frame,width,height);
    WICPixelFormatGUID format=GUID_WICPixelFormat24bppBGR;
    if(SUCCEEDED(result))result=IWICBitmapFrameEncode_SetPixelFormat(frame,&format);
    if(SUCCEEDED(result)&&memcmp(&format,&GUID_WICPixelFormat24bppBGR,sizeof(format))!=0)result=E_FAIL;
    DWORD count=width*height;
    if(SUCCEEDED(result)) {
        bgr=HeapAlloc(GetProcessHeap(),0,(SIZE_T)count*3);
        if(!bgr)result=E_OUTOFMEMORY;
    }
    if(SUCCEEDED(result)) {
        for(DWORD pixel=0;pixel<count;++pixel){bgr[pixel*3]=pixels[pixel*4];bgr[pixel*3+1]=pixels[pixel*4+1];bgr[pixel*3+2]=pixels[pixel*4+2];}
        result=IWICBitmapFrameEncode_WritePixels(frame,height,width*3,count*3,bgr);
    }
    if(SUCCEEDED(result))result=IWICBitmapFrameEncode_Commit(frame);
    if(SUCCEEDED(result))IWICBitmapEncoder_Commit(encoder);
    if(bgr)HeapFree(GetProcessHeap(),0,bgr);
    if(properties)IPropertyBag2_Release(properties);
    if(frame)IWICBitmapFrameEncode_Release(frame);
    if(encoder)IWICBitmapEncoder_Release(encoder);
    if(stream)IWICStream_Release(stream);
}
static BOOL CALLBACK find_child_window(HWND window,LPARAM parameter) {
    DWORD process_id;GetWindowThreadProcessId(window,&process_id);
    if(process_id==(DWORD)parameter&&IsWindowVisible(window)&&GetWindow(window,GW_OWNER)==NULL) {
        RECT client;GetClientRect(window,&client);
        if(client.right>100&&client.bottom>100){splash.child_window=window;return FALSE;}
    }return TRUE;
}
static void follow_child_window(void) {
    if(!splash.child.dwProcessId)return;
    if(!splash.child_window)EnumWindows(find_child_window,(LPARAM)splash.child.dwProcessId);
    if(!splash.child_window||!IsWindow(splash.child_window)||IsIconic(splash.child_window))return;
    if(splash.borderless&&(GetWindowLongPtrW(splash.child_window,GWL_STYLE)&WS_CAPTION)==WS_CAPTION)splash.decorated_child_seen=TRUE;
    HWND foreground=GetForegroundWindow();
    /* Cross-process ownership joins the GUI input queues. Godot's expensive
     * initialization then blocks this window's paint/message delivery too.
     * Keep independent windows and cover only while this application is active. */
    BOOL active=splash.native_test||foreground==splash.window||foreground==splash.child_window;
    if(active!=splash.topmost) {
        SetWindowPos(splash.window,active?HWND_TOPMOST:HWND_NOTOPMOST,0,0,0,0,SWP_NOACTIVATE|SWP_NOMOVE|SWP_NOSIZE);
        splash.topmost=active;
    }
    if(splash.ready_seen) {
        RECT client;POINT position={0,0};GetClientRect(splash.child_window,&client);ClientToScreen(splash.child_window,&position);
        RECT bounds={position.x,position.y,position.x+client.right,position.y+client.bottom};
        if(!EqualRect(&bounds,&splash.last_child_rect)) {
            SetWindowPos(splash.window,NULL,position.x,position.y,client.right,client.bottom,SWP_NOACTIVATE|SWP_NOZORDER);
            splash.last_child_rect=bounds;++splash.layout_changes;
        }
        splash.runtime_covered=TRUE;
    }
    if(!splash.native_test&&splash.ready_seen&&foreground==splash.child_window)SetForegroundWindow(splash.window);
}
static void finish_splash(void) {
    if(splash.done)return;
    splash.done=TRUE;splash.finished=GetTickCount64();
    save_profile(); /* The runtime reads this immediately after seeing done. */
    HWND foreground=GetForegroundWindow();ShowWindow(splash.window,SW_HIDE);
    if(splash.child_window&&(foreground==splash.window||foreground==splash.child_window))SetForegroundWindow(splash.child_window);
    marker(L"done",splash.skip_requested?"skipped":"completed");DestroyWindow(splash.window);
}
static void begin_exit(void) {
    if(splash.exit_started||!splash.ready_seen)return;
    splash.exit_started=GetTickCount64();marker(L"exiting",splash.skip_requested?"skipped":"completed");save_profile();
}
static void request_skip(void) {
    if(splash.done)return;
    if(splash.exit_started){++splash.exit_inputs;save_profile();return;}
    ULONGLONG now=GetTickCount64();
    if(!splash.ready_seen||!splash.full_logo||now-splash.full_logo<500){++splash.rejected_inputs;save_profile();return;}
    splash.skip_requested=TRUE;splash.accepted_frame=(DWORD)splash.pack.decoded_frame;
    marker(L"skip","requested");begin_exit();
}
static void draw_frame(HWND window) {
    LARGE_INTEGER began;QueryPerformanceCounter(&began);
    PAINTSTRUCT paint;HDC dc=BeginPaint(window,&paint);RECT client;GetClientRect(window,&client);
    int width=client.right,height=client.bottom;
    if(width<=0||height<=0){EndPaint(window,&paint);return;}
    BOOL cached=resize_surface(&splash.surface,dc,width,height);
    PaintSurface *surface=&splash.surface;
    /* Cover the client rectangle rather than letterboxing. Only the edges of
     * the background are cropped; the centered wordmark keeps its proportions. */
    int sw=splash.pack.width,sh=splash.pack.height;
    if((int64_t)width*sh>(int64_t)height*sw)sh=(int)((int64_t)sw*height/width);
    else sw=(int)((int64_t)sh*width/height);
    int sx=((int)splash.pack.width-sw)/2,sy=((int)splash.pack.height-sh)/2;
    if(!cached||surface->frame!=splash.pack.decoded_frame) {
        HDC target=cached?surface->dc:dc;
        SetStretchBltMode(target,HALFTONE);SetBrushOrgEx(target,0,0,NULL);
        StretchDIBits(target,0,0,width,height,sx,sy,sw,sh,splash.pack.pixels,&splash.pack.bitmap,DIB_RGB_COLORS,SRCCOPY);
        if(cached)surface->frame=splash.pack.decoded_frame;
        ULONGLONG tick=GetTickCount64();
        if(splash.last_frame_tick&&!splash.exit_started) {
            DWORD gap=(DWORD)(tick-splash.last_frame_tick);
            if(gap>splash.max_frame_gap_ms)splash.max_frame_gap_ms=gap;
        }
        splash.last_frame_tick=tick;++splash.frame_changes;
    }
    PaintSurface *output=surface;
    if(splash.exit_started) {
        ULONGLONG age=GetTickCount64()-splash.exit_started;
        double amount=age>=EXIT_MS?1.0:(double)age/EXIT_MS;
        BYTE alpha=(BYTE)(255.0*(1.0-amount*amount*(3.0-2.0*amount)));
        if(alpha!=splash.opacity){SetLayeredWindowAttributes(window,0,alpha,LWA_ALPHA);splash.opacity=alpha;}
        /* Scale only once; exit fragments work at the actual window resolution. */
        if(cached&&resize_surface(&splash.exit_surface,dc,width,height)) {
            PatBlt(splash.exit_surface.dc,0,0,width,height,BLACKNESS);
            for(int row=0;row<height;) {
                int band=row*360/height/11;
                int end=((band+1)*11*height+359)/360;if(end>height)end=height;
                int shift=(band%3==0?1:-1)*(int)(amount*amount*(9+(band*7)%23)*width/640);
                BitBlt(splash.exit_surface.dc,shift>0?shift:0,row,width-(shift<0?-shift:shift),end-row,surface->dc,shift<0?-shift:0,row,SRCCOPY);
                row=end;
            }
            output=&splash.exit_surface;
        }
    }
    if(cached)BitBlt(dc,0,0,width,height,output->dc,0,0,SRCCOPY);
    if(!splash.shown)GdiFlush(); /* Present before CreateProcess, not a GPU wait on every frame. */
    EndPaint(window,&paint);ULONGLONG now=GetTickCount64();
    ++splash.paints;DWORD duration=elapsed_us(began);if(duration>splash.max_paint_us)splash.max_paint_us=duration;
    const BYTE *pixels=cached?output->pixels:splash.pack.pixels;
    DWORD pw=cached?(DWORD)width:splash.pack.width,ph=cached?(DWORD)height:splash.pack.height;
    if(!splash.shown){splash.shown=now;splash.first_window_visible=IsWindowVisible(window);marker(L"shown","visible");save_profile();capture_frame_png(L"native-first.png",pixels,pw,ph);}
    if(!splash.full_logo&&splash.pack.decoded_frame==LOGO_FRAME){splash.full_logo=now;marker(L"logo","complete");save_profile();capture_frame_png(L"native-logo.png",pixels,pw,ph);}
    if(splash.exit_started&&!splash.exit_capture_saved&&now-splash.exit_started>=EXIT_MS/2) {
        splash.exit_capture_saved=TRUE;capture_frame_png(L"native-exit.png",pixels,pw,ph);
    }
}
static LRESULT CALLBACK splash_proc(HWND window,UINT message,WPARAM wparam,LPARAM lparam) {
    switch(message) {
    case WM_ERASEBKGND:return 1;
    case WM_PAINT:draw_frame(window);return 0;
    case WM_SIZE:InvalidateRect(window,NULL,FALSE);return 0;
    case FRAME_DECODED:SendMessageW(window,WM_TIMER,1,0);return 0;
    case CHILD_CREATED: {
        ChildLaunch *launch=(ChildLaunch*)lparam;
        splash.launch_ms=launch->elapsed_ms;
        if(!launch->succeeded){marker(L"cancel","runtime_launch_failed");finish_splash();return 0;}
        splash.child=launch->child;
        ResumeThread(splash.child.hThread);CloseHandle(splash.child.hThread);splash.child.hThread=NULL;
        save_profile();return 0;
    }
    case WM_SYSKEYDOWN:
        if(wparam==VK_F4&&(lparam&(1L<<29))){SendMessageW(window,WM_CLOSE,0,0);return 0;}
        /* fall through */
    case WM_KEYDOWN:
        /* Real user input must not alter an automated natural/skip branch.
         * Test PostMessage keys have lparam=0 and exercise this same handler. */
        if(splash.native_test&&lparam!=0)return 0;
        if(!(lparam&(1L<<30)))request_skip();
        return 0;
    case WM_LBUTTONDOWN:case WM_RBUTTONDOWN:case WM_MBUTTONDOWN:
        if(!splash.native_test)request_skip();
        return 0;
    case WM_TIMER: {
        ULONGLONG now=GetTickCount64();
        if(now-splash.heartbeat_tick>=250)write_heartbeat();
        if(splash.child.hProcess&&WaitForSingleObject(splash.child.hProcess,0)==WAIT_OBJECT_0){finish_splash();return 0;}
        if(!splash.ready_seen&&marker_exists(L"ready")){splash.ready_seen=TRUE;splash.ready=now;save_profile();}
        LARGE_INTEGER follow;QueryPerformanceCounter(&follow);follow_child_window();
        DWORD follow_us=elapsed_us(follow);if(follow_us>splash.max_follow_us)splash.max_follow_us=follow_us;
        DWORD index=FIRST_FRAME+(DWORD)((now-splash.shown)*splash.pack.fps_num/(1000*splash.pack.fps_den));
        if(index>=splash.pack.count)index=splash.pack.count-1;
        /* A delayed tick must actually present the stable logo before counting
         * its half-second hold; a late glitch/final frame is not equivalent. */
        if(!splash.full_logo&&index>=LOGO_FRAME)index=LOGO_FRAME;
        int previous=splash.pack.decoded_frame;
        if(!splash.exit_started&&!present_frame(index)){marker(L"cancel","asset_decode_failed");finish_splash();return 0;}
        if(splash.native_test&&!splash.test_early_sent&&splash.shown&&now-splash.shown>100) {
            splash.test_early_sent=TRUE;PostMessageW(window,WM_KEYDOWN,VK_ESCAPE,0);
        }
        if(splash.auto_skip&&!splash.test_valid_sent&&splash.ready_seen&&splash.full_logo&&now-splash.full_logo>=550) {
            splash.test_valid_sent=TRUE;PostMessageW(window,WM_KEYDOWN,VK_ESCAPE,0);
        }
        if(splash.native_test&&splash.exit_started&&!splash.test_exit_sent&&now-splash.exit_started>100) {
            splash.test_exit_sent=TRUE;PostMessageW(window,WM_KEYDOWN,VK_ESCAPE,0);
        }
        BOOL logo_held=splash.full_logo&&now-splash.full_logo>=500;
        if(splash.ready_seen&&logo_held&&(splash.skip_requested||splash.pack.decoded_frame==(int)splash.pack.count-1))begin_exit();
        if(splash.exit_started&&now-splash.exit_started>=EXIT_MS){finish_splash();return 0;}
        if(!splash.ready_seen&&splash.shown&&now-splash.shown>45000){marker(L"cancel","handshake_timeout");finish_splash();return 0;}
        if(previous!=splash.pack.decoded_frame||splash.exit_started)InvalidateRect(window,NULL,FALSE);
        return 0;
    }
    case WM_CLOSE:marker(L"cancel","window_closed");if(splash.child.hProcess)TerminateProcess(splash.child.hProcess,0);finish_splash();return 0;
    case WM_DESTROY:PostQuitMessage(0);return 0;
    default:return DefWindowProcW(window,message,wparam,lparam);
    }
}
static BOOL create_splash(HINSTANCE instance,const wchar_t *arguments,BOOL test) {
    SetProcessDPIAware();WNDCLASSW cls={0};cls.lpfnWndProc=splash_proc;cls.hInstance=instance;
    cls.lpszClassName=WINDOW_CLASS;cls.hCursor=LoadCursorW(NULL,IDC_ARROW);
    if(!RegisterClassW(&cls)&&GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)return FALSE;
    MONITORINFO monitor={0};monitor.cbSize=sizeof(monitor);POINT point={0,0};
    GetMonitorInfoW(MonitorFromPoint(point,MONITOR_DEFAULTTOPRIMARY),&monitor);
    BOOL fullscreen=!test&&preference_enabled(L"fullscreen",FALSE);
    RECT area=fullscreen?monitor.rcMonitor:monitor.rcWork;int width=1920,height=1080;
    const wchar_t *resolution=wcsstr(arguments,L"--resolution ");
    if(resolution){int w,h;if(swscanf(resolution+13,L"%dx%d",&w,&h)==2&&w>100&&h>100){width=w;height=h;}}
    if(fullscreen){width=area.right-area.left;height=area.bottom-area.top;}
    if(width>area.right-area.left)width=area.right-area.left;
    if(height>area.bottom-area.top)height=area.bottom-area.top;
    int x=area.left+(area.right-area.left-width)/2,y=area.top+(area.bottom-area.top-height)/2;
    splash.window=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_LAYERED|WS_EX_TOPMOST,WINDOW_CLASS,L"cybertranslator",WS_POPUP,x,y,width,height,NULL,NULL,instance,NULL);
    if(!splash.window)return FALSE;
    splash.topmost=TRUE;GetWindowRect(splash.window,&splash.last_child_rect);
    splash.opacity=255;SetLayeredWindowAttributes(splash.window,0,255,LWA_ALPHA);ShowWindow(splash.window,SW_SHOW);
    /* STARTUPINFO may override the first ShowWindow during hidden GUI tests. */
    SetWindowPos(splash.window,NULL,0,0,0,0,SWP_SHOWWINDOW|SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_NOZORDER);
    if(!splash.native_test)SetForegroundWindow(splash.window);
    UpdateWindow(splash.window);return TRUE;
}

static void play_splash(void) {
    /* Absolute frame deadlines avoid WM_TIMER's 16/31-ms quantization. Modern
     * Windows supplies a high-resolution waitable timer; older builds fall back. */
    HANDLE timer=CreateWaitableTimerExW(NULL,NULL,0x00000002,TIMER_ALL_ACCESS);
    BOOL legacy=!timer;
    if(!timer){timer=CreateWaitableTimerW(NULL,FALSE,NULL);timeBeginPeriod(1);}
    if(!timer){marker(L"cancel","timer_failed");finish_splash();timeEndPeriod(1);return;}
    while(!splash.done) {
        ULONGLONG now=GetTickCount64(),elapsed=now-(splash.exit_started?splash.exit_started:splash.shown);
        DWORD rate=splash.exit_started?60:splash.pack.fps_num;
        ULONGLONG next=(elapsed*rate/1000+1)*1000;
        next=(next+rate-1)/rate;
        LARGE_INTEGER due;due.QuadPart=-(LONGLONG)(next>elapsed?next-elapsed:1)*10000;
        SetWaitableTimer(timer,&due,0,NULL,NULL,FALSE);
        DWORD result=MsgWaitForMultipleObjectsEx(1,&timer,INFINITE,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
        if(result==WAIT_OBJECT_0)SendMessageW(splash.window,WM_TIMER,1,0);
        else if(result==WAIT_FAILED){marker(L"cancel","timer_wait_failed");finish_splash();break;}
        MSG message;
        while(PeekMessageW(&message,NULL,0,0,PM_REMOVE)) {
            if(message.message==WM_QUIT)break;
            TranslateMessage(&message);DispatchMessageW(&message);
        }
    }
    CancelWaitableTimer(timer);CloseHandle(timer);if(legacy)timeEndPeriod(1);
}
static DWORD WINAPI launch_child(void *parameter) {
    ChildLaunch *launch=parameter;ULONGLONG began=GetTickCount64();
    STARTUPINFOW startup={0};startup.cb=sizeof(startup);startup.dwFlags=STARTF_USESHOWWINDOW;startup.wShowWindow=SW_SHOWNA;
    /* Security scans/process creation can themselves stall for hundreds of ms.
     * Start suspended on a worker and resume on the UI after receiving its handles. */
    launch->succeeded=CreateProcessW(NULL,launch->command,NULL,NULL,FALSE,CREATE_SUSPENDED,NULL,launch->folder,&startup,&launch->child);
    launch->elapsed_ms=(DWORD)(GetTickCount64()-began);
    PostMessageW(launch->window,CHILD_CREATED,0,(LPARAM)launch);return 0;
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,LPWSTR arguments,int show) {
    (void)previous;(void)show;
    /* This helper must not initialize COM, decode artwork or launch a runtime.
     * Godot's Windows process map cannot query its native parent reliably. */
    if(argument_present(arguments,L"--native-parent-alive")) {
        const wchar_t *argument=wcsstr(arguments,L"--native-parent-alive")+21;
        while(*argument==L' '||*argument==L'\t')++argument;
        wchar_t *end=NULL;unsigned long pid=wcstoul(argument,&end,10);
        if(!pid||end==argument)return 1;
        HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,(DWORD)pid);
        if(!process)return GetLastError()==ERROR_ACCESS_DENIED?0:1;
        DWORD exit_code=0;
        BOOL queried=GetExitCodeProcess(process,&exit_code);CloseHandle(process);
        return !queried||exit_code==STILL_ACTIVE?0:1;
    }
    splash.entered=GetTickCount64();
    QueryPerformanceFrequency(&clock_frequency);splash.surface.frame=splash.exit_surface.frame=-1;
    GetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_PROFILE",splash.profile,32768);
    wchar_t folder[32768];if(!GetModuleFileNameW(NULL,folder,32768))return 1;
    wchar_t *slash=wcsrchr(folder,L'\\');if(!slash)return 1;*slash=0;
    BOOL test=argument_present(arguments,L"--test");
    splash.borderless=test?argument_present(arguments,L"--borderless-test"):preference_enabled(L"borderless",FALSE);
    splash.native_test=test&&argument_present(arguments,L"--native-startup-test");
    splash.performance_only=test&&argument_present(arguments,L"--native-startup-performance");
    splash.auto_skip=test&&argument_present(arguments,L"--native-startup-auto-skip");
    if(splash.native_test&&!splash.profile[0]) {
        wchar_t output[32768];if(GetEnvironmentVariableW(L"GRIDDY_TEST_OUTPUT",output,32768)) {
            CreateDirectoryW(output,NULL);path_join(splash.profile,32768,output,L"native-timing.json");
        }
    }
    BOOL native=!argument_present(arguments,L"--headless")&&(test?argument_present(arguments,L"--startup-animation"):preference_enabled(L"startup_animation",TRUE));
    HRESULT com=CoInitializeEx(NULL,COINIT_APARTMENTTHREADED);
    if(argument_present(arguments,L"--native-splash-probe")) {
        BOOL valid=SUCCEEDED(com)&&load_pack(&splash.pack,folder);
        if(valid)for(DWORD index=0;index<splash.pack.count;++index)if(!decode_frame(&splash.pack,index)){valid=FALSE;break;}
        save_profile();release_pack(&splash.pack);if(SUCCEEDED(com))CoUninitialize();return valid?0:2;
    }
    SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_ACTIVE",NULL);SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_DIR",NULL);SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_START_MS",NULL);
    native=native&&SUCCEEDED(com)&&load_pack(&splash.pack,folder);
    if(native)native=make_handshake()&&create_splash(instance,arguments,test);
    if(native)start_decoder();
    if(!native){SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_ACTIVE",NULL);SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_DIR",NULL);SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_START_MS",NULL);cleanup_handshake();}
    wchar_t native_pid[32];_snwprintf(native_pid,32,L"%lu",(unsigned long)GetCurrentProcessId());
    SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_PID",native?native_pid:NULL);
    size_t capacity=wcslen(folder)+wcslen(arguments)+256;
    wchar_t *command=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,capacity*sizeof(wchar_t));
    if(!command){if(native)finish_splash();cleanup_handshake();stop_decoder();release_surface(&splash.surface);release_surface(&splash.exit_surface);release_pack(&splash.pack);if(SUCCEEDED(com))CoUninitialize();return 1;}
    if(native) {
        RECT bounds;GetWindowRect(splash.window,&bounds);
        _snwprintf(command,capacity,L"\"%ls\\GriddyTranslate.runtime.exe\" --resolution %ldx%ld --position %ld,%ld %ls",folder,bounds.right-bounds.left,bounds.bottom-bounds.top,bounds.left,bounds.top,arguments);
    } else _snwprintf(command,capacity,L"\"%ls\\GriddyTranslate.runtime.exe\" %ls",folder,arguments);
    SetEnvironmentVariableW(L"DISABLE_RTSS_LAYER",L"1");SetEnvironmentVariableW(L"VK_LOADER_LAYERS_DISABLE",L"VK_LAYER_RTSS");
    BOOL started;
    if(native) {
        ChildLaunch launch={0};launch.command=command;launch.folder=folder;launch.window=splash.window;
        HANDLE thread=CreateThread(NULL,0,launch_child,&launch,0,NULL);
        if(!thread)launch_child(&launch);
        play_splash();
        if(thread){WaitForSingleObject(thread,INFINITE);CloseHandle(thread);}
        started=launch.succeeded;
        if(started&&!splash.child.hProcess) {
            /* The user closed the splash before process creation finished. */
            splash.child=launch.child;TerminateProcess(splash.child.hProcess,0);
            CloseHandle(splash.child.hThread);splash.child.hThread=NULL;
        }
    } else {
        STARTUPINFOW startup={0};startup.cb=sizeof(startup);startup.dwFlags=STARTF_USESHOWWINDOW;startup.wShowWindow=SW_SHOWNORMAL;
        started=CreateProcessW(NULL,command,NULL,NULL,FALSE,0,NULL,folder,&startup,&splash.child);
        if(started){CloseHandle(splash.child.hThread);splash.child.hThread=NULL;save_profile();}
    }
    HeapFree(GetProcessHeap(),0,command);
    if(!started){if(native)finish_splash();cleanup_handshake();stop_decoder();MessageBoxW(NULL,L"无法启动翻译器。请先解压整个 ZIP，并让 exe、runtime.exe、runtime.pck 和 DLL 保持在同一个文件夹。",L"GriddyTranslate",MB_OK|MB_ICONERROR);release_surface(&splash.surface);release_surface(&splash.exit_surface);release_pack(&splash.pack);if(SUCCEEDED(com))CoUninitialize();return 1;}
    stop_decoder();release_surface(&splash.surface);release_surface(&splash.exit_surface);
    DWORD result=0;
    if(splash.native_test) {
        if(WaitForSingleObject(splash.child.hProcess,45000)==WAIT_OBJECT_0)GetExitCodeProcess(splash.child.hProcess,&result);
        else {TerminateProcess(splash.child.hProcess,3);result=3;}
    }
    if(splash.native_test||WaitForSingleObject(splash.child.hProcess,0)==WAIT_OBJECT_0)cleanup_handshake();
    CloseHandle(splash.child.hProcess);release_pack(&splash.pack);if(SUCCEEDED(com))CoUninitialize();return (int)result;
}
