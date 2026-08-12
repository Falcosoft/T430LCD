; ASPECTD.ASM
; T430LCD 2.3 - ASPECTD
; Primary target: Lenovo ThinkPad T430 / Intel HD Graphics 4000
; Resident DPMI aspect-ratio / pixel-perfect centered display corrector.
;
; Final hardware-verified DPMI counterpart of ASPECT.
;
; Target environment:
;   JEMMEX/JEMM386 active
;   HDPMI32.EXE -R resident
;   VCPI disabled if required by other software (for example VSBHDA)
;
; Commands:
;   ASPECTD        install with aspect-ratio correction, or show state
;   ASPECTD /A     install/select aspect-ratio correction
;   ASPECTD /C     install/select pixel-perfect centered mode
;   ASPECTD /U     deactivate correction (resident DPMI client stays loaded)
;   ASPECTD /D     same as /U
;   ASPECTD /E     re-enable the selected policy
;
; /U deliberately means "deactivate" rather than physical unload. HDPMI32
; does not provide a documented safe way to destroy this resident client
; context later. The INT 10h and INT 2Fh hooks therefore remain installed.
;
; Resident behavior:
;   - watches INT 10h AH=00h legacy VGA mode sets
;   - watches INT 10h AX=4F02h VBE mode sets
;   - calls original BIOS first
;   - applies the selected policy to successful VBE modes, including native
;   - corrects only when BIOS restores installation PF_A_SIZE
;   - writes ONLY PF_A_POS followed by PF_A_SIZE
;   - verifies both writes
;   - disables future writes after any verification failure
;
; Build from TOOLS\ASPECT\ASPECTD:
;   TASM /Mx /I..\..\..\INCL ASPECTD.ASM
;   TLINK /t ASPECTD.OBJ
;
.model tiny
.386p
.code
org 100h

include T430LCD.INC

; ASPECTD maps the 4 KiB MMIO page containing the shared fitter registers.
; The register addresses themselves come from INCL\REGISTRS.INC.
PF_PAGE_OFFSET      equ 068000h
PF_A_POS_PAGE       equ (PF_A_POS_OFFSET-PF_PAGE_OFFSET)
PF_A_SIZE_PAGE      equ (PF_A_SIZE_OFFSET-PF_PAGE_OFFSET)
PIPE_PAGE_OFFSET    equ 060000h
PIPE_A_SRC_PAGE     equ 001Ch
MAP_SIZE            equ 1000h

; Plain ASPECT uses FEC0/FEC1.
MUX_PRESENT          equ 0FEC2h
MUX_PRESENT_REPLY    equ 0C2FEh
MUX_INFO             equ 0FEC3h
MUX_INFO_REPLY       equ 0C3FEh
MUX_CONTROL          equ 0FEC4h
MUX_CONTROL_REPLY    equ 0C4FEh

ASPECT_MUX_PRESENT       equ 0FEC0h
ASPECT_MUX_PRESENT_REPLY equ 0C0FEh

; Resident correction state.
STATE_ENABLED        equ 00h
STATE_USER_DISABLED  equ 01h
STATE_WRITE_FAILED   equ 02h

; Display policies.
POLICY_ASPECT        equ 00h
POLICY_CENTER        equ 01h

; Resident callback commands.
CMD_MODE             equ 00h
CMD_DISABLE          equ 01h
CMD_ENABLE           equ 02h
CMD_ASPECT           equ 03h
CMD_CENTER           equ 04h

; Control result codes returned in BL by MUX_CONTROL.
CTL_DISABLED_RESTORED equ 01h
CTL_DISABLED_ONLY     equ 02h
CTL_ALREADY_DISABLED equ 03h
CTL_ENABLED_APPLIED  equ 04h
CTL_ENABLED_PENDING  equ 05h
CTL_ALREADY_ENABLED  equ 06h
CTL_WRITE_FAILED     equ 07h
CTL_BUSY             equ 08h
CTL_LOCKED            equ 09h
CTL_POLICY_APPLIED    equ 0Ah
CTL_POLICY_PENDING    equ 0Bh
CTL_POLICY_SELECTED   equ 0Ch
CTL_BAD_COMMAND       equ 0FFh

; Installer command values.
ARG_DEFAULT           equ 00h
ARG_DISABLE           equ 01h
ARG_ENABLE            equ 02h
ARG_ASPECT            equ 03h
ARG_CENTER            equ 04h
ARG_INVALID           equ 0FFh

; DPMI real-mode register structure offsets.
RM_EDI               equ 00h
RM_ESI               equ 04h
RM_EBP               equ 08h
RM_RES                equ 0Ch
RM_EBX                equ 10h
RM_EDX                equ 14h
RM_ECX                equ 18h
RM_EAX                equ 1Ch
RM_FLAGS              equ 20h
RM_ES                 equ 22h
RM_DS                 equ 24h
RM_FS                 equ 26h
RM_GS                 equ 28h
RM_IP                 equ 2Ah
RM_CS                 equ 2Ch
RM_SP                 equ 2Eh
RM_SS                 equ 30h
RM_STRUCT_SIZE        equ 32h

HDPMI_PRIVATE_PARAS  equ 0020h

; ResidentInfo returned by INT 2Fh AX=FEC3h.
RI_STATE              equ 00h
RI_POLICY             equ 01h
RI_RES_PARAS          equ 02h

start:
        jmp     InstallerStart

; ==========================================================================
; RESIDENT REGION
; Everything through ResidentEnd remains resident.
; ==========================================================================

; --------------------------------------------------------------------------
; INT 2Fh presence/state/control service.
; --------------------------------------------------------------------------

NewInt2F proc far
        cmp     ax,MUX_PRESENT
        je      MuxPresent
        cmp     ax,MUX_INFO
        je      MuxInfo
        cmp     ax,MUX_CONTROL
        je      MuxControl
        jmp     dword ptr cs:[OldInt2F]

MuxPresent:
        mov     ax,MUX_PRESENT_REPLY
        iret

MuxInfo:
        mov     ax,MUX_INFO_REPLY
        push    cs
        pop     es
        mov     di,offset ResidentInfo
        iret

MuxControl:
        ; BL = CMD_DISABLE / CMD_ENABLE.
        cmp     byte ptr cs:[Busy],0
        jne     MuxControlBusy

        cmp     bl,CMD_DISABLE
        je      MuxControlValid
        cmp     bl,CMD_ENABLE
        je      MuxControlValid
        cmp     bl,CMD_ASPECT
        je      MuxControlValid
        cmp     bl,CMD_CENTER
        je      MuxControlValid

        mov     ax,MUX_CONTROL_REPLY
        mov     bl,CTL_BAD_COMMAND
        iret

MuxControlValid:
        mov     byte ptr cs:[ControlCommand],bl
        mov     byte ptr cs:[ControlResult],CTL_BAD_COMMAND
        mov     byte ptr cs:[Busy],1

        ; Same proven FAR-CALL DPMI callback bridge used by the INT 10h hook.
        call    dword ptr cs:[CallbackPtr]

        mov     byte ptr cs:[Busy],0
        mov     bl,byte ptr cs:[ControlResult]
        mov     ax,MUX_CONTROL_REPLY
        iret

MuxControlBusy:
        mov     ax,MUX_CONTROL_REPLY
        mov     bl,CTL_BUSY
        iret
NewInt2F endp

; --------------------------------------------------------------------------
; Real-mode INT 10h hook.
; --------------------------------------------------------------------------

NewInt10 proc far
        cmp     ah,00h
        je      HookLegacy
        cmp     ax,4F02h
        je      HookVbe
        jmp     dword ptr cs:[OldInt10]

