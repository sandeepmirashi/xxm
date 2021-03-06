unit xxmp;

{
  xxm Project

This is a default xxm Project class inheriting from TXxmProject. You are free to change this one for your project.
Use LoadPage to process URL's as a requests is about to start.
(Be carefull with sending content from here though.)
It is advised to link each request to a session here, if you want session management.
(See  an example xxmSession.pas in the public folder.)
Use LoadFragment to handle calls made to Context.Include.

  $Rev: 102 $ $Date: 2010-09-15 14:42:45 +0200 (wo, 15 sep 2010) $
}

interface

uses xxm;

type
  TXxm[[ProjectName]]=class(TXxmProject)
  public
    function LoadPage(Context: IXxmContext; Address: WideString): IXxmFragment; override;
    function LoadFragment(Context: IXxmContext; Address, RelativeTo: WideString): IXxmFragment; override;
    procedure UnloadFragment(Fragment: IXxmFragment); override;
  end;

function XxmProjectLoad(AProjectName:WideString): IXxmProject; stdcall;

implementation

uses xxmFReg;

function XxmProjectLoad(AProjectName:WideString): IXxmProject;
begin
  Result:=TXxm[[ProjectName]].Create(AProjectName);
end;

{ TXxm[[ProjectName]] }

function TXxm[[ProjectName]].LoadPage(Context: IXxmContext; Address: WideString): IXxmFragment;
begin
  inherited;
  //TODO: link session to request
  Result:=XxmFragmentRegistry.GetFragment(Self,Address,'');
end;

function TXxm[[ProjectName]].LoadFragment(Context: IXxmContext; Address, RelativeTo: WideString): IXxmFragment;
begin
  Result:=XxmFragmentRegistry.GetFragment(Self,Address,RelativeTo);
end;

procedure TXxm[[ProjectName]].UnloadFragment(Fragment: IXxmFragment);
begin
  inherited;
  //TODO: set cache TTL, decrease ref count
  //Fragment.Free;
end;

initialization
  IsMultiThread:=true;
end.
