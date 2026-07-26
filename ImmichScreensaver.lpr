program ImmichScreensaver;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, uController, uConfig, uImmich, uProducer, uScreenWin, uSettings, uAbout;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title := 'Immich Screensaver';
  Application.Scaled := True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar := False;
  {$POP}
  Application.Initialize;
  // The main form is only an invisible controller
  Application.ShowMainForm := False;
  Application.CreateForm(TControllerForm, ControllerForm);
  Application.Run;
end.
