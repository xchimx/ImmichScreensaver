unit uScreenWin;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, Forms, Controls, Graphics, ExtCtrls, Types, uConfig;

type
  { TScreenWindow - a borderless fullscreen window covering exactly one monitor.
    Image changes are optionally crossfaded. User input is evaluated centrally
    by the controller, not here. }
  TScreenWindow = class(TForm)
  private
    FFitMode: TFitMode;
    FFadeEnabled: Boolean;
    FShowClock: Boolean;
    FClockH: TClockHAlign;
    FClockV: TClockVAlign;
    FTargetBounds: TRect;
    FCurBmp: TBitmap;      // currently visible full screen image
    FNextBmp: TBitmap;     // image fading in
    FHasImage: Boolean;
    FFading: Boolean;
    FFadePending: Boolean; // decoded, fade not started yet
    FFadeAlpha: Integer;   // 0..255
    FFadeStep: Integer;    // alpha increment per tick, derived from duration
    FFadeTimer: TTimer;
    FClockTimer: TTimer;
    procedure ApplyTargetBounds;
    procedure EnsureBitmaps;
    procedure RenderGraphicTo(Bmp: TBitmap; G: TGraphic);
    procedure FinalizeFade;
    procedure FadeStep(Sender: TObject);
    procedure ClockTick(Sender: TObject);
    procedure DrawClock;
  protected
    procedure DoShow; override;
  public
    constructor CreateForMonitor(AOwner: TComponent; const ABounds: TRect;
      AFitMode: TFitMode; AFadeEnabled: Boolean; AFadeDurationMs: Integer;
      AShowClock: Boolean; AClockH: TClockHAlign; AClockV: TClockVAlign);
    destructor Destroy; override;
    procedure Paint; override;
    // Decodes and pre-renders a new image without starting the fade. The stream
    // is NOT freed. For smooth changes decode on every monitor first, then call
    // BeginFade on all of them.
    procedure PrepareImageFromStream(AStream: TStream);
    procedure BeginFade;
    // Convenience: decode and fade immediately (first image / priming).
    procedure ShowImageFromStream(AStream: TStream);
  end;

implementation

const
  FADE_INTERVAL_MS = 16; // fade timer tick (~60 fps)

// AlphaBlend is not declared in the FPC Windows unit; import it from msimg32
// under a distinct name to avoid clashing with other units.
function WinAlphaBlend(hdcDest: HDC; xDest, yDest, wDest, hDest: Integer;
  hdcSrc: HDC; xSrc, ySrc, wSrc, hSrc: Integer; ftn: TBlendFunction): BOOL;
  stdcall; external 'msimg32.dll' name 'AlphaBlend';

constructor TScreenWindow.CreateForMonitor(AOwner: TComponent; const ABounds: TRect;
  AFitMode: TFitMode; AFadeEnabled: Boolean; AFadeDurationMs: Integer;
  AShowClock: Boolean; AClockH: TClockHAlign; AClockV: TClockVAlign);
begin
  inherited CreateNew(AOwner);
  FFitMode := AFitMode;
  FFadeEnabled := AFadeEnabled;
  FShowClock := AShowClock;
  FClockH := AClockH;
  FClockV := AClockV;
  FTargetBounds := ABounds;
  FHasImage := False;
  FFading := False;

  if AFadeDurationMs < FADE_INTERVAL_MS then
    AFadeDurationMs := FADE_INTERVAL_MS;
  FFadeStep := Round(255 * FADE_INTERVAL_MS / AFadeDurationMs);
  if FFadeStep < 1 then
    FFadeStep := 1;
  if FFadeStep > 255 then
    FFadeStep := 255;

  FCurBmp := TBitmap.Create;
  FCurBmp.PixelFormat := pf24bit;
  FNextBmp := TBitmap.Create;
  FNextBmp.PixelFormat := pf24bit;

  FFadeTimer := TTimer.Create(Self);
  FFadeTimer.Enabled := False;
  FFadeTimer.Interval := FADE_INTERVAL_MS;
  FFadeTimer.OnTimer := @FadeStep;

  FClockTimer := TTimer.Create(Self);
  FClockTimer.Interval := 1000;
  FClockTimer.OnTimer := @ClockTick;
  FClockTimer.Enabled := FShowClock;

  // Scaling off so SetBounds hits the exact physical pixels of the monitor
  Scaled := False;
  BorderStyle := bsNone;
  FormStyle := fsSystemStayOnTop;
  Color := clBlack;
  Cursor := crNone;
  DoubleBuffered := True;
  ShowInTaskBar := stNever;

  ApplyTargetBounds;
