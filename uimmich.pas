unit uImmich;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpclient, opensslsockets, fpjson, jsonparser;

type
  EImmichHttp = class(Exception);

  { TImmichClient - thin wrapper around the Immich REST API }
  TImmichClient = class
  private
    FServer: string;
    FAPIKey: string;
    FHttp: TFPHTTPClient;
    procedure PrepareJsonHeaders;
    procedure CheckHttpOk;
    function NormalizeServer(const S: string): string;
  public
    constructor Create(const AServer, AAPIKey: string);
    destructor Destroy; override;

    procedure SetTimeouts(AConnectMs, AIOMs: Integer);

    // Aborts a running request. Safe to call from another thread.
    procedure Abort;

    // Returns True on success; AMessage holds the reply or the error text
    function TestConnection(out AMessage: string): Boolean;

    // Fills Names and Ids (parallel lists) with all albums
    procedure GetAlbums(ANames, AIds: TStrings);

    // Collects every image asset id. An empty AAlbumIds searches the whole
    // library (paginated), otherwise the given albums are read.
    function GetImageAssetIds(AAlbumIds: TStrings): TStringList;
    procedure GetImageAssetIdsInto(AAlbumIds: TStrings; Target: TStringList);

    // Appends a random batch of image ids to APool. An empty AAlbumId searches
    // the whole library. ASeen is used for deduplication and must be sorted.
    procedure SearchRandomAppend(const AAlbumId: string; ACount: Integer;
      APool, ASeen: TStringList);

    // Downloads an image; the caller owns the stream. Returns nil on failure.
    function DownloadImage(const AssetId: string; UseOriginal: Boolean): TMemoryStream;

    property Server: string read FServer write FServer;
    property APIKey: string read FAPIKey write FAPIKey;
  end;

implementation

const
  MAX_SEARCH_PAGES = 500; // safety limit for the pagination loop

constructor TImmichClient.Create(const AServer, AAPIKey: string);
begin
  inherited Create;
  FServer := NormalizeServer(AServer);
  FAPIKey := Trim(AAPIKey);
  FHttp := TFPHTTPClient.Create(nil);
  FHttp.AllowRedirect := True;
  FHttp.ConnectTimeout := 10000;
  FHttp.IOTimeout := 30000;
end;

destructor TImmichClient.Destroy;
begin
  FHttp.Free;
  inherited Destroy;
end;

procedure TImmichClient.SetTimeouts(AConnectMs, AIOMs: Integer);
begin
  FHttp.ConnectTimeout := AConnectMs;
  FHttp.IOTimeout := AIOMs;
end;

procedure TImmichClient.Abort;
begin
  // Only sets a flag; the read loops of TFPHTTPClient bail out between reads
  FHttp.Terminate;
end;

function TImmichClient.NormalizeServer(const S: string): string;
begin
  Result := Trim(S);
  while (Length(Result) > 0) and (Result[Length(Result)] = '/') do
    Delete(Result, Length(Result), 1);
end;

procedure TImmichClient.PrepareJsonHeaders;
begin
  FHttp.RequestHeaders.Clear;
  FHttp.AddHeader('x-api-key', FAPIKey);
  FHttp.AddHeader('Accept', 'application/json');
end;

// The GET overloads of TFPHTTPClient already validate the status code, the
// POST overloads do not. Check explicitly so a 401/5xx is not mistaken for
// an empty result.
procedure TImmichClient.CheckHttpOk;
begin
  if (FHttp.ResponseStatusCode < 200) or (FHttp.ResponseStatusCode >= 300) then
    raise EImmichHttp.CreateFmt('HTTP %d %s', [FHttp.ResponseStatusCode, FHttp.ResponseStatusText]);
end;

function TImmichClient.TestConnection(out AMessage: string): Boolean;
begin
  Result := False;
  try
    PrepareJsonHeaders;
    AMessage := FHttp.Get(FServer + '/api/server/ping');
    Result := Pos('pong', LowerCase(AMessage)) > 0;
    if not Result then
      AMessage := 'Unexpected reply: ' + AMessage;
  except
    on E: Exception do
      AMessage := E.Message;
  end;
end;

procedure TImmichClient.GetAlbums(ANames, AIds: TStrings);
var
  Response: string;
  Data: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  i: Integer;
begin
  ANames.Clear;
  AIds.Clear;
  PrepareJsonHeaders;
  Response := FHttp.Get(FServer + '/api/albums');

  Data := GetJSON(Response);
  try
    if Data is TJSONArray then
    begin
      Arr := TJSONArray(Data);
      for i := 0 to Arr.Count - 1 do
        if Arr.Items[i] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[i]);
          ANames.Add(Obj.Get('albumName', '(unnamed)') +
                     '  [' + IntToStr(Obj.Get('assetCount', 0)) + ']');
          AIds.Add(Obj.Get('id', ''));
        end;
    end;
  finally
    Data.Free;
  end;
end;

// Collects IMAGE asset ids from an assets array, deduplicated through Seen
procedure CollectImageIds(Arr: TJSONArray; Target, Seen: TStringList);
var
  i: Integer;
  Obj: TJSONObject;
  AType, AId: string;
begin
  if Arr = nil then
    Exit;
  for i := 0 to Arr.Count - 1 do
    if Arr.Items[i] is TJSONObject then
    begin
      Obj := TJSONObject(Arr.Items[i]);
      AType := UpperCase(Obj.Get('type', ''));
      AId := Obj.Get('id', '');
      if (AType = 'IMAGE') and (AId <> '') and (Seen.IndexOf(AId) < 0) then
      begin
        Seen.Add(AId);
        Target.Add(AId);
      end;
    end;
