# Test Checklist

- [ ] LED blinks / basic boot works
- [ ] RFID reads tag ID reliably
- [ ] Authorized tag unlocks
- [ ] Wrong tag increments counter
- [ ] After 3 wrong attempts -> 30s lockout
- [ ] Buzzer alerts on wrong + during lockout
- [ ] Power-fail event saves EEPROM
- [ ] Power return restores lock + lockout state
