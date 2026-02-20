unit NtUtils.VirtDisk;

{
  This module exposes low-level virtual disk API (for .iso and .vhdx).
}

interface

uses
  Ntapi.VirtDisk, Ntapi.ntseapi, NtUtils;

// Determine a disk type based on the file extension
function VdskxDiskTypeFromName(
  const FileName: String
): TVirtualStorageDeviceId;

// Open an existing virtual disk
function VdskxOpenVirtualDisk(
  out hxVirtualDisk: IHandle;
  const FileName: String;
  AccessMask: TVirtualDiskAccessMask = VIRTUAL_DISK_ACCESS_READ;
  DeviceId: TVirtualStorageDeviceId = VIRTUAL_STORAGE_TYPE_DEVICE_UNKNOWN;
  Flags: TOpenVirtualDiskFlags = 0
): TNtxStatus;

// Attach a virtual disk
[RequiredPrivilege(SE_MANAGE_VOLUME_PRIVILEGE, rpSometimes)]
function VdskxSurfaceVirualDisk(
  const hxVirtualDisk: IHandle;
  Flags: TAttachVirtualDiskFlags = ATTACH_VIRTUAL_DISK_FLAG_READ_ONLY;
  [in, opt] const SecurityDescriptor: ISecurityDescriptor = nil
): TNtxStatus;

// Detach a virtual disk
[RequiredPrivilege(SE_MANAGE_VOLUME_PRIVILEGE, rpSometimes)]
function VdskxUnsurfaceVirualDisk(
  const hxVirtualDisk: IHandle
): TNtxStatus;

// Query the attached path for a virtual disk
function VdskxQueryNameVirualDisk(
  const hxVirtualDisk: IHandle;
  out FileName: String
): TNtxStatus;

implementation

uses
  Ntapi.WinNt, Ntapi.ntioapi, Ntapi.ntrtl, DelphiUtils.AutoObjects,
  NtUtils.Files, NtUtils.Files.Open, NtUtils.Files.Control, NtUtils.SysUtils;

{$BOOLEVAL OFF}
{$IFOPT R+}{$DEFINE R+}{$ENDIF}
{$IFOPT Q+}{$DEFINE Q+}{$ENDIF}

function VdskxDiskTypeFromName;
var
  Extension: String;
begin
  Extension := RtlxExtractExtensionPath(FileName);

  if RtlxEqualStrings(Extension, 'iso') then
    Result := VIRTUAL_STORAGE_TYPE_DEVICE_ISO
  else if RtlxEqualStrings(Extension, 'vhd') or
    RtlxEqualStrings(Extension, 'avhd') then
    Result := VIRTUAL_STORAGE_TYPE_DEVICE_VHD
  else if RtlxEqualStrings(Extension, 'vhdx') or
    RtlxEqualStrings(Extension, 'avhdx') then
    Result := VIRTUAL_STORAGE_TYPE_DEVICE_VHDX
  else if RtlxEqualStrings(Extension, 'vhds') then
    Result := VIRTUAL_STORAGE_TYPE_DEVICE_VHDSET
  else
    Result := VIRTUAL_STORAGE_TYPE_DEVICE_UNKNOWN;
end;

function VdskxOpenVirtualDisk;
var
  EA: TVirtualDiskEaBuffer;
  EABuffer: IFullEaInformation;
begin
  if DeviceId = VIRTUAL_STORAGE_TYPE_DEVICE_UNKNOWN then
    DeviceId := VdskxDiskTypeFromName(FileName);

  // Prepare the extended attribute describing flags and options
  EA := Default(TVirtualDiskEaBuffer);
  EA.Identifier := GUID_DEVINTERFACE_SURFACE_VIRTUAL_DRIVE;
  EA.VirtualStorageType.DeviceId := DeviceId;
  EA.VirtualStorageType.VendorId := VIRTUAL_STORAGE_TYPE_VENDOR_MICROSOFT;
  EA.EASize := SizeOf(TVirtualDiskEaBuffer);
  EA.Flags := Flags;
  EA.AccessMask := AccessMask;
  EA.RWDepth := OPEN_VIRTUAL_DISK_RW_DEPTH_DEFAULT;
  EA.Version := 1;
  EABuffer := RtlxAllocateEA(VIRTUAL_DISK_EA_NAME, Auto.RefBuffer(EA),
    FILE_NEED_EA);

  // Open the handle by passing the filename under VHDMP, together with the EA
  Result := NtxCreateFile(hxVirtualDisk, FileParameters
    .UseFileName(VHDMP_DEVICE_NAME + '\' + RtlxGetFullDosPath(FileName))
    .UseAccess(GENERIC_READ or GENERIC_WRITE)
    .UseEAs(EABuffer)
  );
end;

function VdskxSurfaceVirualDisk;
var
  SdLength: Cardinal;
  Input: IMemory<PStorageSurfaceVirtualDiskRequest>;
begin
  if Assigned(SecurityDescriptor) then
    SdLength := RtlLengthSecurityDescriptor(SecurityDescriptor.Data)
  else
    SdLength := 0;

  // Pack the flags
  IMemory(Input) := Auto.AllocateDynamic(
    SizeOf(TStorageSurfaceVirtualDiskRequest) + SdLength);
  Input.Data.RequestLevel := 1;
  Input.Data.Flags := Flags;

  if Assigned(SecurityDescriptor) then
  begin
    // Pack the security descriptor
    Input.Data.SecurityDescriptorOffset :=
      SizeOf(TStorageSurfaceVirtualDiskRequest);
    Input.Data.SecurityDescriptorLength := SdLength;
    Move(SecurityDescriptor.Data^, Input.Offset(
      Input.Data.SecurityDescriptorOffset)^, SdLength);
  end;

  // Issue the IOCTL
  Result := NtxDeviceIoControlFile(hxVirtualDisk,
    IOCTL_STORAGE_SURFACE_VIRTUAL_DISK, Input.Data, Input.Size);
  Result.LastCall.ExpectedPrivilege := SE_MANAGE_VOLUME_PRIVILEGE;
end;

function VdskxUnsurfaceVirualDisk;
var
  Input: TStorageUnsurfaceVirtualDiskRequest;
begin
  Input.RequestLevel := 1;
  Input.Flags := 0;
  Input.ProviderFlags := 0;

  Result := NtxDeviceIoControlFile(hxVirtualDisk,
    IOCTL_STORAGE_UNSURFACE_VIRTUAL_DISK, @Input, SizeOf(Input));
  Result.LastCall.ExpectedPrivilege := SE_MANAGE_VOLUME_PRIVILEGE;
end;

function VdskxQueryNameVirualDisk;
var
  Input: TStorageQueryVirtualDiskNameRequest;
  Output: IMemory<PStorageQueryVirtualDiskNameResponse>;
begin
  Input.RequestLevel := 1;

  Result := NtxDeviceIoControlFileEx(hxVirtualDisk,
    IOCTL_STORAGE_QUERY_VIRTUAL_DISK_NAME, IMemory(Output),
    SizeOf(TStorageQueryVirtualDiskNameResponse) + MAX_PATH * SizeOf(WideChar),
    nil,
    @Input,
    SizeOf(Input)
  );

  if Result.IsSuccess then
    FileName := RtlxCaptureString(
      Output.Offset(Output.Data.VirtualDiskDeviceNameOffset),
      Output.Data.VirtualDiskDeviceNameLength div SizeOf(WideChar)
    );
end;

end.