HookLegacy:
        cmp     byte ptr cs:[Busy],0
        jne     HookChainDirect
        mov     byte ptr cs:[ModeSetKind],1
        mov     byte ptr cs:[RequestedLegacyMode],al
        jmp     HookBegin

HookVbe:
        cmp     byte ptr cs:[Busy],0
        jne     HookChainDirect
        mov     byte ptr cs:[ModeSetKind],2

HookBegin:
        mov     byte ptr cs:[Busy],1

        ; Original BIOS always runs first.
        pushf
        call    dword ptr cs:[OldInt10]

        ; Preserve exact BIOS return state while ASPECTD performs its work.
        pushfd
        pushad
        push    ds
        push    es
        push    fs
        push    gs

        cmp     byte ptr cs:[ModeSetKind],2
        jne     HookCallCallback

        ; Failed VBE mode set: leave BIOS result untouched. Successful VBE
        ; modes use the selected policy exactly like legacy modes: /A can
        ; correct a native-resolution mode, while /C naturally stays 1:1.
        cmp     ax,004Fh
        jne     HookRestore

HookCallCallback:
        mov     byte ptr cs:[ControlCommand],CMD_MODE
        call    dword ptr cs:[CallbackPtr]

HookRestore:
        mov     byte ptr cs:[Busy],0
        pop     gs
        pop     fs
        pop     es
        pop     ds
        popad
        popfd
        iret

HookChainDirect:
        jmp     dword ptr cs:[OldInt10]
NewInt10 endp

; --------------------------------------------------------------------------
; Protected-mode callback.
; No DOS or DPMI calls are made here.
; --------------------------------------------------------------------------

CallbackProc:
        mov     ax,word ptr cs:[DataSelector]
        mov     gs,ax

        mov     ax,word ptr cs:[MmioSelector]
        mov     fs,ax

        mov     al,byte ptr gs:[ControlCommand]
        cmp     al,CMD_DISABLE
        je      CallbackDisable
        cmp     al,CMD_ENABLE
        je      CallbackEnable
        cmp     al,CMD_ASPECT
        je      CallbackSelectAspect
        cmp     al,CMD_CENTER
        je      CallbackSelectCenter

; Normal mode-change correction.
CallbackMode:
        cmp     byte ptr gs:[CorrectionState],STATE_ENABLED
        jne     CallbackReturn

        ; Conservative fixed-raster rule.
        mov     eax,dword ptr fs:[PF_A_SIZE_PAGE]
        cmp     eax,dword ptr gs:[OriginalSize]
        jne     CallbackReturn

        call    CallbackPrepareTarget
        jc      CallbackReturn
        call    CallbackApplyTarget
        jnc     CallbackReturn

        ; A failed verification permanently locks correction until reboot.
        mov     byte ptr gs:[CorrectionState],STATE_WRITE_FAILED
        call    CallbackRestoreOriginal
        jmp     CallbackReturn

; /U and /D.
CallbackDisable:
        cmp     byte ptr gs:[CorrectionState],STATE_WRITE_FAILED
        je      CallbackDisableLocked

        cmp     byte ptr gs:[CorrectionState],STATE_ENABLED
        je      CallbackDisableActive

        mov     byte ptr gs:[ControlResult],CTL_ALREADY_DISABLED
        jmp     CallbackReturn

CallbackDisableLocked:
        mov     byte ptr gs:[ControlResult],CTL_LOCKED
        jmp     CallbackReturn

CallbackDisableActive:
        ; Disable first, so no future mode change can write while deactivated.
        mov     byte ptr gs:[CorrectionState],STATE_USER_DISABLED

        ; Restore the installation fitter state only when the CURRENT state is
        ; exactly ASPECTD's own applied state. If an external path or BIOS
        ; has changed it, leave that state untouched.
        mov     eax,dword ptr fs:[PF_A_POS_PAGE]
        cmp     eax,dword ptr gs:[AppliedPos]
        jne     CallbackDisableNoRestore

        mov     eax,dword ptr fs:[PF_A_SIZE_PAGE]
        cmp     eax,dword ptr gs:[AppliedSize]
        jne     CallbackDisableNoRestore

        call    CallbackRestoreOriginal
        jnc     CallbackDisableRestored

        mov     byte ptr gs:[CorrectionState],STATE_WRITE_FAILED
        mov     byte ptr gs:[ControlResult],CTL_WRITE_FAILED
        jmp     CallbackReturn

CallbackDisableRestored:
        mov     byte ptr gs:[ControlResult],CTL_DISABLED_RESTORED
        jmp     CallbackReturn

CallbackDisableNoRestore:
        mov     byte ptr gs:[ControlResult],CTL_DISABLED_ONLY
        jmp     CallbackReturn

; /E.
CallbackEnable:
        cmp     byte ptr gs:[CorrectionState],STATE_WRITE_FAILED
        je      CallbackEnableLocked

        cmp     byte ptr gs:[CorrectionState],STATE_ENABLED
        je      CallbackEnableAlready

        ; Re-enable future correction first. If this output path currently
        ; matches the installation fixed raster, also apply immediately.
        mov     byte ptr gs:[CorrectionState],STATE_ENABLED

        mov     eax,dword ptr fs:[PF_A_SIZE_PAGE]
        cmp     eax,dword ptr gs:[OriginalSize]
        jne     CallbackEnablePending

        call    CallbackPrepareTarget
        jc      CallbackEnablePending
        call    CallbackApplyTarget
        jnc     CallbackEnableApplied

        mov     byte ptr gs:[CorrectionState],STATE_WRITE_FAILED
        call    CallbackRestoreOriginal
        mov     byte ptr gs:[ControlResult],CTL_WRITE_FAILED
        jmp     CallbackReturn

CallbackEnableApplied:
        mov     byte ptr gs:[ControlResult],CTL_ENABLED_APPLIED
        jmp     CallbackReturn

CallbackEnablePending:
        mov     byte ptr gs:[ControlResult],CTL_ENABLED_PENDING
        jmp     CallbackReturn

CallbackEnableAlready:
        mov     byte ptr gs:[ControlResult],CTL_ALREADY_ENABLED
        jmp     CallbackReturn

CallbackEnableLocked:
        mov     byte ptr gs:[ControlResult],CTL_LOCKED
        jmp     CallbackReturn

; /A or /C - select policy. Immediate application is allowed only when the
; current fitter is the original fixed raster or exactly ASPECTD's own last
; applied state. Otherwise the new policy is remembered for a later mode set.
; Keep /A and /C as explicit entry paths so runtime aspect selection cannot be
; confused with the centered command.
CallbackSelectAspect:
        cmp     byte ptr gs:[CorrectionState],STATE_WRITE_FAILED
        je      CallbackSelectLocked
        mov     byte ptr gs:[CurrentPolicy],POLICY_ASPECT
        jmp     short CallbackSelectState

CallbackSelectCenter:
        cmp     byte ptr gs:[CorrectionState],STATE_WRITE_FAILED
        je      CallbackSelectLocked
        mov     byte ptr gs:[CurrentPolicy],POLICY_CENTER

CallbackSelectState:
        cmp     byte ptr gs:[CorrectionState],STATE_ENABLED
        jne     CallbackSelectDisabled

        mov     eax,dword ptr fs:[PF_A_SIZE_PAGE]
        cmp     eax,dword ptr gs:[OriginalSize]
        je      CallbackSelectApply
        cmp     eax,dword ptr gs:[AppliedSize]
        jne     CallbackSelectPending
        mov     eax,dword ptr fs:[PF_A_POS_PAGE]
        cmp     eax,dword ptr gs:[AppliedPos]
        jne     CallbackSelectPending

