unit uSettings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, Spin, CheckLst,
  Dialogs, uConfig, uImmich, uAbout;

type
  { TSettingsForm - configuration dialog, built entirely in code }
  TSettingsForm = class(TForm)
  private
    FCfg: TAppConfig;
    FAlbumIds: TStringList; // parallel to clbAlbums.Items
    FShownOnce: Boolean;

    edtServer: TEdit;
    edtAPIKey: TEdit;
    chkShowKey: TCheckBox;
    btnTest: TButton;
    spinInterval: TSpinEdit;
    chkRandom: TCheckBox;
    cmbFit: TComboBox;
    chkOriginal: TCheckBox;
    chkFade: TCheckBox;
    spinFade: TSpinEdit;
    chkClock: TCheckBox;
    cmbClockH: TComboBox;
    cmbClockV: TComboBox;
    clbAlbums: TCheckListBox;
    clbMonitors: TCheckListBox;
    btnLoadAlbums: TButton;
    btnAbout: TButton;
    btnSave: TButton;
    btnCancel: TButton;

    procedure BuildUI;
    procedure LoadMonitors;
    procedure LoadAlbumsFromServer(ShowErrors: Boolean);
    procedure ApplyConfigToUI;
    procedure SaveUIToConfig;

    procedure DoFormShow(Sender: TObject);
    procedure DoTestClick(Sender: TObject);
    procedure DoShowKeyClick(Sender: TObject);
    procedure DoLoadAlbumsClick(Sender: TObject);
    procedure DoAboutClick(Sender: TObject);
    procedure DoSaveClick(Sender: TObject);
    procedure DoCancelClick(Sender: TObject);
  public
    constructor CreateWithConfig(AOwner: TComponent; ACfg: TAppConfig);
    destructor Destroy; override;
    // True when the user saved
    function Execute: Boolean;
  end;

implementation

