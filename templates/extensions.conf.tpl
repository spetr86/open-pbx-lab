[general]
static=yes
writeprotect=no

[internal]
exten => ${ASTERISK_EXT_A_NUMBER},1,Dial(PJSIP/${ASTERISK_EXT_A_NUMBER},20)
 same => n,Hangup()

exten => ${ASTERISK_EXT_B_NUMBER},1,Dial(PJSIP/${ASTERISK_EXT_B_NUMBER},20)
 same => n,Hangup()
