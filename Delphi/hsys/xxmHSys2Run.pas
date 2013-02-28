unit xxmHSys2Run;

interface

type
  TXxmHandleMessagesProc=procedure(var QuitApp:boolean);

procedure XxmRunHSys(HandleMessagesProc:TXxmHandleMessagesProc);

procedure HandleWindowsMessages(var QuitApp:boolean);

implementation

uses Windows, SysUtils, Classes, ActiveX, httpapi2,
  xxmPRegXml, xxmThreadPool, xxmHSysMain;

type
  THSysParameters=(
    hpPort,
    hpHostMask,
    hpSecurePort,
    hpThreads,
    //add new here above
    hp_Unknown);

const
  HSysParamNames:array[THSysParameters] of WideString=(
    'port',
    'host',
    'secureport',
    'threads',
    //add new here above
    ''
  );

procedure XxmRunHSys(HandleMessagesProc:TXxmHandleMessagesProc);
var
  i,j,l,Port,SecurePort,Threads:integer;
  s,t,Host:WideString;
  hp:THSysParameters;
  hrs:THTTP_SERVER_SESSION_ID;
  hrg:THTTP_URL_GROUP_ID;
  hrq:THTTP_BINDING_INFO;
  hrss:THTTP_STATE_INFO;
  QuitApp:boolean;

const
  certhash:array[0..19] of byte=(
  $45, $91 ,$88 ,$3d ,$be ,$81 ,$0a ,$0e ,$91 ,$7b ,
  $ab ,$a6 ,$87 ,$40 ,$1b ,$d8 ,$9c ,$1d ,$f6 ,$d2 );

begin
  CoInitialize(nil);
  QuitApp:=false;

  HttpCheck(HttpInitialize(HTTPAPI_VERSION_2_0,HTTP_INITIALIZE_SERVER,nil));
  HttpCheck(HttpCreateServerSession(HTTPAPI_VERSION_2_0,hrs,0));
  HttpCheck(HttpCreateUrlGroup(hrs,hrg,0));

  //defaults
  Port:=80;
  SecurePort:=0;//443;
  Host:='+';
  Threads:=$100;

  for i:=1 to ParamCount do
   begin
    s:=ParamStr(i);
    l:=Length(s);
    j:=1;
    while (j<=l) and (s[j]<>'=') do inc(j);
    if (j<=l) then
     begin
      t:=LowerCase(Copy(s,1,j-1));
      s:=Copy(s,j+1,l-j);
      hp:=Low(THSysParameters);
      while (hp<>hp_Unknown) and (HSysParamNames[hp]<>t) do inc(hp);
      case hp of

        hpPort:
          Port:=StrToInt(s);
        hpHostMask:
          Host:=s;
        hpSecurePort: //see also http://msdn.microsoft.com/en-us/library/ms733791.aspx
          if s='' then SecurePort:=443 else SecurePort:=StrToInt(s);
        hpThreads:
          Threads:=StrToInt(s);

        //add new here above
        else raise Exception.Create('Unknown parameter "'+t+'"');
      end;
     end
    else
     begin

      if Port<>0 then
       begin
        s:='http://'+Host+':'+IntToStr(Port)+'/'+s+'/';
        HttpCheck(HttpAddUrlToUrlGroup(hrg,PWideChar(s),0,0));
       end;
      if SecurePort<>0 then
       begin
        s:='https://'+Host+':'+IntToStr(SecurePort)+'/'+s+'/';
        HttpCheck(HttpAddUrlToUrlGroup(hrg,PWideChar(s),0,0));
       end;

     end;
   end;
  //TODO: check any loaded? load from xxm.xml?

  XxmProjectCache:=TXxmProjectCacheXml.Create;
  PageLoaderPool:=TXxmPageLoaderPool.Create(Threads);

  hrq.Flags:=HTTP_PROPERTY_FLAG_PRESENT;
  HttpCheck(HttpCreateRequestQueue(HTTPAPI_VERSION_2_0,nil,nil,0,hrq.RequestQueueHandle));
  HttpCheck(HttpSetUrlGroupProperty(hrg,HttpServerBindingProperty,@hrq,SizeOf(hrq)));

  hrss.Flags:=HTTP_PROPERTY_FLAG_PRESENT;
  hrss.State:=HttpEnabledStateActive;
  HttpCheck(HttpSetUrlGroupProperty(hrg,HttpServerStateProperty,@hrss,SizeOf(hrss)));

  //TODO: try except
  //TODO: mutex?
  //TODO: overlapped/completionport
  while not QuitApp do
   begin
    //if WaitForSingleObject(hrq,0)=WAIT_OBJECT_0 then ???
      PageLoaderPool.Queue(TXxmHSys1Context.Create(hrq.RequestQueueHandle));
    HandleMessagesProc(QuitApp);
   end;

  HttpCloseRequestQueue(hrq.RequestQueueHandle);
  HttpCloseUrlGroup(hrg);
  HttpCloseServerSession(hrs);
  HttpTerminate(HTTP_INITIALIZE_SERVER,nil);
end;

procedure HandleWindowsMessages(var QuitApp:boolean);
var
  Msg:TMsg;
const
  WM_QUIT = $0012;//from Messages
begin
  if PeekMessage(Msg,0,0,0,PM_REMOVE) then
    if Msg.message=WM_QUIT then
      QuitApp:=true
    else
     begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
     end
  else
    Sleep(1);//don't take 100% CPU!
end;

end.