CallbackSelectApply:
        call    CallbackPrepareTarget
        jc      CallbackSelectPending
        call    CallbackApplyTarget
        jnc     CallbackSelectApplied

        mov     byte ptr gs:[CorrectionState],STATE_WRITE_FAILED
        call    CallbackRestoreOriginal
        mov     byte ptr gs:[ControlResult],CTL_WRITE_FAILED
        jmp     CallbackReturn
CallbackSelectApplied:
        mov     byte ptr gs:[ControlResult],CTL_POLICY_APPLIED
        jmp     CallbackReturn
CallbackSelectPending:
        mov     byte ptr gs:[ControlResult],CTL_POLICY_PENDING
        jmp     CallbackReturn
CallbackSelectDisabled:
        mov     byte ptr gs:[ControlResult],CTL_POLICY_SELECTED
        jmp     CallbackReturn
CallbackSelectLocked:
        mov     byte ptr gs:[ControlResult],CTL_LOCKED

; Return from DPMI callback to the real-mode FAR CALL site.
CallbackReturn:
        mov     ax,word ptr ds:[esi]
        mov     word ptr es:[edi+RM_IP],ax

        mov     ax,word ptr ds:[esi+2]
        mov     word ptr es:[edi+RM_CS],ax

        add     word ptr es:[edi+RM_SP],4

        ; 32-bit DPMI client running in initial 16-bit CS.
        ; 66 CF = IRETD, hardware-verified during DPMI callback development.
        db      066h,0CFh

; --------------------------------------------------------------------------
; Callback MMIO helpers.
; --------------------------------------------------------------------------

; Prepare the target for the currently selected policy.
; /A copies the static 4:3 geometry. /C reads Pipe A PIPESRC from the separate
; mapped page and centers that exact source raster without fitter scaling.
; CF clear = valid target; CF set = source is invalid/larger than native raster.
CallbackPrepareTarget proc near
        cmp     byte ptr gs:[CurrentPolicy],POLICY_CENTER
        je      CallbackPrepareCenter

        mov     eax,dword ptr gs:[AspectPos]
        mov     dword ptr gs:[AppliedPos],eax
        mov     eax,dword ptr gs:[AspectSize]
        mov     dword ptr gs:[AppliedSize],eax
        clc
        ret

CallbackPrepareCenter:
        push    bx
        push    cx
        push    dx

        mov     ax,word ptr gs:[PipeSelector]
        mov     fs,ax
        mov     eax,dword ptr fs:[PIPE_A_SRC_PAGE]
        mov     dword ptr gs:[PipeSourceTemp],eax
        mov     ax,word ptr gs:[MmioSelector]
        mov     fs,ax
        mov     eax,dword ptr gs:[PipeSourceTemp]

        mov     dx,ax
        shr     eax,16
        inc     ax
        inc     dx
        test    ax,ax
        jz      CallbackPrepareBad
        test    dx,dx
        jz      CallbackPrepareBad

        ; The observed CGA 4-color and EGA 320x200x16 symptoms are consistent
        ; with BIOS modes 04h/05h/0Dh reaching Pipe A as 320x400: vertical x2
        ; already present, horizontal x2 absent. Correct only when that exact
        ; geometry is observed; do not generalize to other 320-wide modes.
        cmp     byte ptr gs:[ModeSetKind],1
        jne     CallbackPrepareCenterSized
        mov     bl,byte ptr gs:[RequestedLegacyMode]
        and     bl,7Fh
        cmp     bl,04h
        je      CallbackPrepareLegacy320Check
        cmp     bl,05h
        je      CallbackPrepareLegacy320Check
        cmp     bl,0Dh
        jne     CallbackPrepareCenterSized
CallbackPrepareLegacy320Check:
        cmp     ax,320
        jne     CallbackPrepareCenterSized
        cmp     dx,400
        jne     CallbackPrepareCenterSized
        shl     ax,1

CallbackPrepareCenterSized:
        cmp     ax,word ptr gs:[NativeWidth]
        ja      CallbackPrepareBad
        cmp     dx,word ptr gs:[NativeHeight]
        ja      CallbackPrepareBad

        mov     bx,ax
        mov     cx,dx

        mov     ax,word ptr gs:[NativeWidth]
        sub     ax,bx
        shr     ax,1
        mov     dx,word ptr gs:[NativeHeight]
        sub     dx,cx
        shr     dx,1

        movzx   eax,ax
        shl     eax,16
        mov     ax,dx
        mov     dword ptr gs:[AppliedPos],eax

        movzx   eax,bx
        shl     eax,16
        mov     ax,cx
        mov     dword ptr gs:[AppliedSize],eax
        pop     dx
        pop     cx
        pop     bx
        clc
        ret
CallbackPrepareBad:
        pop     dx
        pop     cx
        pop     bx
        stc
        ret
CallbackPrepareTarget endp

; Write the prepared target and verify both registers.
CallbackApplyTarget proc near
        mov     eax,dword ptr gs:[AppliedPos]
        mov     dword ptr fs:[PF_A_POS_PAGE],eax

        mov     eax,dword ptr gs:[AppliedSize]
        mov     dword ptr fs:[PF_A_SIZE_PAGE],eax

        mov     eax,dword ptr fs:[PF_A_POS_PAGE]
        cmp     eax,dword ptr gs:[AppliedPos]
        jne     CallbackApplyBad

        mov     eax,dword ptr fs:[PF_A_SIZE_PAGE]
        cmp     eax,dword ptr gs:[AppliedSize]
        jne     CallbackApplyBad

        clc
        ret
CallbackApplyBad:
        stc
        ret
CallbackApplyTarget endp

CallbackRestoreOriginal proc near
        mov     eax,dword ptr gs:[OriginalPos]
        mov     dword ptr fs:[PF_A_POS_PAGE],eax

        mov     eax,dword ptr gs:[OriginalSize]
        mov     dword ptr fs:[PF_A_SIZE_PAGE],eax

        mov     eax,dword ptr fs:[PF_A_POS_PAGE]
        cmp     eax,dword ptr gs:[OriginalPos]
        jne     CallbackRestoreBad

        mov     eax,dword ptr fs:[PF_A_SIZE_PAGE]
        cmp     eax,dword ptr gs:[OriginalSize]
        jne     CallbackRestoreBad

        clc
        ret

CallbackRestoreBad:
        stc
        ret
CallbackRestoreOriginal endp

; --------------------------------------------------------------------------
; Resident data.
; --------------------------------------------------------------------------

OldInt10            dw 0,0            ; offset, segment
OldInt2F            dw 0,0            ; offset, segment
CallbackPtr         dw 0,0            ; offset, segment

DataSelector        dw 0
MmioSelector        dw 0
PipeSelector        dw 0

OriginalPos         dd 0
OriginalSize        dd 0
AspectPos           dd 0
AspectSize          dd 0
AppliedPos          dd 0
AppliedSize         dd 0
PipeSourceTemp      dd 0

NativeWidth         dw 0
NativeHeight        dw 0
RequestedLegacyMode db 0

ModeSetKind         db 0
Busy                db 0
ControlCommand      db CMD_MODE
ControlResult       db 0

; Public resident state.
ResidentInfo label byte
CorrectionState     db STATE_ENABLED
CurrentPolicy       db POLICY_ASPECT
ResidentParas       dw 0

; DPMI callback register image must remain valid for callback lifetime.
CallbackRmcs        db RM_STRUCT_SIZE dup (0)

; DOS TSR request RMCS. DPMI 0300h + DOS AH=31h intentionally never returns.
TsrRmcs             db RM_STRUCT_SIZE dup (0)

; HDPMI32 on the verified system requests 0020h private paragraphs.
; .MODEL TINY does not permit ALIGN 16 here. Reserve 15 extra bytes and
; paragraph-align the ES:0000 address at runtime instead.
DpmiPrivateAreaRaw  db ((HDPMI_PRIVATE_PARAS*16)+15) dup (0)

