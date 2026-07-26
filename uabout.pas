unit uAbout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, LCLIntf;

const
  APP_NAME = 'Immich Screensaver';
  APP_VERSION = '1.0';
  AUTHOR_NAME = 'Tobias Schottstädt';
  AUTHOR_URL = 'https://www.schottstaedt.net/';
  IMMICH_URL = 'https://immich.app/';
  PROJECT_URL = 'https://github.com/xchimx/ImmichScreensaver';

type
  { TAboutForm - short description of the project and its author }
  TAboutForm = class(TForm)
  private
    procedure BuildUI;
    function AddLink(ALeft, ATop: Integer; const ACaption, AUrl: string): TLabel;
    procedure LinkClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

procedure ShowAboutDialog(AOwner: TComponent);

implementation

procedure ShowAboutDialog(AOwner: TComponent);
var
  Dlg: TAboutForm;
begin
  Dlg := TAboutForm.Create(AOwner);
  try
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

{ TAboutForm }

constructor TAboutForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BuildUI;
end;

function TAboutForm.AddLink(ALeft, ATop: Integer; const ACaption, AUrl: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Caption := ACaption;
  Result.Hint := AUrl;
  Result.ShowHint := True;
  Result.Cursor := crHandPoint;
  Result.Font.Color := clHotLight;
  Result.Font.Style := [fsUnderline];
  Result.OnClick := @LinkClick;
end;

procedure TAboutForm.BuildUI;
var
  lbl: TLabel;
  btnClose: TButton;
begin
  Caption := 'About ' + APP_NAME;
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := 460;
  ClientHeight := 340;
  Color := clBtnFace;

  lbl := TLabel.Create(Self);
  lbl.Parent := Self;
  lbl.SetBounds(20, 18, 420, 28);
  lbl.Caption := APP_NAME + ' ' + APP_VERSION;
  lbl.Font.Size := 14;
  lbl.Font.Style := [fsBold];

  lbl := TLabel.Create(Self);
  lbl.Parent := Self;
  lbl.SetBounds(20, 52, 420, 80);
  lbl.WordWrap := True;
  lbl.AutoSize := False;
  lbl.Caption :=
    'A Windows screensaver that displays photos from your own Immich ' +
    'server. It supports multiple monitors (a separate photo on every ' +
    'screen), album selection, random order, smooth crossfades and an ' +
    'optional clock and date overlay.';

  lbl := TLabel.Create(Self);
  lbl.Parent := Self;
  lbl.SetBounds(20, 140, 420, 20);
  lbl.Caption := 'Built with Lazarus / Free Pascal. Free and open source (MIT).';

  lbl := TLabel.Create(Self);
  lbl.Parent := Self;
  lbl.SetBounds(20, 178, 420, 20);
  lbl.Caption := 'Created by ' + AUTHOR_NAME;
  lbl.Font.Style := [fsBold];

  lbl := TLabel.Create(Self);
  lbl.Parent := Self;
  lbl.SetBounds(20, 200, 420, 36);
  lbl.WordWrap := True;
  lbl.AutoSize := False;
  lbl.Caption := 'Software developer from Germany. More projects and contact ' +
                 'details on my website:';

  AddLink(20, 238, AUTHOR_URL, AUTHOR_URL);
  AddLink(20, 262, 'Project page: ' + PROJECT_URL, PROJECT_URL);
  AddLink(20, 286, 'Immich photo server: ' + IMMICH_URL, IMMICH_URL);

  btnClose := TButton.Create(Self);
  btnClose.Parent := Self;
  btnClose.SetBounds(350, 300, 90, 28);
  btnClose.Caption := 'Close';
  btnClose.Default := True;
  btnClose.Cancel := True;
  btnClose.OnClick := @CloseClick;
end;

procedure TAboutForm.LinkClick(Sender: TObject);
begin
  if Sender is TLabel then
    OpenURL(TLabel(Sender).Hint);
end;

procedure TAboutForm.CloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

end.
