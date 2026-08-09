; BLCSETD.ASM
; Lenovo ThinkPad T430 / Ivy Bridge Intel HD Graphics 4000
; DPMI-compatible LCD backlight PWM duty setter.
;
; DPMI analogue of BLCSET for systems where direct CR0 protected-mode
; switching is not available because EMM386/JEMM386 is active.
;
; Target environment verified by the ASPECTD development path:
;   JEMM386/JEMMEX active
;   HDPMI32.EXE -R resident
;
; BUILD from TOOLS\BRIGHT\BLCSETD:
;   TASM /M9 /I..\..\..\INCL BLCSETD.ASM
;   TLINK /t BLCSETD.OBJ
;
; USAGE:
;   BLCSETD <hex-duty>
;
; EXAMPLES:
;   BLCSETD 0045
;   BLCSETD 01E7
;   BLCSETD 1155
;
; PROVEN REGISTER PATH:
;   BAR0 + 48250h  CPU PWM control/enable
;   BAR0 + 48254h  CPU PWM duty (low 16 bits)
;   BAR0 + C8254h  PCH PWM maximum (upper 16 bits)
;
; Only BAR0+48254h is written. Its upper 16 bits are preserved.
; The requested duty is clamped to the detected maximum.
;
; Unlike BLCSET, this version does not switch CR0 directly. It enters as a
; 32-bit DPMI client, maps only the two 4 KiB MMIO pages that contain the
; required PWM registers, accesses them through DPMI selectors, then releases
; all DPMI resources before terminating.

.model tiny
.386p
.code
org 100h

include T430LCD.INC

CPU_PAGE_OFFSET      equ 048000h
PCH_PAGE_OFFSET      equ 0C8000h

PWM_CPU_CTL2_PAGE    equ (PWM_CPU_CTL2_OFFSET-CPU_PAGE_OFFSET)
PWM_CPU_CTL_PAGE     equ (PWM_CPU_CTL_OFFSET-CPU_PAGE_OFFSET)
PWM_PCH_CTL2_PAGE    equ (PWM_PCH_CTL2_OFFSET-PCH_PAGE_OFFSET)

MAP_SIZE             equ 1000h

; Same verified HDPMI32 private-area allowance used by ASPECTD.
HDPMI_PRIVATE_PARAS  equ 0020h

