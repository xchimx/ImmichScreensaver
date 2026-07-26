unit uConfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  // How an image is drawn onto the screen
  TFitMode = (fmCover, fmFit, fmStretch);

  // Position of the clock/date overlay
  TClockHAlign = (chLeft, chRight);
  TClockVAlign = (cvTop, cvBottom);

  { TAppConfig - holds all settings and loads/saves them as an INI file }
  TAppConfig = class
  public
    Server: string;           // Immich server URL (without trailing slash)
    APIKey: string;
    IntervalMs: Integer;      // time between image changes
    RandomOrder: Boolean;
    AlbumIds: TStringList;    // selected album ids (empty = whole library)
    Monitors: TStringList;    // selected monitor indices (empty = all)
    FitMode: TFitMode;
    UseOriginal: Boolean;     // load full resolution instead of the preview
    FadeEnabled: Boolean;
    FadeDurationMs: Integer;
    ShowClock: Boolean;
    ClockH: TClockHAlign;
    ClockV: TClockVAlign;
    constructor Create;
    destructor Destroy; override;
    procedure SetDefaults;
    procedure Load;
    procedure Save;
    function ConfigFilePath: string;
    function UseAllAlbums: Boolean;
    function UseAllMonitors: Boolean;
    function MonitorSelected(AIndex: Integer): Boolean;
  end;

function FitModeToStr(M: TFitMode): string;
function StrToFitMode(const S: string): TFitMode;
function ClockHToStr(A: TClockHAlign): string;
function StrToClockH(const S: string): TClockHAlign;
function ClockVToStr(A: TClockVAlign): string;
function StrToClockV(const S: string): TClockVAlign;

implementation

uses
  IniFiles;

const
  SEC_IMMICH = 'Immich';
  SEC_SETTINGS = 'Settings';

  MIN_FADE_MS = 100;
  MAX_FADE_MS = 5000;
  MIN_INTERVAL_MS = 1000;

function FitModeToStr(M: TFitMode): string;
begin
  case M of
    fmFit: Result := 'fit';
    fmStretch: Result := 'stretch';
  else
    Result := 'cover';
  end;
end;

function StrToFitMode(const S: string): TFitMode;
var
  L: string;
begin
  L := LowerCase(Trim(S));
  if L = 'fit' then
    Result := fmFit
  else if L = 'stretch' then
    Result := fmStretch
  else
    Result := fmCover;
end;

function ClockHToStr(A: TClockHAlign): string;
begin
  if A = chLeft then
    Result := 'left'
  else
    Result := 'right';
end;

function StrToClockH(const S: string): TClockHAlign;
begin
  if LowerCase(Trim(S)) = 'left' then
    Result := chLeft
  else
    Result := chRight;
end;

function ClockVToStr(A: TClockVAlign): string;
begin
  if A = cvTop then
    Result := 'top'
  else
    Result := 'bottom';
end;

function StrToClockV(const S: string): TClockVAlign;
begin
  if LowerCase(Trim(S)) = 'top' then
    Result := cvTop
  else
    Result := cvBottom;
end;

{ TAppConfig }

constructor TAppConfig.Create;
begin
  inherited Create;
  AlbumIds := TStringList.Create;
  AlbumIds.Delimiter := ',';
  AlbumIds.StrictDelimiter := True;
  Monitors := TStringList.Create;
  Monitors.Delimiter := ',';
  Monitors.StrictDelimiter := True;
  SetDefaults;
end;

destructor TAppConfig.Destroy;
begin
  AlbumIds.Free;
  Monitors.Free;
  inherited Destroy;
end;

procedure TAppConfig.SetDefaults;
begin
  Server := 'https://demo.immich.app';
  APIKey := '';
  IntervalMs := 8000;
  RandomOrder := True;
  AlbumIds.Clear;
  Monitors.Clear;
  FitMode := fmCover;
  UseOriginal := False;
  FadeEnabled := True;
  FadeDurationMs := 450;
  ShowClock := True;
  ClockH := chRight;
  ClockV := cvBottom;
end;

function TAppConfig.ConfigFilePath: string;
var
  Dir: string;
