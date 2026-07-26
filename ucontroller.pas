unit uController;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Dialogs, ExtCtrls, LCLType, LCLIntf,
  LMessages, uConfig, uProducer, uScreenWin, uSettings;

type
  TRunMode = (rmScreensaver, rmConfig, rmPreview);

  { TControllerForm - invisible controller that drives the screensaver }
  TControllerForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FCfg: TAppConfig;
    FProducer: TImageProducer;
    FWindows: array of TScreenWindow;
    FTimer: TTimer;
    FStopping: Boolean;
    FCycling: Boolean;
    FInputHooked: Boolean;
    FStartTick: QWord;
    FMouseInit: Boolean;
    FMouseX, FMouseY: Integer;
    function DetectMode: TRunMode;
    procedure RunConfig;
    procedure StartScreensaver;
    procedure CreateWindows;
    procedure PrimeWindows;
    procedure CycleAll;
    procedure OnTimer(Sender: TObject);
    procedure HandleAppInput(Sender: TObject; Msg: Cardinal);
    procedure StopScreensaver;
    procedure StopProducer;
  public
  end;

var
  ControllerForm: TControllerForm;

implementation

{$R *.lfm}

uses
  StrUtils;

const
  INPUT_GRACE_MS = 900;   // ignore input right after the windows appear
  MOUSE_THRESHOLD = 8;    // pixels of movement that count as user activity

{ TControllerForm }

function TControllerForm.DetectMode: TRunMode;
var
  P: string;
begin
  // Windows .scr convention:
  //   /s          -> run screensaver (fullscreen)
  //   /p [HWND]   -> preview
  //   /c[:HWND]   -> configure
  //   no argument -> configure (the Explorer "Configure" verb passes none)
  if ParamCount < 1 then
    Exit(rmConfig);

  P := UpperCase(Trim(ParamStr(1)));
  if AnsiStartsStr('/S', P) then
    Result := rmScreensaver
  else if AnsiStartsStr('/P', P) then
    Result := rmPreview
  else
    Result := rmConfig;
end;

procedure TControllerForm.FormCreate(Sender: TObject);
begin
  FStopping := False;
  FCycling := False;
  FInputHooked := False;
  FCfg := TAppConfig.Create;
  FCfg.Load;

  case DetectMode of
    rmConfig:
      RunConfig;
    rmPreview:
      Application.Terminate; // preview window is not supported
    rmScreensaver:
      StartScreensaver;
  end;
end;

procedure TControllerForm.RunConfig;
var
  Dlg: TSettingsForm;
begin
  Dlg := TSettingsForm.CreateWithConfig(Self, FCfg);
  try
    Dlg.Execute;
  finally
    Dlg.Free;
  end;
  Application.Terminate;
end;

procedure TControllerForm.StartScreensaver;
var
  Capacity: Integer;
begin
  FStartTick := GetTickCount64;
  FMouseInit := False;

  CreateWindows;
  if Length(FWindows) = 0 then
  begin
    Application.Terminate;
    Exit;
  end;

  Screen.Cursor := crNone;
  Application.AddOnUserInputHandler(@HandleAppInput);
  FInputHooked := True;

  // A background thread downloads the images so the UI thread never blocks
  Capacity := 2 * Length(FWindows) + 4;
  FProducer := TImageProducer.Create(FCfg.Server, FCfg.APIKey, FCfg.UseOriginal,
    FCfg.RandomOrder, FCfg.AlbumIds, Capacity);
  FProducer.Start;

  PrimeWindows;
  if FStopping then
    Exit;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := FCfg.IntervalMs;
  FTimer.OnTimer := @OnTimer;
  FTimer.Enabled := True;
end;

procedure TControllerForm.CreateWindows;
var
  i: Integer;

  procedure AddWindow(MonIdx: Integer);
  var
    Win: TScreenWindow;
    n: Integer;
  begin
    Win := TScreenWindow.CreateForMonitor(Self, Screen.Monitors[MonIdx].BoundsRect,
             FCfg.FitMode, FCfg.FadeEnabled, FCfg.FadeDurationMs,
             FCfg.ShowClock, FCfg.ClockH, FCfg.ClockV);
    n := Length(FWindows);
    SetLength(FWindows, n + 1);
    FWindows[n] := Win;
    Win.Show;
  end;

begin
  SetLength(FWindows, 0);

  for i := 0 to Screen.MonitorCount - 1 do
    if FCfg.MonitorSelected(i) then
      AddWindow(i);

  // Fall back to every monitor if the selection matched nothing
  if Length(FWindows) = 0 then
    for i := 0 to Screen.MonitorCount - 1 do
      AddWindow(i);