start:
        cli
        mov     ax,cs
        mov     ss,ax
        mov     sp,offset LocalStackTop
        sti

        mov     ds,ax
        mov     es,ax

        mov     dx,offset MsgTitle
        call    PrintZ

        call    ParseCommandLine
        jc      BadSyntax

        mov     dx,offset MsgRequested
        call    PrintZ
        mov     ax,word ptr [RequestedDuty]
        call    PrintHex16
        call    PrintCRLF

        ; Read graphics MMIO BAR0 from PCI 00:02.0 offset 10h.
        mov     di,10h
        call    PciReadDword
        jc      PciReadFailed

        mov     eax,ecx
        and     eax,0FFFFFFF0h
        mov     dword ptr [MmioBase],eax
        test    eax,eax
        jz      BarInvalid

        mov     dx,offset MsgBar0
        call    PrintZ
        mov     eax,dword ptr [MmioBase]
        call    PrintHex32
        call    PrintCRLF

        ; Physical addresses of only the two MMIO pages BLCSETD needs.
        mov     eax,dword ptr [MmioBase]
        add     eax,CPU_PAGE_OFFSET
        mov     dword ptr [CpuMapPhys],eax

        mov     eax,dword ptr [MmioBase]
        add     eax,PCH_PAGE_OFFSET
        mov     dword ptr [PchMapPhys],eax

        ; Detect a DPMI host and obtain the initial-mode-switch entry point.
        mov     ax,1687h
        int     2Fh
        or      ax,ax
        jnz     NoDpmi
        test    bx,0001h
        jz      NoDpmi32

        mov     word ptr [DpmiEntry],di
        mov     word ptr [DpmiEntry+2],es
        mov     word ptr [PrivateParas],si

        cmp     word ptr [PrivateParas],HDPMI_PRIVATE_PARAS
        ja      PrivateTooLarge

        ; The DPMI initial-switch private area must be supplied as ES:0000.
        ; Reserve 15 bytes of slack and paragraph-align the buffer at runtime.
        mov     bx,offset DpmiPrivateAreaRaw
        add     bx,15
        mov     cl,4
        shr     bx,cl
        mov     ax,cs
        add     ax,bx
        mov     es,ax

        mov     ax,0001h              ; request a 32-bit DPMI client
        call    dword ptr cs:[DpmiEntry]
        jc      DpmiSwitchFailed

        ; DS now addresses our program data through the DPMI client selector.
        ; Map CPU PWM page BAR0+48000h.
        mov     ax,0800h
        mov     bx,word ptr [CpuMapPhys+2]
        mov     cx,word ptr [CpuMapPhys]
        xor     si,si
        mov     di,MAP_SIZE
        int     31h
        jc      CpuMapFailed

        mov     word ptr [CpuMapLinear],cx
        mov     word ptr [CpuMapLinear+2],bx
        mov     byte ptr [CpuMapActive],1

        ; Allocate and configure CPU MMIO selector.
        mov     ax,0000h
        mov     cx,1
        int     31h
        jc      CpuSelectorAllocFailed

        mov     word ptr [CpuSelector],ax
        mov     byte ptr [CpuSelectorActive],1

        mov     bx,word ptr [CpuSelector]
        mov     cx,word ptr [CpuMapLinear+2]
        mov     dx,word ptr [CpuMapLinear]
        mov     ax,0007h
        int     31h
        jc      CpuSelectorSetupFailed

        mov     bx,word ptr [CpuSelector]
        xor     cx,cx
        mov     dx,MAP_SIZE-1
        mov     ax,0008h
        int     31h
        jc      CpuSelectorSetupFailed

        ; Map PCH PWM page BAR0+C8000h.
        mov     ax,0800h
        mov     bx,word ptr [PchMapPhys+2]
        mov     cx,word ptr [PchMapPhys]
        xor     si,si
        mov     di,MAP_SIZE
        int     31h
        jc      PchMapFailed

        mov     word ptr [PchMapLinear],cx
        mov     word ptr [PchMapLinear+2],bx
        mov     byte ptr [PchMapActive],1

        ; Allocate and configure PCH MMIO selector.
        mov     ax,0000h
        mov     cx,1
        int     31h
        jc      PchSelectorAllocFailed

        mov     word ptr [PchSelector],ax
        mov     byte ptr [PchSelectorActive],1

        mov     bx,word ptr [PchSelector]
        mov     cx,word ptr [PchMapLinear+2]
        mov     dx,word ptr [PchMapLinear]
        mov     ax,0007h
        int     31h
        jc      PchSelectorSetupFailed

        mov     bx,word ptr [PchSelector]
        xor     cx,cx
        mov     dx,MAP_SIZE-1
        mov     ax,0008h
        int     31h
        jc      PchSelectorSetupFailed

        call    SetBrightnessDpmi

        ; Report the same useful register values as BLCSET.
        mov     dx,offset MsgCpuCtl2
        call    PrintZ
        mov     eax,dword ptr [CpuCtl2]
        call    PrintHex32
        call    PrintCRLF

        mov     dx,offset MsgOriginal
        call    PrintZ
        mov     eax,dword ptr [OriginalCpuCtl]
        call    PrintHex32
        call    PrintCRLF

        mov     dx,offset MsgPchCtl2
        call    PrintZ
        mov     eax,dword ptr [PchCtl2]
        call    PrintHex32
        call    PrintCRLF

        mov     dx,offset MsgMaximum
        call    PrintZ
        mov     ax,word ptr [MaximumDuty]
        call    PrintHex16
        call    PrintCRLF

        mov     dx,offset MsgApplied
        call    PrintZ
        mov     ax,word ptr [AppliedDuty]
        call    PrintHex16
        call    PrintCRLF

        mov     dx,offset MsgWritten
        call    PrintZ
        mov     eax,dword ptr [WrittenCpuCtl]
        call    PrintHex32
        call    PrintCRLF

        mov     dx,offset MsgReadback
        call    PrintZ
        mov     eax,dword ptr [ReadbackCpuCtl]
        call    PrintHex32
        call    PrintCRLF

        mov     al,byte ptr [SetStatus]
        cmp     al,0
        je      SetSucceeded
        cmp     al,1
        je      NoMaximum
        cmp     al,2
        je      VerifyFailed

        mov     dx,offset MsgUnknownStatus
        call    PrintZ
        jmp     ExitPm2

SetSucceeded:
        mov     dx,offset MsgSuccess
        call    PrintZ
        jmp     ExitPm0

NoMaximum:
        mov     dx,offset MsgNoMaximum
        call    PrintZ
        jmp     ExitPm2

