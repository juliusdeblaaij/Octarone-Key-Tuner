; replace the following variables if needed for your preferences!
;
JSPath := "MIDI Tools/Key Tuner" . JSPath  ; this is the path to the JSFX under the JS Effects folder, change it if you put them somewhere else :)
VSTid := "rejs"                            ; the default is "rejs", if you use something else, please change this ID here (don't touch it if you have no idea what it is)


#NoTrayIcon
#MaxMem 1
FileEncoding  ; ANSI
StringCaseSense, Off
SetFormat, FloatFast, 0.15

VarSetCapacity(data1, 256)   ; the 'JS string' that holds 2-bytes per Scale: Key and Number of Notes, but also first 2 bytes pitchbend_range and cnt_max
VarSetCapacity(data2, 66048) ; the other float data: Key Tuning and the note data themselves

state := 0
scale := 1
offset1 := 2
offset2 := 0


FileSelectFile, file, 3, , Browse to Scale Text File`, or Bank/Preset, Scale Text/Bank (*.fxb; *.fxp; *.txt)
if(ErrorLevel || file="")
  ExitApp

line := FileOpen(file, "r")  ; open it in line first
if(line = 0)
{
  MsgBox, 16, , Can't open the file, error code: %A_LastError%
  ExitApp
}

if(line.Read(4) = "CcnK")    ; if a Bank/Preset... (added later)
  Goto Decode
line.Close()



NumPut(2 + 15*256, data1, 0, "ushort")  ; pitchbend_range and cnt_max defaults

Loop, Read, %file%
{
  line := Trim(A_LoopReadLine)
  if(line = "")
    continue

  if state between 1 and 4
  {
    pos := InStr(line, ":")
    if(pos = 0)
      Goto Invalid
  }
  GoSub State%state%
}
if(state + scale = 1)
{
  MsgBox, 16, , The file has no scales at all!
  ExitApp
}
if(state <> 0)
{
  MsgBox, 16, , The last scale is incomplete
  ExitApp
}

; now dump the output to fxb
pos := InStr(file, ".", true, 0)
if(pos)
  file := SubStr(file, 1, pos-1)
file .= ".fxb"

file := FileOpen(file, "w")
OutErr:
if(file = 0)
{
  MsgBox, 16, , Can't open output file, error code: %A_LastError%
  ExitApp
}

file.Write("CcnK")
pos := StrLen(JSPath) + (offset1+3&~3) + offset2 + 290
file.WriteUInt(((pos>>24)&0xFF) | ((pos>>8)&0xFF00) | ((pos&0xFF00)<<8) | (pos<<24))  ; big endian, meh...
file.Write("FBCh")
file.WriteUInt(0x01000000)
file.Write(VSTid)
file.WriteUInt(0x4C040000)
file.WriteUInt(0x01000000)
Loop, 16
  file.WriteInt64(0)
pos -= 152
file.WriteUInt(((pos>>24)&0xFF) | ((pos>>8)&0xFF00) | ((pos&0xFF00)<<8) | (pos<<24))
file.Write(JSPath)
file.WriteUChar(0)
Loop, 32
  file.Write("- - ")
file.WriteUChar(0)
file.WriteUInt((offset1+3&~3) + offset2 + 4)

file.WriteUInt(offset1)
file.RawWrite(data1, offset1)
if(offset1 & 3)
  Loop % 4 - (offset1 & 3)
    file.WriteUChar(0)

file.RawWrite(data2, offset2)

End:
file.Close()
MsgBox, 64, , Done
ExitApp




State0:
if(!RegExMatch(line, "i)^\[Scale \d+]$"))
  return

pos := SubStr(SubStr(line, 8), 1, -1)
if(pos <> scale)
{
  if(pos = 0)
  {
    MsgBox, 16, , Scale numbers start from 1, i.e [Scale 1]
    ExitApp
  }
  if(pos > scale)
  {
    MsgBox, 16, , The Scale Number should be %scale%:`n`n%line%
    ExitApp
  }
  MsgBox, 16, , Duplicated [Scale %pos%]; should be [Scale %scale%]
  ExitApp
}
if(scale > 128)
{
  MsgBox, 16, , Too many scales! [Scale 128] is the last one possible.
  ExitApp
}
state++
return


State1:
if(SubStr(line, 1, pos-1) <> "Key")
  Goto Invalid
pos := Trim(SubStr(line, pos+1))
if(!RegExMatch(pos, "^\d+$") || pos > 127)
  Goto Invalid

NumPut(pos, data1, offset1++, "uchar")
state++
return


State2:
if(SubStr(line, 1, pos-1) <> "Key Tuning")
  Goto Invalid

pos := Trim(SubStr(line, pos+1))
if(!RegExMatch(pos, "i)^\d+(\.\d+)?(Hz)?$"))
  Goto Invalid

if(SubStr(pos, -1) = "Hz")
  pos := ln(SubStr(pos, 1, -2))*17.3123404906675608883 - 36.3763165622959152488  ; A4(69) = 440Hz

if(pos > 127)
  Goto Invalid
NumPut(pos, data2, offset2, "float")
offset2 += 4
state++
return


State3:
if(SubStr(line, 1, pos-1) <> "Number of Notes")
  Goto Invalid
notes := Trim(SubStr(line, pos+1))
if(!RegExMatch(notes, "^\d+$") || notes = 0 || notes > 127)
  Goto Invalid

NumPut(notes, data1, offset1, "uchar")
state++
return


State4:
if(line <> "Notes:")
  Goto Invalid
state++
return


State5:
if(!RegExMatch(line, "i)^\d+(\.\d+|[ \t]*/[ \t]*\d+)?$"))
  Goto Invalid

if(InStr(line, "."))
  pos := line*0.01
else
{
  pos := InStr(line, "/")
  if(pos)
    pos := Trim(SubStr(line, 1, pos-1)) / Trim(SubStr(line, pos+1))
  else
    pos := line
  pos := ln(pos)*17.3123404906675608883
}
if(pos = 0)
{
  MsgBox, 16, , Note can't be 0 cents in [Scale %scale%]:`n`n%line%
  ExitApp
}
if(pos > 127)
{
  MsgBox, 16, , Note is too big:`n`n%line%
  ExitApp
}

note_list .= pos "`n"
if(--notes = 0)
{
  Sort, note_list, NU
  NumPut(NumGet(data1, offset1, "uchar") - ErrorLevel, data1, offset1, "uchar")
  offset1++

  Loop, Parse, note_list, `n
  {
    NumPut(A_LoopField, data2, offset2, "float")
    offset2 += 4
  }
  offset2 -= 4  ; get rid of last empty element
  note_list=
  state := 0
  scale++
}
return



Invalid:
MsgBox, 16, , Invalid Line in [Scale %scale%]:`n`n%line%
ExitApp






















Decode:
state := file
file := line
pos := file.ReadUInt()
if(((pos>>24)&0xFF) | ((pos>>8)&0xFF00) | ((pos&0xFF00)<<8) | ((pos<<24)&0xFF000000) <> file.Length-8)
  Goto Corrupt

line := 128
pos := file.Read(4)
if(pos <> "FBCh")
{
  if(pos <> "FPCh")
    Goto Corrupt
  line -= 100
}
if(file.ReadUInt() = "" || file.Read(4) <> VSTid || file.ReadUInt() = 0 || file.ReadUInt() <> 0x01000000 || file.RawRead(pos, line) <> line)
  Goto Corrupt

pos := file.ReadUInt()
if(((pos>>24)&0xFF) | ((pos>>8)&0xFF00) | ((pos&0xFF00)<<8) | ((pos<<24)&0xFF000000) <> file.Length-line-32)
  Goto Corrupt

Loop % StrLen(JSPath)+1
{
  pos := file.ReadUChar()
  if(pos <> NumGet(JSPath, A_Index-1, "uchar"))
    Goto Corrupt
}
Loop, 32
  if(file.Read(4) <> "- - ")
    Goto Corrupt
if(file.ReadUChar() <> 0)
  Goto Corrupt
if(file.ReadUInt() <> file.Length-line-StrLen(JSPath)-166)
  Goto Corrupt

line := file.ReadUInt()
if(line < 4 || line > 258 || line&1)
  Goto Corrupt

if(file.RawRead(data1, line) <> line)
  Goto Corrupt
if(line & 2)
  file.ReadUShort()  ; skip padding

pos := file.RawRead(data2, 66048)
if(pos = 0 || pos&3 || file.AtEOF = 0)
  Goto Corrupt
file.Close()


; line is the size of data1 list
; now dump the output to Scale txt
pos := InStr(state, ".", true, 0)
if(pos)
  file := SubStr(state, 1, pos-1)
file .= ".txt"

file := FileOpen(file, "w`n")
if(file = 0)
  Goto OutErr


SetFormat, FloatFast, 0.8
Loop
{
  if(offset1 > 2)
    file.Write("`n`n")

  notes := NumGet(data1, offset1+1, "uchar")
  file.Write("[Scale " . scale . "]`nKey: " . NumGet(data1, offset1, "uchar") . "`nKey Tuning: " . RegExReplace((Exp(NumGet(data2, offset2, "float")*0.05776226504666210912)*8.1757989156437073337), "\.?0+$") . "Hz`nNumber of Notes: " . notes . "`nNotes:")
  offset1 += 2
  offset2 += 4
  Loop % notes
  {
    file.Write("`n  " . RegExReplace(NumGet(data2, offset2, "float")*100, "(\.\d+?)0+$", "$1"))
    offset2 += 4
  }
  scale++
} Until offset1 = line

Goto End



Corrupt:
MsgBox, 16, , The file is an invalid ReaJS Bank/Preset for the Key Tuner
ExitApp