end;

function TImmichClient.GetImageAssetIds(AAlbumIds: TStrings): TStringList;
begin
  Result := TStringList.Create;
  GetImageAssetIdsInto(AAlbumIds, Result);
end;

procedure TImmichClient.GetImageAssetIdsInto(AAlbumIds: TStrings; Target: TStringList);
var
  Seen: TStringList;
  i: Integer;

  procedure LoadFromAlbum(const AlbumId: string);
  var
    Response: string;
    Data: TJSONData;
    Obj: TJSONObject;
  begin
    PrepareJsonHeaders;
    Response := FHttp.Get(FServer + '/api/albums/' + AlbumId);
    Data := GetJSON(Response);
    try
      if Data is TJSONObject then
      begin
        Obj := TJSONObject(Data);
        if Obj.Find('assets') is TJSONArray then
          CollectImageIds(TJSONArray(Obj.Find('assets')), Target, Seen);
      end;
    finally
      Data.Free;
    end;
  end;

  procedure LoadFromLibrary;
  var
    Page: Integer;
    Body: TStringStream;
    Response: string;
    Data: TJSONData;
    Obj, AssetsObj: TJSONObject;
    NextNode: TJSONData;
    HasMore: Boolean;
  begin
    Page := 1;
    repeat
      HasMore := False;
      FHttp.RequestHeaders.Clear;
      FHttp.AddHeader('x-api-key', FAPIKey);
      FHttp.AddHeader('Accept', 'application/json');
      FHttp.AddHeader('Content-Type', 'application/json');

      Body := TStringStream.Create('{"type":"IMAGE","size":1000,"page":' + IntToStr(Page) + '}');
      try
        FHttp.RequestBody := Body;
        try
          Response := FHttp.Post(FServer + '/api/search/metadata');
          CheckHttpOk;
        finally
          FHttp.RequestBody := nil;
        end;
      finally
        Body.Free;
      end;

      Data := GetJSON(Response);
      try
        if Data is TJSONObject then
        begin
          Obj := TJSONObject(Data);
          if Obj.Find('assets') is TJSONObject then
          begin
            AssetsObj := TJSONObject(Obj.Find('assets'));
            if AssetsObj.Find('items') is TJSONArray then
              CollectImageIds(TJSONArray(AssetsObj.Find('items')), Target, Seen);

            NextNode := AssetsObj.Find('nextPage');
            if (NextNode <> nil) and (not NextNode.IsNull) then
            begin
              // nextPage may be a number or a string
              Page := StrToIntDef(NextNode.AsString, 0);
              HasMore := Page > 0;
            end;
          end;
        end;
      finally
        Data.Free;
      end;
    until (not HasMore) or (Page > MAX_SEARCH_PAGES);
  end;

begin
  Seen := TStringList.Create;
  try
    Seen.Sorted := True;
    Seen.Duplicates := dupIgnore;
    for i := 0 to Target.Count - 1 do
      Seen.Add(Target[i]);
    if (AAlbumIds = nil) or (AAlbumIds.Count = 0) then
      LoadFromLibrary
    else
      for i := 0 to AAlbumIds.Count - 1 do
        if Trim(AAlbumIds[i]) <> '' then
          LoadFromAlbum(Trim(AAlbumIds[i]));
  finally
    Seen.Free;
  end;
end;

procedure TImmichClient.SearchRandomAppend(const AAlbumId: string; ACount: Integer;
  APool, ASeen: TStringList);
var
  Body: TStringStream;
  Response, js: string;
  Data: TJSONData;
begin
  FHttp.RequestHeaders.Clear;
  FHttp.AddHeader('x-api-key', FAPIKey);
  FHttp.AddHeader('Accept', 'application/json');
  FHttp.AddHeader('Content-Type', 'application/json');

  if AAlbumId <> '' then
    js := Format('{"size":%d,"type":"IMAGE","albumIds":["%s"]}', [ACount, AAlbumId])
  else
    js := Format('{"size":%d,"type":"IMAGE"}', [ACount]);

  Body := TStringStream.Create(js);
  try
    FHttp.RequestBody := Body;
    try
      Response := FHttp.Post(FServer + '/api/search/random');
      CheckHttpOk;
    finally
      FHttp.RequestBody := nil;
    end;
  finally
    Body.Free;
  end;

  Data := GetJSON(Response);
  try
    if Data is TJSONArray then
      CollectImageIds(TJSONArray(Data), APool, ASeen);
  finally
    Data.Free;
  end;
end;

function TImmichClient.DownloadImage(const AssetId: string; UseOriginal: Boolean): TMemoryStream;
var
  Url: string;
begin
  Result := TMemoryStream.Create;
  try
    FHttp.RequestHeaders.Clear;
    FHttp.AddHeader('x-api-key', FAPIKey);

    if UseOriginal then
      Url := FServer + '/api/assets/' + AssetId + '/original'
    else
      Url := FServer + '/api/assets/' + AssetId + '/thumbnail?size=preview';

    FHttp.Get(Url, Result);
    Result.Position := 0;

    if Result.Size = 0 then
      FreeAndNil(Result);
  except
    on E: Exception do
      FreeAndNil(Result);
  end;
end;

end.