ResidentEnd label byte

; ==========================================================================
; TRANSIENT INSTALLER / COMMAND REGION
; Discarded when installation becomes resident.
; ==========================================================================

InstallerStart:
        cli
        mov     ax,cs
        mov     ss,ax
        mov     sp,offset InstallerStackTop
        sti

        mov     ds,ax
        mov     es,ax
        mov     word ptr [RealModeSegment],ax

        call    ParseCommand
        mov     byte ptr [StartupCommand],al
        cmp     al,ARG_INVALID
        jne     CommandParsed

        mov     dx,offset MsgUsage
        call    PrintZ
        mov     ax,4C01h
        int     21h

CommandParsed:
        ; Check for an already resident ASPECTD before doing any DPMI work.
        mov     ax,MUX_PRESENT
        int     2Fh
        cmp     ax,MUX_PRESENT_REPLY
        je      ResidentCommand

        ; Default, /A and /C may start a new resident copy. /U, /D and /E
        ; require an existing resident copy.
        cmp     byte ptr [StartupCommand],ARG_DEFAULT
        je      CheckPlainAspectConflict
        cmp     byte ptr [StartupCommand],ARG_ASPECT
        je      CheckPlainAspectConflict
        cmp     byte ptr [StartupCommand],ARG_CENTER
        je      CheckPlainAspectConflict

        mov     dx,offset MsgNotResident
        call    PrintZ
        mov     ax,4C01h
        int     21h

ResidentCommand:
        cmp     byte ptr [StartupCommand],ARG_DEFAULT
        je      ShowResidentState

        cmp     byte ptr [StartupCommand],ARG_DISABLE
        je      SendDisable

        cmp     byte ptr [StartupCommand],ARG_ENABLE
        je      SendEnable
        cmp     byte ptr [StartupCommand],ARG_ASPECT
        je      SendAspect
        cmp     byte ptr [StartupCommand],ARG_CENTER
        je      SendCenter

        mov     dx,offset MsgUsage
        call    PrintZ
        mov     ax,4C01h
        int     21h

SendDisable:
        mov     ax,MUX_CONTROL
        mov     bl,CMD_DISABLE
        int     2Fh
        cmp     ax,MUX_CONTROL_REPLY
        jne     ControlProtocolFail

        call    PrintDisableResult
        mov     ax,4C00h
        int     21h

SendEnable:
        mov     ax,MUX_CONTROL
        mov     bl,CMD_ENABLE
        int     2Fh
        cmp     ax,MUX_CONTROL_REPLY
        jne     ControlProtocolFail

        call    PrintEnableResult
        mov     ax,4C00h
        int     21h

SendAspect:
        mov     ax,MUX_CONTROL
        mov     bl,CMD_ASPECT
        int     2Fh
        cmp     ax,MUX_CONTROL_REPLY
        jne     ControlProtocolFail
        call    PrintPolicyResult
        mov     ax,4C00h
        int     21h

SendCenter:
        mov     ax,MUX_CONTROL
        mov     bl,CMD_CENTER
        int     2Fh
        cmp     ax,MUX_CONTROL_REPLY
        jne     ControlProtocolFail
        call    PrintPolicyResult
        mov     ax,4C00h
        int     21h

ShowResidentState:
        call    PrintResidentState
        mov     ax,4C00h
        int     21h

ControlProtocolFail:
        mov     dx,offset MsgControlFail
        call    PrintZ
        mov     ax,4C01h
        int     21h

CheckPlainAspectConflict:
        ; Do not stack ASPECTD on top of the plain-DOS ASPECT TSR.
        mov     ax,ASPECT_MUX_PRESENT
        int     2Fh
        cmp     ax,ASPECT_MUX_PRESENT_REPLY
        jne     BeginInstall

        mov     dx,offset MsgAspectConflict
        call    PrintZ
        mov     ax,4C01h
        int     21h

BeginInstall:
        mov     byte ptr [CurrentPolicy],POLICY_ASPECT
        cmp     byte ptr [StartupCommand],ARG_CENTER
        jne     BeginInstallPolicySet
        mov     byte ptr [CurrentPolicy],POLICY_CENTER
BeginInstallPolicySet:
        ; Intel graphics BAR0, PCI 00:02.0 config offset 10h.
        mov     di,10h
        call    PciReadDword
        jc      PciFail

        mov     eax,ecx
        and     eax,0FFFFFFF0h
        mov     dword ptr [MmioBase],eax
        test    eax,eax
        jz      BarFail

        mov     eax,dword ptr [MmioBase]
        add     eax,PF_PAGE_OFFSET
        mov     dword ptr [MapPhys],eax
        mov     eax,dword ptr [MmioBase]
        add     eax,PIPE_PAGE_OFFSET
        mov     dword ptr [PipeMapPhys],eax

        ; Detect 32-bit DPMI host and obtain initial switch entry.
        mov     ax,1687h
        int     2Fh
        or      ax,ax
        jnz     NoDpmi
        test    bx,0001h
        jz      NoDpmi32

        mov     word ptr [DpmiEntry],di
        mov     word ptr [DpmiEntry+2],es
        mov     word ptr [PrivateParas],si

        ; Keep the resident private area compact and deterministic.
        cmp     word ptr [PrivateParas],HDPMI_PRIVATE_PARAS
        ja      PrivateTooLarge

        ; Environment is not needed by the resident copy.
        call    FreeEnvironment

        ; DPMI initial-switch private area must be passed as ES:0000.
        ; Round the raw resident buffer upward to the next paragraph boundary.
        mov     bx,offset DpmiPrivateAreaRaw
        add     bx,15
        mov     cl,4
        shr     bx,cl
        mov     ax,cs
        add     ax,bx
        mov     es,ax

        mov     ax,0001h              ; 32-bit DPMI client
        call    dword ptr cs:[DpmiEntry]
        jc      DpmiSwitchFail

        mov     word ptr [DataSelector],ds

        ; Map the 4 KB page containing fitter A POS/SIZE.
        mov     ax,0800h
        mov     bx,word ptr [MapPhys+2]
        mov     cx,word ptr [MapPhys]
        xor     si,si
        mov     di,MAP_SIZE
        int     31h
        jc      MapFail

        mov     word ptr [MapLinear],cx
        mov     word ptr [MapLinear+2],bx
        mov     byte ptr [MapActive],1

        ; Allocate selector for mapped MMIO.
        mov     ax,0000h
        mov     cx,0001h
        int     31h
        jc      SelectorAllocFail

        mov     word ptr [MmioSelector],ax
        mov     byte ptr [SelectorActive],1

        mov     bx,word ptr [MmioSelector]
        mov     cx,word ptr [MapLinear+2]
        mov     dx,word ptr [MapLinear]
        mov     ax,0007h
        int     31h
        jc      SelectorSetupFail

        mov     bx,word ptr [MmioSelector]
        xor     cx,cx
        mov     dx,MAP_SIZE-1
        mov     ax,0008h
        int     31h
        jc      SelectorSetupFail

        ; Map Pipe A timing/source page used by /C. It is retained so policy
        ; switching to centered mode remains possible after installation.
        mov     ax,0800h
        mov     bx,word ptr [PipeMapPhys+2]
        mov     cx,word ptr [PipeMapPhys]
        xor     si,si
        mov     di,MAP_SIZE
        int     31h
        jc      MapFail
        mov     word ptr [PipeMapLinear],cx
        mov     word ptr [PipeMapLinear+2],bx
        mov     byte ptr [PipeMapActive],1

        mov     ax,0000h
        mov     cx,0001h
        int     31h
        jc      SelectorAllocFail
        mov     word ptr [PipeSelector],ax
        mov     byte ptr [PipeSelectorActive],1

        mov     bx,word ptr [PipeSelector]
        mov     cx,word ptr [PipeMapLinear+2]
        mov     dx,word ptr [PipeMapLinear]
        mov     ax,0007h
        int     31h
        jc      SelectorSetupFail

        mov     bx,word ptr [PipeSelector]
        xor     cx,cx
        mov     dx,MAP_SIZE-1
        mov     ax,0008h
        int     31h
        jc      SelectorSetupFail

        ; Capture exact installation fitter state.
        mov     ax,word ptr [MmioSelector]
        mov     fs,ax

        mov     eax,dword ptr fs:[PF_A_POS_PAGE]
        mov     dword ptr [OriginalPos],eax

        mov     eax,dword ptr fs:[PF_A_SIZE_PAGE]
        mov     dword ptr [OriginalSize],eax

        xor     ax,ax
        mov     fs,ax

        call    ComputeAspectGeometry
        jc      GeometryFail

        mov     dx,offset MsgDetected
        call    PrintZ
        mov     ax,word ptr [NativeWidth]
        call    PrintDec16
        mov     dl,'x'
        call    PutCh
        mov     ax,word ptr [NativeHeight]
        call    PrintDec16
        call    PrintCRLF

        cmp     byte ptr [CurrentPolicy],POLICY_CENTER
        je      GeometryNeedsInstall
        cmp     byte ptr [CorrectionNeeded],0
        jne     GeometryNeedsInstall

        mov     dx,offset MsgAlready43
        call    PrintZ
        jmp     ExitPm0