begin
  Dir := GetEnvironmentVariable('APPDATA') + PathDelim + 'ImmichScreensaver';
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);
  Result := Dir + PathDelim + 'immich_config.ini';
end;

procedure TAppConfig.Load;
var
  Ini: TIniFile;
  CfgFile: string;
begin
  SetDefaults;
  CfgFile := ConfigFilePath;
  if not FileExists(CfgFile) then
  begin
    Save;
    Exit;
  end;

  Ini := TIniFile.Create(CfgFile);
  try
    Server := Ini.ReadString(SEC_IMMICH, 'Server', Server);
    APIKey := Ini.ReadString(SEC_IMMICH, 'APIKey', APIKey);
    IntervalMs := Ini.ReadInteger(SEC_IMMICH, 'Interval', IntervalMs);
    if IntervalMs < MIN_INTERVAL_MS then
      IntervalMs := MIN_INTERVAL_MS;

    RandomOrder := Ini.ReadBool(SEC_SETTINGS, 'Random', RandomOrder);
    UseOriginal := Ini.ReadBool(SEC_SETTINGS, 'UseOriginal', UseOriginal);
    FitMode := StrToFitMode(Ini.ReadString(SEC_SETTINGS, 'FitMode', FitModeToStr(FitMode)));

    FadeEnabled := Ini.ReadBool(SEC_SETTINGS, 'Fade', FadeEnabled);
    FadeDurationMs := Ini.ReadInteger(SEC_SETTINGS, 'FadeDuration', FadeDurationMs);
    if FadeDurationMs < MIN_FADE_MS then
      FadeDurationMs := MIN_FADE_MS;
    if FadeDurationMs > MAX_FADE_MS then
      FadeDurationMs := MAX_FADE_MS;

    ShowClock := Ini.ReadBool(SEC_SETTINGS, 'Clock', ShowClock);
    ClockH := StrToClockH(Ini.ReadString(SEC_SETTINGS, 'ClockHAlign', ClockHToStr(ClockH)));
    ClockV := StrToClockV(Ini.ReadString(SEC_SETTINGS, 'ClockVAlign', ClockVToStr(ClockV)));

    AlbumIds.DelimitedText := Ini.ReadString(SEC_SETTINGS, 'Albums', '');
    Monitors.DelimitedText := Ini.ReadString(SEC_SETTINGS, 'Monitors', '');
  finally
    Ini.Free;
  end;
end;

procedure TAppConfig.Save;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ConfigFilePath);
  try
    Ini.WriteString(SEC_IMMICH, 'Server', Server);
    Ini.WriteString(SEC_IMMICH, 'APIKey', APIKey);
    Ini.WriteInteger(SEC_IMMICH, 'Interval', IntervalMs);

    Ini.WriteBool(SEC_SETTINGS, 'Random', RandomOrder);
    Ini.WriteBool(SEC_SETTINGS, 'UseOriginal', UseOriginal);
    Ini.WriteString(SEC_SETTINGS, 'FitMode', FitModeToStr(FitMode));
    Ini.WriteBool(SEC_SETTINGS, 'Fade', FadeEnabled);
    Ini.WriteInteger(SEC_SETTINGS, 'FadeDuration', FadeDurationMs);
    Ini.WriteBool(SEC_SETTINGS, 'Clock', ShowClock);
    Ini.WriteString(SEC_SETTINGS, 'ClockHAlign', ClockHToStr(ClockH));
    Ini.WriteString(SEC_SETTINGS, 'ClockVAlign', ClockVToStr(ClockV));
    Ini.WriteString(SEC_SETTINGS, 'Albums', AlbumIds.DelimitedText);
    Ini.WriteString(SEC_SETTINGS, 'Monitors', Monitors.DelimitedText);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

function TAppConfig.UseAllAlbums: Boolean;
begin
  Result := AlbumIds.Count = 0;
end;

function TAppConfig.UseAllMonitors: Boolean;
begin
  Result := Monitors.Count = 0;
end;

function TAppConfig.MonitorSelected(AIndex: Integer): Boolean;
begin
  Result := UseAllMonitors or (Monitors.IndexOf(IntToStr(AIndex)) >= 0);
end;

end.