end;

destructor TScreenWindow.Destroy;
begin
  FCurBmp.Free;
  FNextBmp.Free;
  inherited Destroy;
end;

procedure TScreenWindow.ApplyTargetBounds;
begin
  SetBounds(FTargetBounds.Left, FTargetBounds.Top,
            FTargetBounds.Right - FTargetBounds.Left,
            FTargetBounds.Bottom - FTargetBounds.Top);
end;

procedure TScreenWindow.DoShow;
begin
  inherited DoShow;
  // Re-apply once the handle exists, robust against DPI/autoscale corrections
  ApplyTargetBounds;
end;

procedure TScreenWindow.EnsureBitmaps;
begin
  if (FCurBmp.Width <> ClientWidth) or (FCurBmp.Height <> ClientHeight) then
  begin
    FCurBmp.SetSize(ClientWidth, ClientHeight);
    FCurBmp.Canvas.Brush.Color := clBlack;
    FCurBmp.Canvas.FillRect(0, 0, ClientWidth, ClientHeight);
  end;
  if (FNextBmp.Width <> ClientWidth) or (FNextBmp.Height <> ClientHeight) then
    FNextBmp.SetSize(ClientWidth, ClientHeight);
end;

procedure TScreenWindow.RenderGraphicTo(Bmp: TBitmap; G: TGraphic);
var
  cw, ch, iw, ih, dw, dh, x, y: Integer;
  scale: Double;
  Dest: TRect;
begin
  cw := Bmp.Width;
  ch := Bmp.Height;
  Bmp.Canvas.Brush.Color := clBlack;
  Bmp.Canvas.Brush.Style := bsSolid;
  Bmp.Canvas.FillRect(0, 0, cw, ch);

  if (G = nil) or G.Empty then
    Exit;
  iw := G.Width;
  ih := G.Height;
  if (iw <= 0) or (ih <= 0) then
    Exit;

  Dest := Rect(0, 0, cw, ch);
  case FFitMode of
    fmStretch:
      Dest := Rect(0, 0, cw, ch);
    fmFit, fmCover:
      begin
        if FFitMode = fmFit then
        begin
          // whole image visible (letterbox)
          scale := cw / iw;
          if (ih * scale) > ch then
            scale := ch / ih;
        end
        else
        begin
          // fill the screen, overflow is cropped
          scale := cw / iw;
          if (ih * scale) < ch then
            scale := ch / ih;
        end;
        dw := Round(iw * scale);
        dh := Round(ih * scale);
        x := (cw - dw) div 2;
        y := (ch - dh) div 2;
        Dest := Rect(x, y, x + dw, y + dh);
      end;
  end;

  Bmp.Canvas.StretchDraw(Dest, G);
end;

procedure TScreenWindow.PrepareImageFromStream(AStream: TStream);
var
  Pic: TPicture;
begin
  FFadePending := False;
  if AStream = nil then
    Exit;

  if FFading then
    FinalizeFade;

  Pic := TPicture.Create;
  try
    try
      AStream.Position := 0;
      Pic.LoadFromStream(AStream);
    except
      Exit; // broken image, keep showing the previous one
    end;

    EnsureBitmaps;

    if (not FFadeEnabled) or (not FHasImage) then
    begin
      RenderGraphicTo(FCurBmp, Pic.Graphic);
      FHasImage := True;
      Invalidate;
    end
    else
    begin
      RenderGraphicTo(FNextBmp, Pic.Graphic);
      FFadePending := True;
    end;
  finally
    Pic.Free;
  end;