VerifyFailed:
        mov     dx,offset MsgVerifyFailed
        call    PrintZ
        jmp     ExitPm2

; ----------------------------------------------------------------------
; DPMI MMIO operation.
; Exactly mirrors BLCSET's verified register semantics.
; ----------------------------------------------------------------------
SetBrightnessDpmi proc near
        mov     byte ptr [SetStatus],0FFh

        mov     ax,word ptr [CpuSelector]
        mov     fs,ax
        mov     ax,word ptr [PchSelector]
        mov     gs,ax

        ; Read CPU PWM control/enable at BAR0+48250h.
        mov     eax,dword ptr fs:[PWM_CPU_CTL2_PAGE]
        mov     dword ptr [CpuCtl2],eax

        ; Read current CPU PWM duty register at BAR0+48254h.
        mov     eax,dword ptr fs:[PWM_CPU_CTL_PAGE]
        mov     dword ptr [OriginalCpuCtl],eax

        ; Read PCH PWM maximum from upper 16 bits of BAR0+C8254h.
        mov     eax,dword ptr gs:[PWM_PCH_CTL2_PAGE]
        mov     dword ptr [PchCtl2],eax
        mov     edx,eax
        shr     edx,16
        mov     word ptr [MaximumDuty],dx

        ; Reject zero maximum: no MMIO write.
        test    dx,dx
        jz      SetNoMaximum

        ; Clamp requested duty to detected maximum.
        movzx   ecx,word ptr [RequestedDuty]
        movzx   edx,word ptr [MaximumDuty]
        cmp     ecx,edx
        jbe     SetDutyInRange
        mov     ecx,edx
SetDutyInRange:
        mov     word ptr [AppliedDuty],cx

        ; Preserve upper 16 bits and replace only the low duty word.
        mov     eax,dword ptr [OriginalCpuCtl]
        and     eax,0FFFF0000h
        or      eax,ecx
        mov     dword ptr [WrittenCpuCtl],eax

        ; Write BAR0+48254h only.
        mov     dword ptr fs:[PWM_CPU_CTL_PAGE],eax

        ; Serialize posted write and verify low 16 bits.
        mov     eax,dword ptr fs:[PWM_CPU_CTL_PAGE]
        mov     dword ptr [ReadbackCpuCtl],eax

        mov     edx,eax
        and     edx,0000FFFFh
        movzx   ecx,word ptr [AppliedDuty]
        cmp     edx,ecx
        jne     SetVerifyFailed

        mov     byte ptr [SetStatus],0
        jmp     SetDpmiDone

SetNoMaximum:
        mov     byte ptr [SetStatus],1
        jmp     SetDpmiDone

SetVerifyFailed:
        mov     byte ptr [SetStatus],2

SetDpmiDone:
        xor     ax,ax
        mov     fs,ax
        mov     gs,ax
        ret
SetBrightnessDpmi endp

; ----------------------------------------------------------------------
; Parse one hexadecimal command-line argument, 1..4 digits.
; Result: RequestedDuty. CF=0 success, CF=1 error.
; ----------------------------------------------------------------------
ParseCommandLine proc near
        push    ax
        push    bx
        push    cx
        push    dx
        push    si

        xor     bx,bx
        xor     cx,cx
        mov     si,81h
        xor     dx,dx
        mov     dl,byte ptr ds:[80h]

ParseSkipLeading:
        cmp     dx,0
        je      ParseFail
        mov     al,byte ptr [si]
        cmp     al,' '
        jne     ParseDigits
        inc     si
        dec     dx
        jmp     ParseSkipLeading

ParseDigits:
        cmp     dx,0
        je      ParseDone
        mov     al,byte ptr [si]
        cmp     al,' '
        je      ParseTrailing
        cmp     cx,4
        jae     ParseFail

        call    HexToNibble
        jc      ParseFail

        shl     bx,4
        xor     ah,ah
        or      bl,al
        inc     cx
        inc     si
        dec     dx
        jmp     ParseDigits

ParseTrailing:
        inc     si
        dec     dx
ParseTrailingLoop:
        cmp     dx,0
        je      ParseDone
        mov     al,byte ptr [si]
        cmp     al,' '
        jne     ParseFail
        inc     si
        dec     dx
        jmp     ParseTrailingLoop

ParseDone:
        cmp     cx,0
        je      ParseFail
        mov     word ptr [RequestedDuty],bx
        clc
        jmp     ParseExit

ParseFail:
        stc

