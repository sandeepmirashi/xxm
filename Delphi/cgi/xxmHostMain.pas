unit xxmHostMain;

interface

uses
  SysUtils, ActiveX, xxm, Classes, xxmContext, xxmThreadPool,
  xxmPReg, xxmPRegXml, xxmParams, xxmParUtils, xxmHeaders;

type
  TXxmPostDataStream=class(TCustomMemoryStream)
  private
    FInput:THandle;
    FInputRead,FInputSize:cardinal;
  public
    constructor Create(Input:THandle;InputSize:cardinal);
    destructor Destroy; override;
    function Write(const Buffer; Count: Integer): Integer; override;
    function Read(var Buffer; Count: Integer): Integer; override;
    procedure SetSize(NewSize: Integer); override;
  end;

  TXxmHostedContext=class(TXxmQueueContext, IxxmHttpHeaders)
  private
    FPipeIn,FPipeOut:THandle;
    FCGIValues:array of record
      Name,Value:AnsiString;
    end;
    FCGIValuesSize,FCGIValuesCount:integer;
    FReqHeaders:TRequestHeaders;
    FResHeaders:TResponseHeaders;
    FConnected:boolean;
    FURI,FRedirectPrefix,FSessionID:AnsiString;
    FCookieParsed: boolean;
    FCookie: AnsiString;
    FCookieIdx: TParamIndexes;
    FQueryStringIndex:integer;
    function GetCGIValue(Name:AnsiString):AnsiString;
  protected
    function SendData(const Buffer; Count: LongInt): LongInt;
    procedure DispositionAttach(FileName: WideString); override;
    function ContextString(cs:TXxmContextString):WideString; override;
    procedure Redirect(RedirectURL:WideString; Relative:boolean); override;
    function Connected:boolean; override;
    function GetSessionID:WideString; override;
    procedure SendHeader; override;
    function GetCookie(Name:WideString):WideString; override;

    function GetProjectEntry:TXxmProjectEntry; override;
    function GetRequestHeader(const Name: WideString): WideString; override;
    procedure AddResponseHeader(const Name, Value: WideString); override;

    function GetRequestHeaders:IxxmDictionaryEx;
    function GetResponseHeaders:IxxmDictionaryEx;
  public
    Queue:TXxmHostedContext;

    constructor Create(PipeIn,PipeOut:THandle);
    destructor Destroy; override;

    procedure Execute; override;
  end;

  EXxmMaximumHeaderLines=class(Exception);
  EXxmContextStringUnknown=class(Exception);
  EXxmUnknownPostDataTymed=class(Exception);

implementation

uses Windows, Variants, ComObj, xxmCommonUtils;

resourcestring
  SXxmMaximumHeaderLines='Maximum header lines exceeded.';
  SXxmContextStringUnknown='Unknown ContextString __';

const
  HTTPMaxHeaderLines=$400;

{ TXxmHostedContext }

constructor TXxmHostedContext.Create(PipeIn,PipeOut:THandle);
begin
  inherited Create('');//empty here, see Execute
  Queue:=nil;//used by thread pool
  FPipeIn:=PipeIn;
  FPipeOut:=PipeOut;
  SendDirect:=SendData;
  FReqHeaders:=nil;
  FResHeaders:=TResponseHeaders.Create;
  (FResHeaders as IUnknown)._AddRef;
  FConnected:=true;
  FCookieParsed:=false;
  FQueryStringIndex:=1;
  FSessionID:='';//see GetSessionID
  FRedirectPrefix:='';
  FCGIValuesSize:=0;
  FCGIValuesCount:=0;
end;

destructor TXxmHostedContext.Destroy;
begin
  FlushFileBuffers(FPipeOut);
  CloseHandle(FPipeIn);
  CloseHandle(FPipeOut);
  if FReqHeaders<>nil then
   begin
    (FReqHeaders as IUnknown)._Release;
    FReqHeaders:=nil;
   end;
  if FResHeaders<>nil then
   begin
    (FResHeaders as IUnknown)._Release;
    FResHeaders:=nil;
   end;
  SetLength(FCGIValues,0);
  inherited;