end;

procedure TScreenWindow.BeginFade;
begin
  if not FFadePending then
    Exit;
  FFadePending := False;
  FFadeAlpha := 0;
  FFading := True;
  FFadeTimer.Enabled := True;
  Invalidate;
end;

procedure TScreenWindow.ShowImageFromStream(AStream: TStream);
begin
  PrepareImageFromStream(AStream);
  BeginFade;
end;

procedure TScreenWindow.FinalizeFade;
begin
  FFadeTimer.Enabled := False;
  if FFading then
  begin
    FCurBmp.Canvas.Draw(0, 0, FNextBmp);
    FHasImage := True;
  end;
  FFading := False;
end;

procedure TScreenWindow.FadeStep(Sender: TObject);
begin
  Inc(FFadeAlpha, FFadeStep);
  if FFadeAlpha >= 255 then
  begin
    FFadeAlpha := 255;
    FinalizeFade;
  end;
  Invalidate;
end;

procedure TScreenWindow.ClockTick(Sender: TObject);
begin
  if FShowClock then
    Invalidate;
end;

procedure TScreenWindow.DrawClock;
var
  dt: TDateTime;
  TimeStr, DateStr: string;
  bigH, smallH, margin, tw, th, dw, dh, yTime, yDate: Integer;

  procedure ShadowText(const S: string; X, Y: Integer);
  begin
    Canvas.Font.Color := clBlack;
    Canvas.TextOut(X + 2, Y + 2, S);
    Canvas.Font.Color := clWhite;
    Canvas.TextOut(X, Y, S);
  end;

begin
  dt := Now;
  // Weekday and date follow the system locale
  TimeStr := FormatDateTime('hh:nn', dt);
  DateStr := FormatDateTime('dddd', dt) + ', ' + DateToStr(dt);

  bigH := ClientHeight div 18;
  if bigH < 22 then
    bigH := 22;
  smallH := ClientHeight div 42;
  if smallH < 12 then
    smallH := 12;
  margin := ClientHeight div 36;
  if margin < 16 then
    margin := 16;

  Canvas.Brush.Style := bsClear;
  Canvas.Font.Name := 'Segoe UI';

  Canvas.Font.Style := [];
  Canvas.Font.Height := smallH;
  dw := Canvas.TextWidth(DateStr);
  dh := Canvas.TextHeight(DateStr);

  Canvas.Font.Style := [fsBold];
  Canvas.Font.Height := bigH;
  tw := Canvas.TextWidth(TimeStr);
  th := Canvas.TextHeight(TimeStr);

  if FClockV = cvTop then
  begin
    yTime := margin;
    yDate := yTime + th;
  end
  else
  begin
    yDate := ClientHeight - margin - dh;
    yTime := yDate - th;
  end;

  if FClockH = chLeft then
    ShadowText(TimeStr, margin, yTime)
  else
    ShadowText(TimeStr, ClientWidth - margin - tw, yTime);

  Canvas.Font.Style := [];
  Canvas.Font.Height := smallH;
  if FClockH = chLeft then
    ShadowText(DateStr, margin, yDate)
  else
    ShadowText(DateStr, ClientWidth - margin - dw, yDate);
end;

procedure TScreenWindow.Paint;
var
  bf: TBlendFunction;
begin
  if not FHasImage then
  begin
    Canvas.Brush.Color := clBlack;
    Canvas.Brush.Style := bsSolid;
    Canvas.FillRect(ClientRect);
  end
  else
  begin
    Canvas.Draw(0, 0, FCurBmp);

    if FFading then
    begin
      bf.BlendOp := AC_SRC_OVER;
      bf.BlendFlags := 0;
      bf.SourceConstantAlpha := FFadeAlpha;
      bf.AlphaFormat := 0;
      WinAlphaBlend(Canvas.Handle, 0, 0, ClientWidth, ClientHeight,
                    FNextBmp.Canvas.Handle, 0, 0, ClientWidth, ClientHeight, bf);
    end;
  end;

  if FShowClock then
    DrawClock;
end;

end.
