library xxmIsapiAU;

{$R '..\common\xxmData.res' '..\common\xxmData.rc'}

uses
  SysUtils,
  Classes,
  isapi4 in 'isapi4.pas',
  xxm in '..\bin\public\xxm.pas',
  xxmIsapiMain in 'xxmIsapiMain.pas',
  xxmPReg in '..\common\xxmPReg.pas',
  xxmPRegXml in '..\common\xxmPRegXml.pas',
  xxmParams in '..\common\xxmParams.pas',
  xxmParUtils in '..\common\xxmParUtils.pas',
  xxmHeaders in '..\bin\public\xxmHeaders.pas',
  MSXML2_TLB in '..\common\MSXML2_TLB.pas',
  xxmCommonUtils in '..\common\xxmCommonUtils.pas',
  xxmContext in '..\common\xxmContext.pas',
  xxmIsapiStream in 'xxmIsapiStream.pas',
  xxmAutoUpdate in '..\common\xxmAutoUpdate.pas';

{$R *.res}

exports
  GetExtensionVersion,
  HttpExtensionProc,
  TerminateExtension;

begin
  XxmAutoBuildHandler:=AutoUpdate;
end.