GeometryNeedsInstall:
        ; Apply once to the current output before installing hooks.
        call    ApplyInitialAspect
        jc      InitialWriteFail

        mov     dx,offset MsgTarget
        call    PrintZ
        mov     ax,word ptr [AppliedSize+2]
        call    PrintDec16
        mov     dl,'x'
        call    PutCh
        mov     ax,word ptr [AppliedSize]
        call    PrintDec16
        mov     dx,offset MsgAt
        call    PrintZ
        mov     ax,word ptr [AppliedPos+2]
        call    PrintDec16
        mov     dl,','
        call    PutCh
        mov     ax,word ptr [AppliedPos]
        call    PrintDec16
        call    PrintCRLF

        ; Allocate protected-mode callback.
        push    ds
        push    es
        mov     ax,ds
        mov     es,ax
        xor     edi,edi
        mov     di,offset CallbackRmcs

        mov     ax,cs
        mov     ds,ax
        xor     esi,esi
        mov     si,offset CallbackProc

        mov     ax,0303h
        int     31h

        pop     es
        pop     ds
        jc      CallbackAllocFail

        mov     word ptr [CallbackSeg],cx
        mov     word ptr [CallbackOff],dx
        mov     word ptr [CallbackPtr],dx
        mov     word ptr [CallbackPtr+2],cx
        mov     byte ptr [CallbackActive],1

        ; Save original real-mode vectors.
        mov     ax,0200h
        mov     bl,10h
        int     31h
        mov     word ptr [OldInt10+2],cx
        mov     word ptr [OldInt10],dx

        mov     ax,0200h
        mov     bl,2Fh
        int     31h
        mov     word ptr [OldInt2F+2],cx
        mov     word ptr [OldInt2F],dx

        ; Install INT 10h hook.
        mov     ax,0201h
        mov     bl,10h
        mov     cx,word ptr [RealModeSegment]
        mov     dx,offset NewInt10
        int     31h
        jc      HookInstallFail
        mov     byte ptr [Hook10Active],1

        ; Install INT 2Fh hook.
        mov     ax,0201h
        mov     bl,2Fh
        mov     cx,word ptr [RealModeSegment]
        mov     dx,offset NewInt2F
        int     31h
        jc      MuxInstallFail
        mov     byte ptr [Hook2FActive],1

        ; Verify both vectors.
        mov     ax,0200h
        mov     bl,10h
        int     31h
        cmp     cx,word ptr [RealModeSegment]
        jne     HookVerifyFail
        cmp     dx,offset NewInt10
        jne     HookVerifyFail

        mov     ax,0200h
        mov     bl,2Fh
        int     31h
        cmp     cx,word ptr [RealModeSegment]
        jne     HookVerifyFail
        cmp     dx,offset NewInt2F
        jne     HookVerifyFail

        ; Number of paragraphs retained from PSP through ResidentEnd.
        mov     dx,offset ResidentEnd
        add     dx,15
        mov     cl,4
        shr     dx,cl
        mov     word ptr [ResidentParas],dx

        cmp     byte ptr [CurrentPolicy],POLICY_CENTER
        je      InstallPrintCenter
        mov     dx,offset MsgInstalledAspect
        jmp     short InstallPrintDone
InstallPrintCenter:
        mov     dx,offset MsgInstalledCenter
InstallPrintDone:
        call    PrintZ

        ; Stay resident through DOS AH=31h invoked by DPMI 0300h.
        call    ClearTsrRmcs

        mov     dword ptr [TsrRmcs+RM_EAX],00003100h
        xor     eax,eax
        mov     ax,word ptr [ResidentParas]
        mov     dword ptr [TsrRmcs+RM_EDX],eax

        mov     ax,ds
        mov     es,ax
        xor     edi,edi
        mov     di,offset TsrRmcs
        xor     cx,cx
        xor     bh,bh
        mov     bl,21h
        mov     ax,0300h
        int     31h

        ; DOS AH=31h must never return.
        mov     dx,offset MsgTsrReturned
        call    PrintZ
        call    RestoreHooks
        call    RestoreOriginalFitter
        jmp     ExitPm2

; --------------------------------------------------------------------------
; Geometry calculation.
; --------------------------------------------------------------------------

ComputeAspectGeometry proc near
        mov     eax,dword ptr [OriginalSize]
        mov     edx,eax
        shr     eax,16
        and     edx,0FFFFh

        test    ax,ax
        jz      ComputeBad
        test    dx,dx
        jz      ComputeBad

        mov     word ptr [NativeWidth],ax
        mov     word ptr [NativeHeight],dx

        ; Exact 4:3: width*3 == height*4.
        movzx   eax,word ptr [NativeWidth]
        imul    eax,3
        movzx   edx,word ptr [NativeHeight]
        shl     edx,2
        cmp     eax,edx
        jne     ComputeNeedsCorrection

        mov     byte ptr [CorrectionNeeded],0
        mov     eax,dword ptr [OriginalPos]
        mov     dword ptr [AspectPos],eax
        mov     eax,dword ptr [OriginalSize]
        mov     dword ptr [AspectSize],eax
        mov     ax,word ptr [NativeWidth]
        mov     word ptr [AspectWidth],ax
        mov     ax,word ptr [NativeHeight]
        mov     word ptr [AspectHeight],ax
        mov     word ptr [AspectX],0
        mov     word ptr [AspectY],0
        clc
        ret

ComputeNeedsCorrection:
        mov     byte ptr [CorrectionNeeded],1

        ; First try full output height.
        movzx   eax,word ptr [NativeHeight]
        shl     eax,2
        xor     edx,edx
        mov     ecx,3
        div     ecx
        and     ax,0FFFEh
        cmp     ax,word ptr [NativeWidth]
        ja      ComputeFitByWidth

        mov     word ptr [AspectWidth],ax
        mov     ax,word ptr [NativeHeight]
        mov     word ptr [AspectHeight],ax
        jmp     ComputeCenter

ComputeFitByWidth:
        mov     ax,word ptr [NativeWidth]
        mov     word ptr [AspectWidth],ax
        movzx   eax,ax
        imul    eax,3
        shr     eax,2
        and     ax,0FFFEh
        mov     word ptr [AspectHeight],ax

