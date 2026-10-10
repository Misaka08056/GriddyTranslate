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

typedef struct {
    HANDLE file, mapping;
    const BYTE *data;
    DWORD size, width, height, fps_num, fps_den, count;
    const uint32_t *offsets;
    IWICImagingFactory *factory;
    BYTE *pixels, *exit_pixels;
    BITMAPINFO bitmap;
    int decoded_frame;
} FramePack;
typedef struct {
    FramePack pack;
    PROCESS_INFORMATION child;
    HWND window, child_window;
    ULONGLONG entered, shown, full_logo, ready, exit_started, finished, heartbeat_tick;
    DWORD rejected_inputs, exit_inputs, accepted_frame;
    BOOL ready_seen, skip_requested, done, auto_skip, native_test, owner_attached, first_window_visible;
    BOOL test_early_sent, test_valid_sent, test_exit_sent, exit_capture_saved;
    wchar_t handshake[32768], profile[32768];
} Splash;
static Splash splash;

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
        "\"first_window_visible\":%s,\"owner_attached\":%s}\n",
        (unsigned long)GetCurrentProcessId(),(unsigned long)splash.child.dwProcessId,
        (unsigned long long)(splash.shown?splash.shown-splash.entered:0),
        (unsigned long long)(splash.full_logo?splash.full_logo-splash.entered:0),
        (unsigned long long)(splash.ready?splash.ready-splash.entered:0),
        (unsigned long long)(splash.exit_started?splash.exit_started-splash.entered:0),
        (unsigned long long)(splash.finished?splash.finished-splash.entered:0),
        splash.skip_requested?"true":"false",(unsigned long)splash.rejected_inputs,(unsigned long)splash.exit_inputs,
        FIRST_FRAME,(unsigned long)splash.accepted_frame,(unsigned long)splash.pack.count,(unsigned long)splash.pack.width,(unsigned long)splash.pack.height,
        splash.first_window_visible?"true":"false",splash.owner_attached?"true":"false");
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
    if(pack->exit_pixels)HeapFree(GetProcessHeap(),0,pack->exit_pixels);
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
    pack->pixels=HeapAlloc(GetProcessHeap(),0,pixels);pack->exit_pixels=HeapAlloc(GetProcessHeap(),0,pixels);
    if(!pack->pixels||!pack->exit_pixels)return FALSE;
    pack->bitmap.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);pack->bitmap.bmiHeader.biWidth=pack->width;
    pack->bitmap.bmiHeader.biHeight=-(LONG)pack->height;pack->bitmap.bmiHeader.biPlanes=1;
    pack->bitmap.bmiHeader.biBitCount=32;pack->bitmap.bmiHeader.biCompression=BI_RGB;
    return decode_frame(pack,FIRST_FRAME);
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
static void capture_frame_png(const wchar_t *name, const BYTE *pixels) {
    if(!splash.native_test)return;
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
    if(SUCCEEDED(result))result=IWICBitmapFrameEncode_SetSize(frame,splash.pack.width,splash.pack.height);
    WICPixelFormatGUID format=GUID_WICPixelFormat24bppBGR;
    if(SUCCEEDED(result))result=IWICBitmapFrameEncode_SetPixelFormat(frame,&format);
    if(SUCCEEDED(result)&&memcmp(&format,&GUID_WICPixelFormat24bppBGR,sizeof(format))!=0)result=E_FAIL;
    DWORD count=splash.pack.width*splash.pack.height;
    if(SUCCEEDED(result)) {
        bgr=HeapAlloc(GetProcessHeap(),0,(SIZE_T)count*3);
        if(!bgr)result=E_OUTOFMEMORY;
    }
    if(SUCCEEDED(result)) {
        for(DWORD pixel=0;pixel<count;++pixel){bgr[pixel*3]=pixels[pixel*4];bgr[pixel*3+1]=pixels[pixel*4+1];bgr[pixel*3+2]=pixels[pixel*4+2];}
        result=IWICBitmapFrameEncode_WritePixels(frame,splash.pack.height,splash.pack.width*3,count*3,bgr);
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
    if(!splash.child_window)EnumWindows(find_child_window,(LPARAM)splash.child.dwProcessId);
    if(!splash.child_window||!IsWindow(splash.child_window)||IsIconic(splash.child_window))return;
    RECT client;POINT position={0,0};GetClientRect(splash.child_window,&client);ClientToScreen(splash.child_window,&position);
    HWND foreground=GetForegroundWindow();
    SetWindowLongPtrW(splash.window,GWLP_HWNDPARENT,(LONG_PTR)splash.child_window);
    if(!splash.owner_attached) {
        SetWindowPos(splash.window,HWND_NOTOPMOST,position.x,position.y,client.right,client.bottom,SWP_NOACTIVATE);
        splash.owner_attached=TRUE;
    } else SetWindowPos(splash.window,NULL,position.x,position.y,client.right,client.bottom,SWP_NOACTIVATE|SWP_NOZORDER);
    /* Owned windows stay above their runtime without covering unrelated apps. */
    if(!splash.native_test&&foreground==splash.child_window)SetForegroundWindow(splash.window);
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
    PAINTSTRUCT paint;HDC dc=BeginPaint(window,&paint);RECT client;GetClientRect(window,&client);
    int width=client.right,height=client.bottom,fw=width,fh=(int)((int64_t)width*9/16);
    if(fh>height){fh=height;fw=(int)((int64_t)height*16/9);}
    int x=(width-fw)/2,y=(height-fh)/2;
    HBRUSH background=CreateSolidBrush(RGB(3,1,2));
    RECT edges[4]={{0,0,width,y},{0,y+fh,width,height},{0,y,x,y+fh},{x+fw,y,width,y+fh}};
    for(int edge=0;edge<4;++edge)FillRect(dc,&edges[edge],background);
    DeleteObject(background);
    BYTE *pixels=splash.pack.pixels;
    if(splash.exit_started) {
        ULONGLONG age=GetTickCount64()-splash.exit_started;
        double amount=age>=EXIT_MS?1.0:(double)age/EXIT_MS;
        BYTE alpha=(BYTE)(255.0*(1.0-amount*amount*(3.0-2.0*amount)));
        SetLayeredWindowAttributes(window,0,alpha,LWA_ALPHA);
        /* Every exit uses horizontal signal fragments followed by a dissolve. */
        DWORD row_bytes=splash.pack.width*4;
        for(DWORD row=0;row<splash.pack.height;++row) {
            int band=(int)(row*360/splash.pack.height/11);
            int shift=(band%3==0?1:-1)*(int)(amount*amount*(9+(band*7)%23)*splash.pack.width/640);
            BYTE *out=splash.pack.exit_pixels+row*row_bytes;
            const BYTE *in=splash.pack.pixels+row*row_bytes;
            memset(out,0,row_bytes);
            if(shift>=0)memcpy(out+shift*4,in,row_bytes-shift*4);
            else memcpy(out,in-shift*4,row_bytes+shift*4);
        }pixels=splash.pack.exit_pixels;
    }
    SetStretchBltMode(dc,HALFTONE);SetBrushOrgEx(dc,0,0,NULL);
    StretchDIBits(dc,x,y,fw,fh,0,0,splash.pack.width,splash.pack.height,pixels,&splash.pack.bitmap,DIB_RGB_COLORS,SRCCOPY);
    GdiFlush();
    EndPaint(window,&paint);ULONGLONG now=GetTickCount64();
    if(!splash.shown){splash.shown=now;splash.first_window_visible=IsWindowVisible(window);marker(L"shown","visible");save_profile();capture_frame_png(L"native-first.png",pixels);}
    if(!splash.full_logo&&splash.pack.decoded_frame>=LOGO_FRAME){splash.full_logo=now;marker(L"logo","complete");save_profile();capture_frame_png(L"native-logo.png",pixels);}
    if(splash.exit_started&&!splash.exit_capture_saved&&now-splash.exit_started>=EXIT_MS/2) {
        splash.exit_capture_saved=TRUE;capture_frame_png(L"native-exit.png",pixels);
    }
}
static LRESULT CALLBACK splash_proc(HWND window,UINT message,WPARAM wparam,LPARAM lparam) {
    switch(message) {
    case WM_ERASEBKGND:return 1;
    case WM_PAINT:draw_frame(window);return 0;
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
        follow_child_window();
        if(!splash.ready_seen&&marker_exists(L"ready")){splash.ready_seen=TRUE;splash.ready=now;save_profile();}
        DWORD index=FIRST_FRAME+(DWORD)((now-splash.shown)*splash.pack.fps_num/(1000*splash.pack.fps_den));
        if(index>=splash.pack.count)index=splash.pack.count-1;
        /* A delayed tick must actually present the stable logo before counting
         * its half-second hold; a late glitch/final frame is not equivalent. */
        if(!splash.full_logo&&index>=LOGO_FRAME)index=LOGO_FRAME;
        if(!splash.exit_started&&!decode_frame(&splash.pack,index)){marker(L"cancel","asset_decode_failed");finish_splash();return 0;}
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
        if(splash.ready_seen&&logo_held&&(splash.skip_requested||index==splash.pack.count-1))begin_exit();
        if(splash.exit_started&&now-splash.exit_started>=EXIT_MS){finish_splash();return 0;}
        if(!splash.ready_seen&&splash.shown&&now-splash.shown>45000){marker(L"cancel","handshake_timeout");finish_splash();return 0;}
        InvalidateRect(window,NULL,FALSE);return 0;
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
    SetLayeredWindowAttributes(splash.window,0,255,LWA_ALPHA);ShowWindow(splash.window,SW_SHOW);
    /* STARTUPINFO may override the first ShowWindow during hidden GUI tests. */
    SetWindowPos(splash.window,NULL,0,0,0,0,SWP_SHOWWINDOW|SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_NOZORDER);
    if(!splash.native_test)SetForegroundWindow(splash.window);
    UpdateWindow(splash.window);SetTimer(splash.window,1,16,NULL);return TRUE;
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
    GetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_PROFILE",splash.profile,32768);
    wchar_t folder[32768];if(!GetModuleFileNameW(NULL,folder,32768))return 1;
    wchar_t *slash=wcsrchr(folder,L'\\');if(!slash)return 1;*slash=0;
    BOOL test=argument_present(arguments,L"--test");
    splash.native_test=test&&argument_present(arguments,L"--native-startup-test");
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
    if(!native){SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_ACTIVE",NULL);SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_DIR",NULL);SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_START_MS",NULL);cleanup_handshake();}
    wchar_t native_pid[32];_snwprintf(native_pid,32,L"%lu",(unsigned long)GetCurrentProcessId());
    SetEnvironmentVariableW(L"GRIDDY_NATIVE_SPLASH_PID",native?native_pid:NULL);
    size_t capacity=wcslen(folder)+wcslen(arguments)+256;
    wchar_t *command=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,capacity*sizeof(wchar_t));
    if(!command){if(native)finish_splash();cleanup_handshake();release_pack(&splash.pack);if(SUCCEEDED(com))CoUninitialize();return 1;}
    _snwprintf(command,capacity,L"\"%ls\\GriddyTranslate.runtime.exe\" %ls",folder,arguments);
    SetEnvironmentVariableW(L"DISABLE_RTSS_LAYER",L"1");SetEnvironmentVariableW(L"VK_LOADER_LAYERS_DISABLE",L"VK_LAYER_RTSS");
    STARTUPINFOW startup={0};startup.cb=sizeof(startup);startup.dwFlags=STARTF_USESHOWWINDOW;startup.wShowWindow=native?SW_SHOWNA:SW_SHOWNORMAL;
    BOOL started=CreateProcessW(NULL,command,NULL,NULL,FALSE,0,NULL,folder,&startup,&splash.child);HeapFree(GetProcessHeap(),0,command);
    if(!started){if(native)finish_splash();cleanup_handshake();MessageBoxW(NULL,L"无法启动翻译器。请先解压整个 ZIP，并让 exe、runtime.exe、runtime.pck 和 DLL 保持在同一个文件夹。",L"GriddyTranslate",MB_OK|MB_ICONERROR);release_pack(&splash.pack);if(SUCCEEDED(com))CoUninitialize();return 1;}
    CloseHandle(splash.child.hThread);save_profile();
    if(native){MSG message;while(GetMessageW(&message,NULL,0,0)>0){TranslateMessage(&message);DispatchMessageW(&message);}}
    DWORD result=0;
    if(splash.native_test) {
        if(WaitForSingleObject(splash.child.hProcess,45000)==WAIT_OBJECT_0)GetExitCodeProcess(splash.child.hProcess,&result);
        else {TerminateProcess(splash.child.hProcess,3);result=3;}
    }
    if(splash.native_test||WaitForSingleObject(splash.child.hProcess,0)==WAIT_OBJECT_0)cleanup_handshake();
    CloseHandle(splash.child.hProcess);release_pack(&splash.pack);if(SUCCEEDED(com))CoUninitialize();return (int)result;
}
