# State Machine (Draft)

States:
- IDLE (locked, waiting for card)
- UNLOCKED (door unlocked for N seconds, then relock)
- LOCKOUT (after 3 wrong attempts, ignore cards for 30 seconds)

Events:
- TAG_OK
- TAG_BAD
- UNLOCK_TIMER_EXPIRE
- LOCKOUT_TIMER_TICK/EXPIRE
- POWER_FAIL (save EEPROM)
- POWER_RETURN (restore EEPROM)
