-- Launch a second LÖVE GUI without a shell or console window.
local M={}
local ffi=require("ffi")
function M.quote(value)
  -- Microsoft CRT argv quoting, including trailing backslashes.
  value=tostring(value)
  value=value:gsub('(\\*)"',function(slashes) return slashes..slashes..'\\"' end)
  value=value:gsub('(\\+)$',function(slashes) return slashes..slashes end)
  return '"'..value..'"'
end
if ffi.os=="Windows" then
  ffi.cdef[[
    typedef struct {
      unsigned long cb; unsigned short *reserved, *desktop, *title;
      unsigned long x,y,xSize,ySize,xChars,yChars,fill,flags;
      unsigned short show,reservedCount; unsigned char *reservedBytes;
      void *input,*output,*error;
    } CEW_STARTUP;
    typedef struct { void *process,*thread; unsigned long pid,tid; } CEW_PROCESS;
    int __stdcall MultiByteToWideChar(unsigned int,unsigned long,const char*,int,unsigned short*,int);
    int __stdcall CreateProcessW(const unsigned short*,unsigned short*,void*,void*,int,unsigned long,void*,const unsigned short*,CEW_STARTUP*,CEW_PROCESS*);
    int __stdcall GetExitCodeProcess(void*,unsigned long*);
    int __stdcall CloseHandle(void*);
    unsigned long __stdcall GetLastError(void);
    int __stdcall EnumWindows(int (__stdcall *)(void*,intptr_t),intptr_t);
    unsigned long __stdcall GetWindowThreadProcessId(void*,unsigned long*);
    int __stdcall IsWindowVisible(void*);
    int __stdcall ShowWindow(void*,int);
    int __stdcall SetForegroundWindow(void*);
  ]]
  local kernel=ffi.load("kernel32");local user=ffi.load("user32")
  local function wide(text)
    local n=kernel.MultiByteToWideChar(65001,0,text,#text,nil,0)
    assert(n>0,"Invalid window launch path")
    local out=ffi.new("unsigned short[?]",n+1)
    kernel.MultiByteToWideChar(65001,0,text,#text,out,n);return out
  end
  function M.start(exe,args)
    local parts={M.quote(exe)};for _,v in ipairs(args) do parts[#parts+1]=M.quote(v) end
    local startup=ffi.new("CEW_STARTUP[1]");startup[0].cb=ffi.sizeof("CEW_STARTUP")
    local result=ffi.new("CEW_PROCESS[1]")
    if kernel.CreateProcessW(wide(exe),wide(table.concat(parts," ")),nil,nil,0,0,nil,nil,startup,result)==0 then
      return nil,"Could not open the event window (Windows error "..tonumber(kernel.GetLastError())..")"
    end
    kernel.CloseHandle(result[0].thread)
    local handle,pid=result[0].process,tonumber(result[0].pid)
    return {
      running=function()
        local code=ffi.new("unsigned long[1]")
        return handle~=nil and kernel.GetExitCodeProcess(handle,code)~=0 and code[0]==259
      end,
      close=function() if handle then kernel.CloseHandle(handle);handle=nil end end,
      focus=function()
        local found=false
        local callback=ffi.cast("int (__stdcall *)(void*,intptr_t)",function(hwnd)
          local owner=ffi.new("unsigned long[1]");user.GetWindowThreadProcessId(hwnd,owner)
          if tonumber(owner[0])==pid and user.IsWindowVisible(hwnd)~=0 then
            found=true
            user.ShowWindow(hwnd,9);user.SetForegroundWindow(hwnd);return 0
          end
          return 1
        end)
        user.EnumWindows(callback,0);callback:free()
        return found
      end,
    }
  end
else
  ffi.cdef[[
    extern char **environ;
    int posix_spawnp(int*,const char*,const void*,const void*,char *const[],char *const[]);
    int waitpid(int,int*,int);
  ]]
  function M.start(exe,args)
    local buffers={};local argv=ffi.new("char *[?]",#args+2)
    for i=0,#args do
      local value=i==0 and exe or args[i]
      buffers[i+1]=ffi.new("char[?]",#value+1,value);argv[i]=buffers[i+1]
    end
    local pid=ffi.new("int[1]")
    local code=ffi.C.posix_spawnp(pid,exe,nil,nil,argv,ffi.C.environ)
    if code~=0 then return nil,"Could not open the event window (spawn error "..code..")" end
    local alive=true
    return {running=function()
      if alive then alive=ffi.C.waitpid(pid[0],ffi.new("int[1]"),1)==0 end
      return alive
    end,close=function() end,focus=function() end}
  end
end
return M