ParseExit:
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
ParseCommandLine endp

HexToNibble proc near
        cmp     al,'0'
        jb      HexBad
        cmp     al,'9'
        jbe     HexDigit
        and     al,0DFh
        cmp     al,'A'
        jb      HexBad
        cmp     al,'F'
        ja      HexBad
        sub     al,'A'-10
        clc
        ret
HexDigit:
        sub     al,'0'
        clc
        ret
HexBad:
        stc
        ret
HexToNibble endp

; ----------------------------------------------------------------------
; DPMI cleanup.
; Selectors are released before their physical mappings.
; ----------------------------------------------------------------------
CleanupDpmi proc near
        cmp     byte ptr [PchSelectorActive],0
        je      CleanupNoPchSelector
        mov     bx,word ptr [PchSelector]
        mov     ax,0001h
        int     31h
        mov     byte ptr [PchSelectorActive],0

CleanupNoPchSelector:
        cmp     byte ptr [CpuSelectorActive],0
        je      CleanupNoCpuSelector
        mov     bx,word ptr [CpuSelector]
        mov     ax,0001h
        int     31h
        mov     byte ptr [CpuSelectorActive],0

CleanupNoCpuSelector:
        cmp     byte ptr [PchMapActive],0
        je      CleanupNoPchMap
        mov     bx,word ptr [PchMapLinear+2]
        mov     cx,word ptr [PchMapLinear]
        mov     ax,0801h
        int     31h
        mov     byte ptr [PchMapActive],0

CleanupNoPchMap:
        cmp     byte ptr [CpuMapActive],0
        je      CleanupDone
        mov     bx,word ptr [CpuMapLinear+2]
        mov     cx,word ptr [CpuMapLinear]
        mov     ax,0801h
        int     31h
        mov     byte ptr [CpuMapActive],0

CleanupDone:
        ret
CleanupDpmi endp

; ----------------------------------------------------------------------
; Error handling.
; ----------------------------------------------------------------------
PciReadFailed:
        mov     dx,offset MsgPciFail
        call    PrintZ
        jmp     Exit1

BarInvalid:
        mov     dx,offset MsgBarInvalid
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

DpmiSwitchFailed:
        mov     dx,offset MsgSwitchFail
        call    PrintZ
        jmp     Exit1

CpuMapFailed:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgCpuMapFail
        call    PrintZ
        jmp     ShowPmError

CpuSelectorAllocFailed:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgCpuSelAlloc
        call    PrintZ
        jmp     ShowPmError

CpuSelectorSetupFailed:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgCpuSelSetup
        call    PrintZ
        jmp     ShowPmError

PchMapFailed:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgPchMapFail
        call    PrintZ
        jmp     ShowPmError

PchSelectorAllocFailed:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgPchSelAlloc
        call    PrintZ
        jmp     ShowPmError

PchSelectorSetupFailed:
        mov     word ptr [LastError],ax
        mov     dx,offset MsgPchSelSetup
        call    PrintZ
        jmp     ShowPmError

ShowPmError:
        mov     ax,word ptr [LastError]
        call    PrintHex16
        call    PrintCRLF
        jmp     ExitPm1

BadSyntax:
        mov     dx,offset MsgUsage
        call    PrintZ
        jmp     Exit1

ExitPm0:
        call    CleanupDpmi
        mov     ax,4C00h
        int     21h

ExitPm1:
        call    CleanupDpmi
        mov     ax,4C01h
        int     21h

ExitPm2:
        call    CleanupDpmi
        mov     ax,4C02h
        int     21h

Exit1:
        mov     ax,4C01h
        int     21h

; ----------------------------------------------------------------------
; PCI BIOS and console helpers.
; ----------------------------------------------------------------------
PciReadDword proc near
        mov     ax,0B10Ah
        xor     bh,bh
        mov     bl,10h
        int     1Ah
        ret
PciReadDword endp

PrintCRLF proc near
        mov     dx,offset MsgCRLF
        call    PrintZ
        ret
PrintCRLF endp

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

PutCh proc near
        push    ax
        mov     ah,02h
        int     21h
        pop     ax
        ret
PutCh endp

PrintHex32 proc near
        push    eax
        ror     eax,16
        call    PrintHex16
        ror     eax,16
        call    PrintHex16
        pop     eax
        ret
PrintHex32 endp

PrintHex16 proc near
        push    ax
        mov     al,ah
        call    PrintHex8
        pop     ax
        call    PrintHex8
        ret