function AddLabel(AParent: TWinControl; ALeft, ATop: Integer; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Caption := ACaption;
end;

constructor TSettingsForm.CreateWithConfig(AOwner: TComponent; ACfg: TAppConfig);
begin
  inherited CreateNew(AOwner);
  FCfg := ACfg;
  FShownOnce := False;
  FAlbumIds := TStringList.Create;
  BuildUI;
  ApplyConfigToUI;
  OnShow := @DoFormShow;
end;

destructor TSettingsForm.Destroy;
begin
  FAlbumIds.Free;
  inherited Destroy;
end;

procedure TSettingsForm.BuildUI;
begin
  Caption := 'Immich Screensaver - Settings';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 720;
  ClientHeight := 610;
  Color := clBtnFace;

  AddLabel(Self, 16, 12, 'Immich Screensaver').Font.Style := [fsBold];

  // --- Left column: connection and playback ---
  AddLabel(Self, 16, 44, 'Immich server URL:');
  edtServer := TEdit.Create(Self);
  edtServer.Parent := Self;
  edtServer.SetBounds(16, 62, 340, 26);

  AddLabel(Self, 16, 94, 'API key:');
  edtAPIKey := TEdit.Create(Self);
  edtAPIKey.Parent := Self;
  edtAPIKey.SetBounds(16, 112, 340, 26);
  edtAPIKey.PasswordChar := '*';

  chkShowKey := TCheckBox.Create(Self);
  chkShowKey.Parent := Self;
  chkShowKey.SetBounds(16, 142, 160, 22);
  chkShowKey.Caption := 'Show key';
  chkShowKey.OnClick := @DoShowKeyClick;

  btnTest := TButton.Create(Self);
  btnTest.Parent := Self;
  btnTest.SetBounds(196, 140, 160, 26);
  btnTest.Caption := 'Test connection';
  btnTest.OnClick := @DoTestClick;

  AddLabel(Self, 16, 176, 'Time between images (seconds):');
  spinInterval := TSpinEdit.Create(Self);
  spinInterval.Parent := Self;
  spinInterval.SetBounds(16, 194, 100, 26);
  spinInterval.MinValue := 1;
  spinInterval.MaxValue := 600;

  chkRandom := TCheckBox.Create(Self);
  chkRandom.Parent := Self;
  chkRandom.SetBounds(16, 230, 320, 22);
  chkRandom.Caption := 'Random order';

  AddLabel(Self, 16, 262, 'Display mode:');
  cmbFit := TComboBox.Create(Self);
  cmbFit.Parent := Self;
  cmbFit.SetBounds(16, 280, 200, 26);
  cmbFit.Style := csDropDownList;
  cmbFit.Items.Add('Fill (crop)');
  cmbFit.Items.Add('Fit (letterbox)');
  cmbFit.Items.Add('Stretch (distort)');

  chkOriginal := TCheckBox.Create(Self);
  chkOriginal.Parent := Self;
  chkOriginal.SetBounds(16, 314, 340, 22);
  chkOriginal.Caption := 'Load full resolution (slower)';

  chkFade := TCheckBox.Create(Self);
  chkFade.Parent := Self;
  chkFade.SetBounds(16, 346, 340, 22);
  chkFade.Caption := 'Smooth crossfade between images';

  AddLabel(Self, 16, 376, 'Crossfade duration (ms):');
  spinFade := TSpinEdit.Create(Self);
  spinFade.Parent := Self;
  spinFade.SetBounds(180, 372, 100, 26);
  spinFade.MinValue := 100;
  spinFade.MaxValue := 5000;

  chkClock := TCheckBox.Create(Self);
  chkClock.Parent := Self;
  chkClock.SetBounds(16, 408, 340, 22);
  chkClock.Caption := 'Show clock and date';

  AddLabel(Self, 16, 438, 'Clock position:');
  cmbClockH := TComboBox.Create(Self);
  cmbClockH.Parent := Self;
  cmbClockH.SetBounds(16, 456, 150, 26);
  cmbClockH.Style := csDropDownList;
  cmbClockH.Items.Add('Left');
  cmbClockH.Items.Add('Right');
  cmbClockV := TComboBox.Create(Self);
  cmbClockV.Parent := Self;
  cmbClockV.SetBounds(176, 456, 150, 26);
  cmbClockV.Style := csDropDownList;
  cmbClockV.Items.Add('Top');
  cmbClockV.Items.Add('Bottom');

  // --- Right column: albums and monitors ---
  AddLabel(Self, 372, 44, 'Albums (image source):');
  btnLoadAlbums := TButton.Create(Self);
  btnLoadAlbums.Parent := Self;
  btnLoadAlbums.SetBounds(372, 62, 160, 26);
  btnLoadAlbums.Caption := 'Load albums';
  btnLoadAlbums.OnClick := @DoLoadAlbumsClick;

  clbAlbums := TCheckListBox.Create(Self);
  clbAlbums.Parent := Self;
  clbAlbums.SetBounds(372, 96, 332, 250);
  AddLabel(Self, 372, 350, 'Nothing checked = use the whole library').Font.Color := clGrayText;

  AddLabel(Self, 372, 382, 'Monitors:');
  clbMonitors := TCheckListBox.Create(Self);
  clbMonitors.Parent := Self;
  clbMonitors.SetBounds(372, 400, 332, 120);
  AddLabel(Self, 372, 524, 'Nothing checked = use all monitors').Font.Color := clGrayText;

  // --- Buttons ---
  btnAbout := TButton.Create(Self);
  btnAbout.Parent := Self;
  btnAbout.SetBounds(16, 566, 90, 28);
  btnAbout.Caption := 'About';
  btnAbout.OnClick := @DoAboutClick;

  btnSave := TButton.Create(Self);
  btnSave.Parent := Self;
  btnSave.SetBounds(508, 566, 90, 28);
  btnSave.Caption := 'Save';
  btnSave.Default := True;
  btnSave.OnClick := @DoSaveClick;

  btnCancel := TButton.Create(Self);
  btnCancel.Parent := Self;
  btnCancel.SetBounds(614, 566, 90, 28);
  btnCancel.Caption := 'Cancel';
  btnCancel.Cancel := True;
  btnCancel.OnClick := @DoCancelClick;
end;

procedure TSettingsForm.LoadMonitors;
var
  i: Integer;
  Cap: string;
begin
  clbMonitors.Items.Clear;
  for i := 0 to Screen.MonitorCount - 1 do
  begin
    Cap := Format('Monitor %d  (%dx%d)', [i + 1,
      Screen.Monitors[i].Width, Screen.Monitors[i].Height]);
    if Screen.Monitors[i].Primary then
      Cap := Cap + '  [primary]';
    clbMonitors.Items.Add(Cap);
  end;
end;

procedure TSettingsForm.ApplyConfigToUI;
var
  i: Integer;
  AllMonitors: Boolean;
begin
  edtServer.Text := FCfg.Server;
  edtAPIKey.Text := FCfg.APIKey;
  spinInterval.Value := FCfg.IntervalMs div 1000;
  chkRandom.Checked := FCfg.RandomOrder;
  chkOriginal.Checked := FCfg.UseOriginal;
  chkFade.Checked := FCfg.FadeEnabled;
  spinFade.Value := FCfg.FadeDurationMs;
  chkClock.Checked := FCfg.ShowClock;
  case FCfg.FitMode of
    fmCover: cmbFit.ItemIndex := 0;
    fmFit: cmbFit.ItemIndex := 1;
    fmStretch: cmbFit.ItemIndex := 2;
  end;
  if FCfg.ClockH = chLeft then
    cmbClockH.ItemIndex := 0
  else
    cmbClockH.ItemIndex := 1;
  if FCfg.ClockV = cvTop then
    cmbClockV.ItemIndex := 0
  else
    cmbClockV.ItemIndex := 1;

  LoadMonitors;
  AllMonitors := FCfg.UseAllMonitors;
  for i := 0 to clbMonitors.Items.Count - 1 do
    clbMonitors.Checked[i] := AllMonitors or FCfg.MonitorSelected(i);
end;

procedure TSettingsForm.LoadAlbumsFromServer(ShowErrors: Boolean);
var
  Client: TImmichClient;
  Names: TStringList;
  i: Integer;
begin
  if (Trim(edtServer.Text) = '') or (Trim(edtAPIKey.Text) = '') then
  begin
    if ShowErrors then
      ShowMessage('Please enter the server URL and API key first.');
    Exit;
  end;

  Names := TStringList.Create;
  Client := TImmichClient.Create(edtServer.Text, edtAPIKey.Text);
  Screen.Cursor := crHourGlass;
  try
    try
      Client.GetAlbums(Names, FAlbumIds);
      clbAlbums.Items.Assign(Names);
      for i := 0 to FAlbumIds.Count - 1 do
        clbAlbums.Checked[i] := FCfg.AlbumIds.IndexOf(FAlbumIds[i]) >= 0;
      if (clbAlbums.Items.Count = 0) and ShowErrors then
        ShowMessage('No albums found.');
    except
      on E: Exception do
        if ShowErrors then
          ShowMessage('Could not load albums:' + LineEnding + E.Message);
    end;
  finally
    Screen.Cursor := crDefault;
    Client.Free;
    Names.Free;
  end;
end;

procedure TSettingsForm.DoFormShow(Sender: TObject);
begin
  // Load the albums on first show so the saved selection is visible. Errors are
  // ignored here (server may be offline); the save guard keeps the selection.
  if FShownOnce then
    Exit;
  FShownOnce := True;
  if (Trim(edtServer.Text) <> '') and (Trim(edtAPIKey.Text) <> '') then
    LoadAlbumsFromServer(False);
end;

procedure TSettingsForm.SaveUIToConfig;
var
  i, CheckedMonitors: Integer;
begin
  FCfg.Server := Trim(edtServer.Text);
  FCfg.APIKey := Trim(edtAPIKey.Text);
  FCfg.IntervalMs := spinInterval.Value * 1000;
  FCfg.RandomOrder := chkRandom.Checked;
  FCfg.UseOriginal := chkOriginal.Checked;
  FCfg.FadeEnabled := chkFade.Checked;
  FCfg.FadeDurationMs := spinFade.Value;
  FCfg.ShowClock := chkClock.Checked;
  case cmbFit.ItemIndex of
    1: FCfg.FitMode := fmFit;
    2: FCfg.FitMode := fmStretch;
  else
    FCfg.FitMode := fmCover;
  end;
  if cmbClockH.ItemIndex = 0 then
    FCfg.ClockH := chLeft
  else
    FCfg.ClockH := chRight;
  if cmbClockV.ItemIndex = 0 then
    FCfg.ClockV := cvTop
  else
    FCfg.ClockV := cvBottom;

  // Only overwrite the albums when the list was actually loaded, otherwise a
  // previously saved selection would be wiped.
  if clbAlbums.Items.Count > 0 then
  begin
    FCfg.AlbumIds.Clear;
    for i := 0 to clbAlbums.Items.Count - 1 do
      if clbAlbums.Checked[i] and (i < FAlbumIds.Count) then
        FCfg.AlbumIds.Add(FAlbumIds[i]);
  end;

  // All (or none) checked means "all monitors", stored as an empty list
  CheckedMonitors := 0;
  for i := 0 to clbMonitors.Items.Count - 1 do
    if clbMonitors.Checked[i] then
      Inc(CheckedMonitors);

  FCfg.Monitors.Clear;
  if (CheckedMonitors > 0) and (CheckedMonitors < clbMonitors.Items.Count) then
    for i := 0 to clbMonitors.Items.Count - 1 do
      if clbMonitors.Checked[i] then
        FCfg.Monitors.Add(IntToStr(i));
end;

procedure TSettingsForm.DoShowKeyClick(Sender: TObject);
begin
  if chkShowKey.Checked then
    edtAPIKey.PasswordChar := #0
  else
    edtAPIKey.PasswordChar := '*';
end;

procedure TSettingsForm.DoTestClick(Sender: TObject);
var
  Client: TImmichClient;
  Msg: string;
  Ok: Boolean;
begin
  if (Trim(edtServer.Text) = '') or (Trim(edtAPIKey.Text) = '') then
  begin
    ShowMessage('Please enter the server URL and API key.');
    Exit;
  end;
  Client := TImmichClient.Create(edtServer.Text, edtAPIKey.Text);
  Screen.Cursor := crHourGlass;
  try
    Ok := Client.TestConnection(Msg);
  finally
    Screen.Cursor := crDefault;
    Client.Free;
  end;
  if Ok then
    ShowMessage('Connection successful.')
  else
    ShowMessage('Connection failed:' + LineEnding + Msg);
end;

procedure TSettingsForm.DoLoadAlbumsClick(Sender: TObject);
begin
  LoadAlbumsFromServer(True);
end;

procedure TSettingsForm.DoAboutClick(Sender: TObject);
begin
  ShowAboutDialog(Self);
end;

procedure TSettingsForm.DoSaveClick(Sender: TObject);
begin
  if (Trim(edtServer.Text) = '') or (Trim(edtAPIKey.Text) = '') then
  begin
    ShowMessage('Please enter the server URL and API key.');
    Exit;
  end;
  SaveUIToConfig;
  try
    FCfg.Save;
  except
    on E: Exception do
    begin
      ShowMessage('Could not save the settings: ' + E.Message);
      Exit;
    end;
  end;
  ModalResult := mrOk;
end;

procedure TSettingsForm.DoCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

function TSettingsForm.Execute: Boolean;
begin
  Result := ShowModal = mrOk;
end;

end.