ComputeCenter:
        mov     ax,word ptr [NativeWidth]
        sub     ax,word ptr [AspectWidth]
        shr     ax,1
        mov     word ptr [AspectX],ax

        mov     ax,word ptr [NativeHeight]
        sub     ax,word ptr [AspectHeight]
        shr     ax,1
        mov     word ptr [AspectY],ax

        xor     eax,eax
        mov     ax,word ptr [AspectX]
        shl     eax,16
        mov     ax,word ptr [AspectY]
        mov     dword ptr [AspectPos],eax

        xor     eax,eax
        mov     ax,word ptr [AspectWidth]
        shl     eax,16
        mov     ax,word ptr [AspectHeight]
        mov     dword ptr [AspectSize],eax

        clc
        ret

ComputeBad:
        stc
        ret
ComputeAspectGeometry endp

; --------------------------------------------------------------------------
; Installation-time fitter write / restore.
; --------------------------------------------------------------------------

ApplyInitialAspect proc near
        push    gs
        mov     ax,ds
        mov     gs,ax
        mov     ax,word ptr [MmioSelector]
        mov     fs,ax

        call    CallbackPrepareTarget
        jc      InitialApplyBad
        call    CallbackApplyTarget
        jc      InitialApplyBad

        xor     ax,ax
        mov     fs,ax
        pop     gs
        clc
        ret

InitialApplyBad:
        xor     ax,ax
        mov     fs,ax
        pop     gs
        call    RestoreOriginalFitter
        stc
        ret
ApplyInitialAspect endp

RestoreOriginalFitter proc near
        cmp     byte ptr [SelectorActive],0
        je      RestoreOriginalDone

        mov     ax,word ptr [MmioSelector]
        mov     fs,ax

        mov     eax,dword ptr [OriginalPos]
        mov     dword ptr fs:[PF_A_POS_PAGE],eax

        mov     eax,dword ptr [OriginalSize]
        mov     dword ptr fs:[PF_A_SIZE_PAGE],eax
        xor     ax,ax
        mov     fs,ax

RestoreOriginalDone:
        ret
RestoreOriginalFitter endp

; --------------------------------------------------------------------------
; Resident state/control output.
; --------------------------------------------------------------------------

PrintResidentState proc near
        push    es
        push    di

        mov     ax,MUX_INFO
        int     2Fh
        cmp     ax,MUX_INFO_REPLY
        jne     PrintStateProtocolBad

        mov     al,byte ptr es:[di+RI_STATE]
        mov     byte ptr [StatusState],al

        mov     al,byte ptr es:[di+RI_POLICY]
        mov     byte ptr [StatusPolicy],al
        mov     ax,word ptr es:[di+RI_RES_PARAS]
        mov     word ptr [StatusParas],ax

        mov     dx,offset MsgResidentPrefix
        call    PrintZ

        cmp     byte ptr [StatusState],STATE_ENABLED
        je      PrintStateEnabled
        cmp     byte ptr [StatusState],STATE_USER_DISABLED
        je      PrintStateDisabled

        mov     dx,offset MsgStateLocked
        call    PrintZ
        jmp     PrintStateMemory

PrintStateEnabled:
        mov     dx,offset MsgStateEnabled
        call    PrintZ
        jmp     PrintStateMemory

PrintStateDisabled:
        mov     dx,offset MsgStateDisabled
        call    PrintZ

PrintStateMemory:
        mov     dx,offset MsgResidentPolicy
        call    PrintZ
        cmp     byte ptr [StatusPolicy],POLICY_CENTER
        je      PrintStateCenter
        mov     dx,offset MsgPolicyAspect
        call    PrintZ
        jmp     short PrintStatePolicyDone
PrintStateCenter:
        mov     dx,offset MsgPolicyCenter
        call    PrintZ
PrintStatePolicyDone:
        mov     dx,offset MsgResidentMemory
        call    PrintZ
        mov     ax,word ptr [StatusParas]
        shl     ax,4
        call    PrintDec16
        mov     dx,offset MsgBytes
        call    PrintZ

        pop     di
        pop     es
        ret

PrintStateProtocolBad:
        pop     di
        pop     es
        mov     dx,offset MsgControlFail
        call    PrintZ
        ret
PrintResidentState endp

PrintDisableResult proc near
        cmp     bl,CTL_DISABLED_RESTORED
        je      PrintDisabledRestored
        cmp     bl,CTL_DISABLED_ONLY
        je      PrintDisabledOnly
        cmp     bl,CTL_ALREADY_DISABLED
        je      PrintAlreadyDisabled
        cmp     bl,CTL_WRITE_FAILED
        je      PrintWriteFailed
        cmp     bl,CTL_LOCKED
        je      PrintDisableLocked
        cmp     bl,CTL_BUSY
        je      PrintBusy

        mov     dx,offset MsgControlFail
        call    PrintZ
        ret

PrintDisabledRestored:
        mov     dx,offset MsgDisabledRestored
        call    PrintZ
        ret

PrintDisabledOnly:
        mov     dx,offset MsgDisabledOnly
        call    PrintZ
        ret

PrintAlreadyDisabled:
        mov     dx,offset MsgAlreadyDisabled
        call    PrintZ
        ret

PrintWriteFailed:
        mov     dx,offset MsgWriteFailed
        call    PrintZ
        ret

PrintDisableLocked:
        mov     dx,offset MsgLocked
        call    PrintZ
        ret

PrintBusy:
        mov     dx,offset MsgBusy
        call    PrintZ
        ret
PrintDisableResult endp

PrintEnableResult proc near
        cmp     bl,CTL_ENABLED_APPLIED
        je      PrintEnabledApplied
        cmp     bl,CTL_ENABLED_PENDING
        je      PrintEnabledPending
        cmp     bl,CTL_ALREADY_ENABLED
        je      PrintAlreadyEnabled
        cmp     bl,CTL_WRITE_FAILED
        je      PrintWriteFailed2
        cmp     bl,CTL_LOCKED
        je      PrintLocked
        cmp     bl,CTL_BUSY
        je      PrintBusy2

        mov     dx,offset MsgControlFail
        call    PrintZ
        ret

PrintEnabledApplied:
        mov     dx,offset MsgEnabledApplied
        call    PrintZ
        ret

PrintEnabledPending:
        mov     dx,offset MsgEnabledPending
        call    PrintZ
        ret

PrintAlreadyEnabled:
        mov     dx,offset MsgAlreadyEnabled
        call    PrintZ
        ret

PrintWriteFailed2:
        mov     dx,offset MsgWriteFailed
        call    PrintZ
        ret

PrintLocked:
        mov     dx,offset MsgLocked
        call    PrintZ
        ret

PrintBusy2:
        mov     dx,offset MsgBusy
        call    PrintZ
        ret
PrintEnableResult endp

PrintPolicyResult proc near
        cmp     bl,CTL_POLICY_APPLIED
        je      PrintPolicyNormal
        cmp     bl,CTL_POLICY_PENDING
        je      PrintPolicyNormal
        cmp     bl,CTL_POLICY_SELECTED
        je      PrintPolicyNormal
        cmp     bl,CTL_WRITE_FAILED
        je      PrintPolicyWriteFail
        cmp     bl,CTL_LOCKED
        je      PrintPolicyLocked
        cmp     bl,CTL_BUSY
        je      PrintPolicyBusy
        mov     dx,offset MsgControlFail
        call    PrintZ
        ret
PrintPolicyNormal:
        cmp     byte ptr [StartupCommand],ARG_CENTER
        je      PrintPolicyCenterOut
        mov     dx,offset MsgModeAspect
        call    PrintZ
        ret