end;

procedure TXxmHostedContext.Execute;
var
  i,j,k,l,m:integer;
  l1:cardinal;
  x,y:AnsiString;
const
  CGIValuesGrowStep=$100;
begin
  try
    //read CGI values
    if not(ReadFile(FPipeIn,l,4,l1,nil)) then RaiseLastOSError;
    SetLength(x,l);
    if not(ReadFile(FPipeIn,x[1],l,l1,nil)) then RaiseLastOSError;
    //process values
    i:=1;
    m:=0;
    while (i<l) do
     begin
      j:=i;
      while (j<=l) and (x[j]<>'=') do inc(j);
      k:=j+1;
      while (k<=l) and (x[k]<>#0) do inc(k);
      if (j-i>4) and (Copy(x,i,5)='HTTP_') then
       begin
        y:=y+x[i+5]+LowerCase(StringReplace(Copy(x,i+6,j-i-6),'_','-',[rfReplaceAll]))+': '+Copy(x,j+1,k-j-1)+#13#10;
       end
      else
        if j<=l then
         begin
          if FCGIValuesCount=FCGIValuesSize then
           begin
            inc(FCGIValuesSize,CGIValuesGrowStep);
            SetLength(FCGIValues,FCGIValuesSize);
           end;
          FCGIValues[FCGIValuesCount].Name:=Copy(x,i,j-i);
          FCGIValues[FCGIValuesCount].Value:=Copy(x,j+1,k-j-1);
          inc(FCGIValuesCount);
         end;
      i:=k+1;
      inc(m);
      if m=HTTPMaxHeaderLines then
        raise EXxmMaximumHeaderLines.Create(SXxmMaximumHeaderLines);
     end;
    y:=y+#13#10;

    FReqHeaders:=TRequestHeaders.Create(y);
    (FReqHeaders as IUnknown)._AddRef;

    x:=GetCGIValue('SERVER_PROTOCOL');//http or https
    i:=1;
    l:=Length(x);
    while (i<=l) and (x[i]<>'/') do inc(i);
    y:=FReqHeaders['Host'];
    if y='' then y:='localhost';//if not port=80 then +':'+?
    FRedirectPrefix:=LowerCase(Copy(x,1,i-1))+'://'+y;

    x:=GetCGIValue('SCRIPT_NAME');
    y:=GetCGIValue('REQUEST_URI');
    l:=Length(x);
    if x=Copy(y,1,l) then
     begin
      FURI:=Copy(y,l+1,Length(y)-l);
      FRedirectPrefix:=FRedirectPrefix+x;
     end
    else
     begin
      FURI:=y;
      //FURLPrefix:= should be ok
     end;

    FURL:=FRedirectPrefix+FURI;
     
    //'Authorization' ?
    //'If-Modified-Since' ? 304
    //'Connection: Keep-alive' ? with sent Content-Length

    FResHeaders['X-Powered-By']:=SelfVersion;
    //if XxmProjectCache=nil then XxmProjectCache:=TXxmProjectCacheXml.Create;

    FQueryStringIndex:=2;
    if XxmProjectCache.ProjectFromURI(Self,
      FURI,FQueryStringIndex,FProjectName,FFragmentName) then
      FRedirectPrefix:=FRedirectPrefix+'/'+FProjectName;
    FPageClass:='['+FProjectName+']';

    //assert headers read and parsed
    //TODO: HTTP/1.1 100 Continue?

    //if Verb<>'GET' then?
    x:=GetCGIValue('CONTENT_LENGTH');
    if x<>'' then FPostData:=TXxmPostDataStream.Create(FPipeIn,StrToInt(x));

    BuildPage;

  except
    on EXxmPageRedirected do
      Flush;
    on EXxmAutoBuildFailed do
      ;//assert output done
    on e:Exception do
      if not HandleException(e) then
       begin
        ForceStatus(500,'Internal Server Error');//TODO:setting?
        try
          if FPostData=nil then x:='none' else x:=IntToStr(FPostData.Size)+' bytes';
        except
          x:='unknown';
        end;
        SendError('error',[
          'ERRORCLASS',e.ClassName,
          'ERROR',HTMLEncode(e.Message),
          'CLASS',FPageClass,
          'URL',HTMLEncode(ContextString(csURL)),
          'POSTDATA',x,
          'QUERYSTRING',HTMLEncode(ContextString(csQueryString)),
          'VERSION',ContextString(csVersion)
        ]);
       end;
  end;
end;

function TXxmHostedContext.GetProjectEntry: TXxmProjectEntry;
begin
  Result:=XxmProjectCache.GetProject(FProjectName);
end;

function TXxmHostedContext.Connected: boolean;
begin
  Result:=FConnected;
  //TODO: set to false when client disconnect
end;

function TXxmHostedContext.ContextString(cs: TXxmContextString): WideString;
begin
  case cs of
    csVersion:Result:=SelfVersion+' '+GetCGIValue('SERVER_SOFTWARE');
    csExtraInfo:Result:='';//???
    csVerb:Result:=GetCGIValue('REQUEST_METHOD');
    csQueryString:Result:=Copy(FURI,FQueryStringIndex,Length(FURI)-FQueryStringIndex+1);
    csUserAgent:Result:=FReqHeaders['User-Agent'];
    csAcceptedMimeTypes:Result:=FReqHeaders['Accept'];//TODO:
    csPostMimeType:Result:=GetCGIValue('CONTENT_TYPE');//TODO:
    csURL:Result:=GetURL;
    csProjectName:Result:=FProjectName;
    csLocalURL:Result:=FFragmentName;
    csReferer:Result:=FReqHeaders['Referer'];
    csLanguage:Result:=FReqHeaders['Accept-Language'];
    csRemoteAddress:Result:=GetCGIValue('REMOTE_ADDR');
    csRemoteHost:Result:=GetCGIValue('REMOTE_HOST');
    csAuthUser:Result:=GetCGIValue('AUTH_USER');
    csAuthPassword:Result:=GetCGIValue('AUTH_PASSWORD');
    else
      raise EXxmContextStringUnknown.Create(StringReplace(
        SXxmContextStringUnknown,'__',IntToHex(integer(cs),8),[]));
  end;
end;

procedure TXxmHostedContext.DispositionAttach(FileName: WideString);
begin
  FResHeaders.SetComplex('Content-disposition','attachment')
    ['filename']:=FileName;
end;

function TXxmHostedContext.GetCookie(Name: WideString): WideString;
begin
  if not(FCookieParsed) then
   begin
    FCookie:=FReqHeaders['Cookie'];
    SplitHeaderValue(FCookie,0,Length(FCookie),FCookieIdx);
    FCookieParsed:=true;
   end;
  Result:=GetParamValue(FCookie,FCookieIdx,Name);
end;

function TXxmHostedContext.GetSessionID: WideString;
const
  SessionCookie='xxmSessionID';
begin
  if FSessionID='' then
   begin
    FSessionID:=GetCookie(SessionCookie);
    if FSessionID='' then
     begin
      FSessionID:=Copy(CreateClassID,2,32);
      SetCookie(SessionCookie,FSessionID);//expiry?
     end;
   end;
  Result:=FSessionID;
end;

procedure TXxmHostedContext.Redirect(RedirectURL: WideString;
  Relative: boolean);
var
  NewURL,RedirBody:WideString;
begin
  //inherited;
  SetStatus(301,'Moved Permanently');//does CheckHeaderNotSent;
  //TODO: move this to execute's except?
  NewURL:=RedirectURL;
  if Relative and (NewURL<>'') and (NewURL[1]='/') then NewURL:=FRedirectPrefix+NewURL;
  RedirBody:='<a href="'+HTMLEncode(NewURL)+'">'+HTMLEncode(NewURL)+'</a>'#13#10;
  FResHeaders['Location']:=NewURL;
  case FAutoEncoding of
    aeUtf8:FResHeaders['Content-Length']:=IntToStr(Length(UTF8Encode(RedirBody))+3);
    aeUtf16:FResHeaders['Content-Length']:=IntToStr(Length(RedirBody)*2+2);
    aeIso8859:FResHeaders['Content-Length']:=IntToStr(Length(AnsiString(RedirBody)));
  end;
  SendStr(RedirBody);
  if BufferSize<>0 then Flush;
  raise EXxmPageRedirected.Create(RedirectURL);
end;

function TXxmHostedContext.SendData(const Buffer; Count: LongInt): LongInt;
begin
  if Count=0 then Result:=0 else
   begin
    Result:=Count;
    if not WriteFile(FPipeOut,Buffer,Count,cardinal(Result),nil) then
      raise EXxmTransferError.Create(SysErrorMessage(GetLastError));
   end;
end;

procedure TXxmHostedContext.SendHeader;
var
  x:AnsiString;
  i:integer;
  l:cardinal;
const
  AutoEncodingCharset:array[TXxmAutoEncoding] of string=(
    '',//aeContentDefined
    '; charset="utf-8"',
    '; charset="utf-16"',
    '; charset="iso-8859-15"'
  );
begin
  //TODO: Content-Length?
  //TODO: Connection keep?
  //use FResHeader.Complex?
  FResHeaders['Content-Type']:=FContentType+AutoEncodingCharset[FAutoEncoding];
  i:=StatusCode;
  WriteFile(FPipeOut,i,4,l,nil);
  x:=//GetCGIValue('SERVER_PROTOCOL')+' '+
    'Status: '+IntToStr(i)+' '+StatusText+#13#10+
    FResHeaders.Build+#13#10;
  WriteFile(FPipeOut,x[1],Length(x),l,nil);
  //clear buffer just in case
  if ContentBuffer<>nil then ContentBuffer.Position:=0;
end;

function TXxmHostedContext.GetRequestHeaders: IxxmDictionaryEx;
begin
  //assert FReqHeaders<>nil since parsed at start of Execute
  Result:=FReqHeaders;
end;

function TXxmHostedContext.GetResponseHeaders: IxxmDictionaryEx;
begin
  Result:=FResHeaders;
end;

function TXxmHostedContext.GetCGIValue(Name: AnsiString): AnsiString;
var
  i:integer;
begin
  i:=0;
  while (i<FCGIValuesCount) and (Name<>FCGIValues[i].Name) do inc(i); //TODO: case-insensitive?
  if i=FCGIValuesCount then Result:='' else Result:=FCGIValues[i].Value;
end;

function TXxmHostedContext.GetRequestHeader(const Name: WideString): WideString;
begin
  Result:=FReqHeaders.Item[Name];
end;

procedure TXxmHostedContext.AddResponseHeader(const Name, Value: WideString);
begin
  //inherited;?
  if SettingCookie then
   begin
    SettingCookie:=false;
    FResHeaders.Add(Name,Value);
   end
  else
    FResHeaders[Name]:=Value;
end;

{ TXxmPostDataStream }

constructor TXxmPostDataStream.Create(Input:THandle;InputSize:cardinal);
begin
  inherited Create;
  FInput:=Input;
  FInputRead:=0;
  FInputSize:=InputSize;
  SetPointer(GlobalAllocPtr(GMEM_MOVEABLE,FInputSize),FInputSize);
end;

destructor TXxmPostDataStream.Destroy;
begin
  GlobalFreePtr(Memory);
  inherited;
end;

function TXxmPostDataStream.Read(var Buffer; Count: Integer): Integer;
var
  l:cardinal;
  p:pointer;
begin
  l:=Position+Count;
  if l>FInputSize then l:=FInputSize;
  if l>FInputRead then
   begin
    dec(l,FInputRead);
    if l<>0 then
     begin
      p:=Memory;
      inc(cardinal(p),FInputRead);
      if not(ReadFile(FInput,p^,l,l,nil)) then RaiseLastOSError;
      inc(FInputRead,l);
     end;
   end;
  Result:=inherited Read(Buffer,Count);
end;

procedure TXxmPostDataStream.SetSize(NewSize: Integer);
begin
  raise Exception.Create('Post data is read-only.');
end;

function TXxmPostDataStream.Write(const Buffer; Count: Integer): Integer;
begin
  raise Exception.Create('Post data is read-only.');
end;

end.