end;

procedure TControllerForm.PrimeWindows;
var
  i, waited: Integer;
  s: TMemoryStream;
  anyShown: Boolean;
begin
  i := 0;
  waited := 0;
  anyShown := False;

  while (i <= High(FWindows)) and (not FStopping) do
  begin
    s := FProducer.PopImage;
    if s <> nil then
    begin
      try
        FWindows[i].ShowImageFromStream(s);
      finally
        s.Free;
      end;
      anyShown := True;
      Inc(i);
      waited := 0;
    end
    else
    begin
      if FProducer.NoImages and (not anyShown) then
        Break;
      Application.ProcessMessages;
      Sleep(20);
      Inc(waited, 20);
      // Once some monitors show an image, let the timer fill in the rest
      if anyShown and (waited > 2500) then
        Break;
      if (not anyShown) and (waited > 6000) then
        Break;
    end;
  end;

  if (not anyShown) and (not FStopping) then
  begin
    ShowMessage('No images found, or the server is unreachable.' + LineEnding +
                'Please check the configuration and API connection (run with /c).' + LineEnding +
                'Server: ' + FCfg.Server);
    Application.Terminate;
    FStopping := True;
  end;
end;

procedure TControllerForm.CycleAll;
var
  i: Integer;
  s: TMemoryStream;
  prepared: array of Boolean;
begin
  if FStopping or FCycling then
    Exit;
  FCycling := True;
  try
    SetLength(prepared, Length(FWindows));
    // Decode for every monitor first, then start all fades together so no
    // decoding stall can happen in the middle of a running fade
    for i := 0 to High(FWindows) do
    begin
      if FStopping then
        Exit;
      prepared[i] := False;
      s := FProducer.PopImage;
      if s <> nil then
      begin
        try
          FWindows[i].PrepareImageFromStream(s);
          prepared[i] := True;
        finally
          s.Free;
        end;
      end;
    end;
    for i := 0 to High(FWindows) do
      if prepared[i] then
        FWindows[i].BeginFade;
  finally
    FCycling := False;
  end;
end;

procedure TControllerForm.OnTimer(Sender: TObject);
begin
  if FStopping then
    Exit;
  CycleAll;
end;

procedure TControllerForm.HandleAppInput(Sender: TObject; Msg: Cardinal);
var
  P: TPoint;
begin
  if FStopping then
    Exit;
  if (GetTickCount64 - FStartTick) < INPUT_GRACE_MS then
    Exit;

  case Msg of
    LM_KEYDOWN, LM_SYSKEYDOWN, LM_CHAR,
    LM_LBUTTONDOWN, LM_RBUTTONDOWN, LM_MBUTTONDOWN,
    LM_LBUTTONDBLCLK, LM_MOUSEWHEEL:
      StopScreensaver;
    LM_MOUSEMOVE:
      begin
        P := Mouse.CursorPos;
        if not FMouseInit then
        begin
          FMouseInit := True;
          FMouseX := P.X;
          FMouseY := P.Y;
        end
        else if (Abs(P.X - FMouseX) > MOUSE_THRESHOLD) or
                (Abs(P.Y - FMouseY) > MOUSE_THRESHOLD) then
          StopScreensaver;
      end;
  end;
end;

procedure TControllerForm.StopProducer;
begin
  if Assigned(FProducer) then
  begin
    FProducer.Cancel; // aborts a running download so WaitFor returns quickly
    FProducer.WaitFor;
    FreeAndNil(FProducer);
  end;
end;

procedure TControllerForm.StopScreensaver;
begin
  if FStopping then
    Exit;
  FStopping := True;
  if Assigned(FTimer) then
    FTimer.Enabled := False;
  if FInputHooked then
  begin
    Application.RemoveOnUserInputHandler(@HandleAppInput);
    FInputHooked := False;
  end;
  Screen.Cursor := crDefault;
  Application.Terminate;
end;

procedure TControllerForm.FormDestroy(Sender: TObject);
begin
  if Assigned(FTimer) then
    FTimer.Enabled := False;
  if FInputHooked then
  begin
    Application.RemoveOnUserInputHandler(@HandleAppInput);
    FInputHooked := False;
  end;
  Screen.Cursor := crDefault;
  StopProducer;
  // FWindows are owned components and get freed automatically
  FreeAndNil(FCfg);
end;

end.