PrintHex16 endp

PrintHex8 proc near
        push    ax
        push    bx
        mov     bl,al
        mov     al,bl
        shr     al,4
        call    PrintNibble
        mov     al,bl
        and     al,0Fh
        call    PrintNibble
        pop     bx
        pop     ax
        ret
PrintHex8 endp

PrintNibble proc near
        and     al,0Fh
        cmp     al,9
        jbe     PrintNibbleDigit
        add     al,'A'-10
        jmp     short PrintNibbleOut
PrintNibbleDigit:
        add     al,'0'
PrintNibbleOut:
        mov     dl,al
        call    PutCh
        ret
PrintNibble endp

; ----------------------------------------------------------------------
; Messages.
; ----------------------------------------------------------------------
MsgTitle:
        db 13,10,'BLCSETD - DPMI ThinkPad T430 LCD PWM duty setter',13,10,0
MsgUsage:
        db 'Usage: BLCSETD <hex-duty>',13,10
        db 'Examples: BLCSETD 0045   BLCSETD 01E7   BLCSETD 1155',13,10,0
MsgRequested:
        db 'Requested duty: ',0
MsgBar0:
        db 'Graphics MMIO BAR0: ',0
MsgCpuCtl2:
        db '  +48250 CPU_CTL2 : ',0
MsgOriginal:
        db '  +48254 original : ',0
MsgPchCtl2:
        db '  +C8254 PCH_CTL2 : ',0
MsgMaximum:
        db '  detected maximum: ',0
MsgApplied:
        db '  applied duty    : ',0
MsgWritten:
        db '  value written   : ',0
MsgReadback:
        db '  readback        : ',0
MsgSuccess:
        db 'Brightness duty changed and verified.',13,10,0
MsgNoMaximum:
        db 'Aborted: detected PWM maximum is zero; no MMIO write performed.',13,10,0
MsgVerifyFailed:
        db 'ERROR: MMIO write readback did not match requested duty.',13,10,0
MsgUnknownStatus:
        db 'ERROR: unknown DPMI MMIO status.',13,10,0
MsgPciFail:
        db 'PCI BIOS configuration read failed.',13,10,0
MsgBarInvalid:
        db 'BAR0 is zero; refusing MMIO access.',13,10,0
MsgNoDpmi:
        db 'ERROR: no DPMI host detected.',13,10,0
MsgNo32:
        db 'ERROR: DPMI host does not support 32-bit clients.',13,10,0
MsgPrivateLarge:
        db 'ERROR: DPMI host private area is larger than supported. Paras=',0
MsgSwitchFail:
        db 'ERROR: DPMI initial-mode switch failed.',13,10,0
MsgCpuMapFail:
        db 'ERROR: CPU PWM physical mapping failed. DPMI AX=',0
MsgCpuSelAlloc:
        db 'ERROR: CPU PWM selector allocation failed. DPMI AX=',0
MsgCpuSelSetup:
        db 'ERROR: CPU PWM selector setup failed. DPMI AX=',0
MsgPchMapFail:
        db 'ERROR: PCH PWM physical mapping failed. DPMI AX=',0
MsgPchSelAlloc:
        db 'ERROR: PCH PWM selector allocation failed. DPMI AX=',0
MsgPchSelSetup:
        db 'ERROR: PCH PWM selector setup failed. DPMI AX=',0
MsgCRLF:
        db 13,10,0

; ----------------------------------------------------------------------
; Variables.
; ----------------------------------------------------------------------
DpmiEntry           dd 0
MmioBase            dd 0
CpuMapPhys          dd 0
PchMapPhys          dd 0
CpuMapLinear        dd 0
PchMapLinear        dd 0

CpuSelector         dw 0
PchSelector         dw 0
PrivateParas        dw 0
LastError           dw 0

CpuCtl2             dd 0
OriginalCpuCtl      dd 0
PchCtl2             dd 0
WrittenCpuCtl       dd 0
ReadbackCpuCtl      dd 0

RequestedDuty       dw 0
MaximumDuty         dw 0
AppliedDuty         dw 0

CpuMapActive        db 0
PchMapActive        db 0
CpuSelectorActive   db 0
PchSelectorActive   db 0
SetStatus           db 0FFh

; DPMI host private area. Same size policy as ASPECTD.
DpmiPrivateAreaRaw  db ((HDPMI_PRIVATE_PARAS*16)+15) dup (0)

LocalStack          db 512 dup (0)
LocalStackTop label byte

end start
