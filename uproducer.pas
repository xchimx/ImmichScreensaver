unit uProducer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, uImmich;

type
  { TImageProducer - downloads images on a background thread so the UI thread
    (and therefore the crossfades) never blocks on the network. The thread only
    touches network and memory, never LCL or GDI objects. }
  TImageProducer = class(TThread)
  private
    FClient: TImmichClient;
    FUseOriginal: Boolean;
    FRandom: Boolean;
    FAlbumIds: TStringList;
    FAlbumRR: Integer;      // round-robin index across the albums
    FPool: TStringList;     // candidate asset ids
    FSeen: TStringList;     // sorted, used for deduplication
    FPos: Integer;
    FQueue: TFPList;        // FIFO of finished TMemoryStream objects
    FLock: TCriticalSection;
    FCapacity: Integer;
    FNoImages: Boolean;     // set when no ids could be found at all
    procedure BuildInitialPool;
    procedure RefillRandom;
    function QueueLen: Integer;
    procedure ShufflePool;
  protected
    procedure Execute; override;
  public
    constructor Create(const AServer, AKey: string; AUseOriginal, ARandom: Boolean;
      AAlbumIds: TStrings; ACapacity: Integer);
    destructor Destroy; override;
    // Called from the UI thread: take the next ready image (nil if none).
    // The caller owns the returned stream.
    function PopImage: TMemoryStream;
    // Called from the UI thread: request a stop and abort a running download
    // so that a following WaitFor returns quickly.
    procedure Cancel;
    property NoImages: Boolean read FNoImages;
  end;

implementation

const
  RANDOM_BATCH = 60;   // ids requested per album call
  POOL_TARGET = 400;   // pool size aimed for at startup
  LIBRARY_ROUNDS = 6;  // random batches when using the whole library
  QUEUE_WAIT_MS = 15;

constructor TImageProducer.Create(const AServer, AKey: string;
  AUseOriginal, ARandom: Boolean; AAlbumIds: TStrings; ACapacity: Integer);
begin
  inherited Create(True); // created suspended, the caller invokes Start
  FreeOnTerminate := False;
  FUseOriginal := AUseOriginal;
  FRandom := ARandom;
  FCapacity := ACapacity;
  if FCapacity < 2 then
    FCapacity := 2;

  FAlbumIds := TStringList.Create;
  if AAlbumIds <> nil then
    FAlbumIds.Assign(AAlbumIds);

  FPool := TStringList.Create;
  FSeen := TStringList.Create;
  FSeen.Sorted := True;
  FSeen.Duplicates := dupIgnore;
  FQueue := TFPList.Create;
  FLock := TCriticalSection.Create;

  // Own HTTP client for this thread, never shared with the UI thread.
  // Short IO timeout so a stalled download gives up quickly on shutdown.
  FClient := TImmichClient.Create(AServer, AKey);
  FClient.SetTimeouts(5000, 2500);
end;

destructor TImageProducer.Destroy;
var
  i: Integer;
begin
  FLock.Enter;
  try
    for i := 0 to FQueue.Count - 1 do
      TObject(FQueue[i]).Free;
    FQueue.Clear;
  finally
    FLock.Leave;
  end;
  FQueue.Free;
  FLock.Free;
  FPool.Free;
  FSeen.Free;
  FAlbumIds.Free;
  FClient.Free;
  inherited Destroy;
end;

function TImageProducer.QueueLen: Integer;
begin
  FLock.Enter;
  try
    Result := FQueue.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TImageProducer.ShufflePool;
var
  i, j: Integer;
begin
  for i := FPool.Count - 1 downto 1 do
  begin
    j := Random(i + 1);
    FPool.Exchange(i, j);
  end;
end;

procedure TImageProducer.RefillRandom;
var
  albumId: string;
begin
  if FAlbumIds.Count = 0 then
    albumId := ''
  else
  begin
    albumId := Trim(FAlbumIds[FAlbumRR]);
    FAlbumRR := (FAlbumRR + 1) mod FAlbumIds.Count;
  end;
  try
    FClient.SearchRandomAppend(albumId, RANDOM_BATCH, FPool, FSeen);
  except
    // ignore a single failed request
  end;
end;

procedure TImageProducer.BuildInitialPool;
var
  rounds, maxRounds: Integer;
begin
  if FRandom then
  begin
    // Small random batches per album keep startup fast even for large libraries
    if FAlbumIds.Count = 0 then
      maxRounds := LIBRARY_ROUNDS
    else
      maxRounds := FAlbumIds.Count;
    rounds := 0;
    while (not Terminated) and (FPool.Count < POOL_TARGET) and (rounds < maxRounds) do
    begin
      RefillRandom;
      Inc(rounds);
    end;
    ShufflePool;
  end
  else
  begin
    // Sequential mode needs the complete list in order
    try
      FClient.GetImageAssetIdsInto(FAlbumIds, FPool);
    except
      // leave the pool as it is; an empty pool is reported as NoImages
    end;
  end;
end;

procedure TImageProducer.Execute;
var
  id: string;
  s: TMemoryStream;
begin
  Randomize;
  BuildInitialPool;

  if FPool.Count = 0 then
  begin
    FNoImages := True;
    Exit;
  end;

  FPos := 0;
  while not Terminated do
  begin
    if QueueLen >= FCapacity then
    begin
      Sleep(QUEUE_WAIT_MS);
      Continue;
    end;

    if FPos >= FPool.Count then
    begin
      FPos := 0;
      if FRandom then
      begin
        ShufflePool;
        RefillRandom; // mix in fresh ids for variety
      end;
    end;
    if FPool.Count = 0 then
      Break;

    id := FPool[FPos];
    Inc(FPos);

    s := FClient.DownloadImage(id, FUseOriginal);
    if Terminated then
    begin
      s.Free;
      Break;
    end;
    if s <> nil then
    begin
      FLock.Enter;
      try
        FQueue.Add(s);
      finally
        FLock.Leave;
      end;
    end;
  end;
end;

function TImageProducer.PopImage: TMemoryStream;
begin
  Result := nil;
  FLock.Enter;
  try
    if FQueue.Count > 0 then
    begin
      Result := TMemoryStream(FQueue[0]);
      FQueue.Delete(0);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TImageProducer.Cancel;
begin
  Terminate;
  FClient.Abort;
end;

end.