PrintPolicyCenterOut:
        mov     dx,offset MsgModeCenter
        call    PrintZ
        ret
PrintPolicyWriteFail:
        mov     dx,offset MsgWriteFailed
        call    PrintZ
        ret
PrintPolicyLocked:
        mov     dx,offset MsgLocked
        call    PrintZ
        ret
PrintPolicyBusy:
        mov     dx,offset MsgBusy
        call    PrintZ
        ret
PrintPolicyResult endp

; --------------------------------------------------------------------------
; Command parser.
; AL = ARG_DEFAULT / ARG_DISABLE / ARG_ENABLE / ARG_ASPECT / ARG_CENTER / ARG_INVALID.
; --------------------------------------------------------------------------

ParseCommand proc near
        push    bx
        push    si

        xor     bx,bx
        mov     bl,byte ptr cs:[80h]
        or      bx,bx
        jz      ParseDefault

        mov     si,81h

ParseSkipSpaces:
        cmp     bx,0
        je      ParseDefault

        mov     al,byte ptr cs:[si]
        cmp     al,' '
        jne     ParseSlash

        inc     si
        dec     bx
        jmp     ParseSkipSpaces

ParseSlash:
        cmp     al,'/'
        je      ParseLetter
        cmp     al,'-'
        jne     ParseInvalid

ParseLetter:
        inc     si
        dec     bx
        jz      ParseInvalid

        mov     al,byte ptr cs:[si]
        and     al,0DFh

        cmp     al,'U'
        je      ParseDisable
        cmp     al,'D'
        je      ParseDisable
        cmp     al,'E'
        je      ParseEnable
        cmp     al,'A'
        je      ParseAspect
        cmp     al,'C'
        je      ParseCenter
        jmp     ParseInvalid

ParseDisable:
        mov     al,ARG_DISABLE
        jmp     ParseDone

ParseEnable:
        mov     al,ARG_ENABLE
        jmp     ParseDone

ParseAspect:
        mov     al,ARG_ASPECT
        jmp     ParseDone

ParseCenter:
        mov     al,ARG_CENTER
        jmp     ParseDone

ParseDefault:
        mov     al,ARG_DEFAULT
        jmp     ParseDone

ParseInvalid:
        mov     al,ARG_INVALID

ParseDone:
        pop     si
        pop     bx
        ret
ParseCommand endp

; --------------------------------------------------------------------------
; DPMI/DOS resource helpers.
; --------------------------------------------------------------------------

ClearTsrRmcs proc near
        push    ax
        push    cx
        push    di
        push    es

        mov     ax,ds
        mov     es,ax
        mov     di,offset TsrRmcs
        xor     ax,ax
        mov     cx,RM_STRUCT_SIZE/2
        rep     stosw

        pop     es
        pop     di
        pop     cx
        pop     ax
        ret
ClearTsrRmcs endp

RestoreHooks proc near
        cmp     byte ptr [Hook2FActive],0
        je      RestoreNo2F

        mov     ax,0201h
        mov     bl,2Fh
        mov     cx,word ptr [OldInt2F+2]
        mov     dx,word ptr [OldInt2F]
        int     31h
        mov     byte ptr [Hook2FActive],0

RestoreNo2F:
        cmp     byte ptr [Hook10Active],0
        je      RestoreNo10

        mov     ax,0201h
        mov     bl,10h
        mov     cx,word ptr [OldInt10+2]
        mov     dx,word ptr [OldInt10]
        int     31h
        mov     byte ptr [Hook10Active],0

RestoreNo10:
        ret
RestoreHooks endp

CleanupDpmi proc near
        call    RestoreHooks

        cmp     byte ptr [CallbackActive],0
        je      CleanupNoCallback

        mov     cx,word ptr [CallbackSeg]
        mov     dx,word ptr [CallbackOff]
        mov     ax,0304h
        int     31h
        mov     byte ptr [CallbackActive],0

CleanupNoCallback:
        cmp     byte ptr [PipeSelectorActive],0
        je      CleanupNoPipeSelector
        mov     bx,word ptr [PipeSelector]
        mov     ax,0001h
        int     31h
        mov     byte ptr [PipeSelectorActive],0
CleanupNoPipeSelector:
        cmp     byte ptr [SelectorActive],0
        je      CleanupNoSelector

        mov     bx,word ptr [MmioSelector]
        mov     ax,0001h
        int     31h
        mov     byte ptr [SelectorActive],0

CleanupNoSelector:
        cmp     byte ptr [PipeMapActive],0
        je      CleanupNoPipeMap
        mov     bx,word ptr [PipeMapLinear+2]
        mov     cx,word ptr [PipeMapLinear]
        mov     ax,0801h
        int     31h
        mov     byte ptr [PipeMapActive],0
CleanupNoPipeMap:
        cmp     byte ptr [MapActive],0
        je      CleanupDone

        mov     bx,word ptr [MapLinear+2]
        mov     cx,word ptr [MapLinear]
        mov     ax,0801h
        int     31h
        mov     byte ptr [MapActive],0

CleanupDone:
        ret
CleanupDpmi endp

FreeEnvironment proc near
        push    ax
        push    es

        mov     ax,word ptr cs:[2Ch]
        or      ax,ax
        jz      FreeEnvDone

        mov     es,ax
        mov     ah,49h
        int     21h
        jc      FreeEnvDone

        mov     word ptr cs:[2Ch],0

FreeEnvDone:
        pop     es
        pop     ax
        ret
FreeEnvironment endp

; --------------------------------------------------------------------------
; Error paths.
; --------------------------------------------------------------------------

PciFail:
        mov     dx,offset MsgPciFail
        call    PrintZ
        jmp     Exit1

BarFail:
        mov     dx,offset MsgBarFail
        call    PrintZ
        jmp     Exit1

NoDpmi:
        mov     dx,offset MsgNoDpmi
        call    PrintZ
        jmp     Exit1

NoDpmi32:
        mov     dx,offset MsgNo32
        call    PrintZ
        jmp     Exit1

PrivateTooLarge:
        mov     dx,offset MsgPrivateLarge
        call    PrintZ
        mov     ax,word ptr [PrivateParas]
        call    PrintHex16
        call    PrintCRLF
        jmp     Exit1

DpmiSwitchFail:
        mov     dx,offset MsgSwitchFail
        call    PrintZ
        jmp     Exit1

MapFail:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgMapFail
        call    PrintZ
        jmp     ShowPmError

SelectorAllocFail:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgSelAllocFail
        call    PrintZ
        jmp     ShowPmError

SelectorSetupFail:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgSelSetupFail
        call    PrintZ
        jmp     ShowPmError

GeometryFail:
        mov     dx,offset MsgGeometryFail
        call    PrintZ
        jmp     ExitPm1

InitialWriteFail:
        mov     dx,offset MsgInitialWriteFail
        call    PrintZ
        jmp     ExitPm1

CallbackAllocFail:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgCallbackFail
        call    PrintZ
        jmp     ShowPmErrorRestore

HookInstallFail:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgHookFail
        call    PrintZ
        jmp     ShowPmErrorRestore

MuxInstallFail:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgMuxFail
        call    PrintZ
        jmp     ShowPmErrorRestore

HookVerifyFail:
        mov     dx,offset MsgVerifyFail
        call    PrintZ
        call    RestoreOriginalFitter
        jmp     ExitPm1

ShowPmErrorRestore:
        mov     ax,word ptr [LastError]
        call    PrintHex16
        call    PrintCRLF
        call    RestoreOriginalFitter
        jmp     ExitPm1

ShowPmError:
        mov     ax,word ptr [LastError]
        call    PrintHex16
        call    PrintCRLF
        jmp     ExitPm1

ExitPm0:
        call    CleanupDpmi
        mov     ax,4C00h
        int     21h

ExitPm2:
        call    CleanupDpmi
        mov     ax,4C02h
        int     21h

ExitPm1:
        call    CleanupDpmi
        mov     ax,4C01h
        int     21h

Exit1:
        mov     ax,4C01h
        int     21h

; --------------------------------------------------------------------------
; PCI BIOS helper.
; --------------------------------------------------------------------------

PciReadDword proc near
        mov     ax,0B10Ah
        xor     bh,bh
        mov     bl,10h                ; bus 0, device 2, function 0
        int     1Ah
        ret
PciReadDword endp

; --------------------------------------------------------------------------
; Console output.
; --------------------------------------------------------------------------

PutCh proc near
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di

        mov     ah,02h
        int     21h

        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
PutCh endp
PrintZ proc near
        push    ax
        push    si

        mov     si,dx
PrintZLoop:
        lodsb
        or      al,al
        jz      PrintZDone

        mov     dl,al
        call    PutCh
        jmp     PrintZLoop

PrintZDone:
        pop     si
        pop     ax
        ret
PrintZ endp

PrintCRLF proc near
        mov     dx,offset MsgCRLF
        call    PrintZ
        ret
PrintCRLF endp

PrintHexNibble proc near
        and     al,0Fh
        cmp     al,9
        jbe     HexDigit
        add     al,'A'-10
        jmp     HexOut

HexDigit:
        add     al,'0'

HexOut:
        mov     dl,al
        call    PutCh
        ret
PrintHexNibble endp

PrintHex8 proc near
        push    ax

        mov     ah,al
        shr     al,4
        call    PrintHexNibble
        mov     al,ah
        call    PrintHexNibble

        pop     ax
        ret
PrintHex8 endp

PrintHex16 proc near
        push    ax

        mov     al,ah
        call    PrintHex8

        pop     ax
        call    PrintHex8
        ret
PrintHex16 endp

PrintDec16 proc near
        push    ax
        push    bx
        push    cx
        push    dx

        xor     cx,cx
        mov     bx,10
        or      ax,ax
        jnz     DecDivide

        mov     dl,'0'
        call    PutCh
        jmp     DecDone

DecDivide:
        xor     dx,dx
        div     bx
        push    dx
        inc     cx
        or      ax,ax
        jnz     DecDivide

DecOutput:
        pop     dx
        add     dl,'0'
        call    PutCh
        loop    DecOutput

DecDone:
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
PrintDec16 endp

; --------------------------------------------------------------------------
; Transient variables/messages.
; --------------------------------------------------------------------------

DpmiEntry           dd 0
MmioBase            dd 0
MapPhys             dd 0
MapLinear           dd 0
PipeMapPhys         dd 0
PipeMapLinear       dd 0

PrivateParas        dw 0
CallbackSeg         dw 0
CallbackOff         dw 0
LastError           dw 0
RealModeSegment     dw 0

AspectWidth         dw 0
AspectHeight        dw 0
AspectX             dw 0
AspectY             dw 0

StatusParas         dw 0
StatusState         db 0
StatusPolicy        db 0

StartupCommand      db ARG_DEFAULT
CorrectionNeeded    db 0
MapActive           db 0
SelectorActive      db 0
PipeMapActive       db 0
PipeSelectorActive  db 0
CallbackActive      db 0
Hook10Active        db 0
Hook2FActive        db 0

MsgDetected:
        db 'Detected output: ',0
MsgTarget:
        db 'Selected window: ',0
MsgAt:
        db ' at ',0
MsgInstalledAspect:
        db 'ASPECTD: installed (aspect mode).',13,10,0
MsgInstalledCenter:
        db 'ASPECTD: installed (centered mode).',13,10,0

MsgResidentPrefix:
        db 'ASPECTD: ',0
MsgStateEnabled:
        db 'enabled',13,10,0
MsgStateDisabled:
        db 'disabled',13,10,0
MsgStateLocked:
        db 'locked (reboot required)',13,10,0
MsgResidentPolicy:
        db 'Mode: ',0
MsgPolicyAspect:
        db 'aspect',13,10,0
MsgPolicyCenter:
        db 'centered',13,10,0
MsgResidentMemory:
        db 'Resident: ',0
MsgBytes:
        db ' bytes',13,10,0

MsgDisabledRestored:
        db 'ASPECTD: disabled.',13,10,0
MsgDisabledOnly:
        db 'ASPECTD: disabled (output unchanged).',13,10,0
MsgAlreadyDisabled:
        db 'ASPECTD: already disabled.',13,10,0
MsgEnabledApplied:
        db 'ASPECTD: enabled.',13,10,0
MsgEnabledPending:
        db 'ASPECTD: enabled.',13,10,0
MsgAlreadyEnabled:
        db 'ASPECTD: already enabled.',13,10,0
MsgWriteFailed:
        db 'ERROR: fitter write/readback verification failed.',13,10
        db 'ASPECTD disabled further correction writes. Reboot before trying again.',13,10,0
MsgLocked:
        db 'ERROR: ASPECTD is safety-locked after a fitter write/readback failure.',13,10
        db 'Reboot is required before correction can be enabled again.',13,10,0
MsgBusy:
        db 'ERROR: ASPECTD is busy handling a video-mode change. Try the command again.',13,10,0

MsgNotResident:
        db 'ASPECTD: not resident.',13,10,0
MsgAspectConflict:
        db 'ERROR: ASPECT is already resident. Remove it before installing ASPECTD.',13,10,0
MsgAlready43:
        db 'ASPECTD: already 4:3; not installed.',13,10,0
MsgModeAspect:
        db 'ASPECTD: aspect mode.',13,10,0
MsgModeCenter:
        db 'ASPECTD: centered mode.',13,10,0
MsgUsage:
        db 'Usage: ASPECTD [/A|/C|/U|/D|/E]',13,10,0
MsgControlFail:
        db 'ERROR: ASPECTD resident control protocol failed.',13,10,0

MsgPciFail:
        db 'ERROR: PCI BIOS graphics BAR0 read failed.',13,10,0
MsgBarFail:
        db 'ERROR: graphics BAR0 is zero.',13,10,0
MsgNoDpmi:
        db 'ERROR: no DPMI host detected.',13,10,0
MsgNo32:
        db 'ERROR: DPMI host does not support 32-bit clients.',13,10,0
MsgPrivateLarge:
        db 'ERROR: DPMI host private area is larger than supported. Paras=',0
MsgSwitchFail:
        db 'ERROR: initial DPMI switch failed.',13,10,0
MsgMapFail:
        db 'ERROR: physical MMIO mapping failed, AX=',0
MsgSelAllocFail:
        db 'ERROR: MMIO selector allocation failed, AX=',0
MsgSelSetupFail:
        db 'ERROR: MMIO selector setup failed, AX=',0
MsgGeometryFail:
        db 'ERROR: invalid fitter geometry.',13,10,0
MsgInitialWriteFail:
        db 'ERROR: initial fitter write/readback failed; original state restored.',13,10,0
MsgCallbackFail:
        db 'ERROR: DPMI callback allocation failed, AX=',0
MsgHookFail:
        db 'ERROR: INT 10h hook installation failed, AX=',0
MsgMuxFail:
        db 'ERROR: INT 2Fh hook installation failed, AX=',0
MsgVerifyFail:
        db 'ERROR: installed real-mode vectors did not verify.',13,10,0
MsgTsrReturned:
        db 'ERROR: DOS TSR call unexpectedly returned; installation rolled back.',13,10,0

MsgCRLF:
        db 13,10,0
        db 13,10,0

InstallerStack       db 512 dup (0)
InstallerStackTop    label byte

end start
