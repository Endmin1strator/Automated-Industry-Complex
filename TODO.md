# TODO

สถานะ: `[ ]` ยังไม่ได้ทำ · `[x]` ทำ/แก้แล้ว (ยังไม่ได้ทดสอบในเกมจริง)

## To Do

### [ ] Party System
- Leader set จาก player ในเซิร์ฟ
- Condition: ต้องเช็คว่ามีคนที่ไม่ได้อยู่ใน whitelist เข้ามาในเซิร์ฟแล้ว หรือ Leader Party ไม่ได้อยู่ใน server
- ถ้าเข้าเงื่อนไข ให้ reset character แล้วยืนนิ่งๆ จากนั้น chat `Tp friend (leaderPartName)`
- ถ้ายังไม่ teleport ไปหา Leader ให้ลอง 3 attempts จนกว่าจะแน่ใจ

### [ ] Target Priority
- สามารถเพิ่ม Player เข้า Target Priority ได้ ยกเว้นตัวเอง
- เช็คว่าเป็นผู้เล่นและยังอยู่ใน server เท่านั้น

### [ ] Waypoints Looped & Paired Farmzone/Waypoint/Targets
- พอไปถึง Waypoint สุดท้ายแล้ว ถ้า Farmzone ที่ Paired ไว้กับ Waypoint นั้นไม่เจอ Paired Targets ให้เดินถอยกลับ
  - ตัวอย่าง: Waypoint มีทั้งหมด 10 ตำแหน่ง พอไปถึง 10 แล้วไม่เจอ Paired Targets จะเดินกลับ 10 > 9 > 8 > 7 ... จนถึง 1
- ระหว่างทางให้หา Paired Targets ใน Paired Farmzone ที่ Paired ไว้กับ Waypoint นั้น เช่น Paired Waypoint#1 ไว้กับ Farmzone#1
- หากไม่เจอ Paired Targets ใน Paired Farmzone ทั้งหมด ให้ยืนรอจนกว่า Target จะเกิด
- หาก Target ถูกเพิ่มเข้ามาใน Paired Farmzone#2 แต่ตัวละครอยู่ Paired Farmzone# อื่น ให้เดินกลับไป Paired Farmzone# นั้นตาม Waypoint ที่ตั้งไว้แบบ Dynamic

### [ ] Waypoints Priority Wait
- ตอนวิ่งไปถึง Waypoint แล้ว สามารถตั้งใน Priority ให้รอ x วินาที ก่อนไป Waypoint ถัดไป
- Default คือ 0
- Edit ได้จาก UI (ต้องแก้ Utils UI ให้รองรับ)

### [ ] UI Priority Draggable
- ลาก Priority ขึ้นลงได้ โดยไม่ต้องกด up/down

## To Fix

### [x] Pinned Items
- Save across `game.PlaceId`
- ลาก Pinned Items ออกนอกจอไม่ได้
- เพิ่มปุ่ม Reset Position ให้ Pinned Items ใน MainUI

> แก้แล้ว: เก็บใน `AutoFarmProfiles/PinnedItems.json` ใช้ร่วมทุก PlaceId (ย้ายของเดิมจากโปรไฟล์มาให้ครั้งแรก),
> บันทึกตำแหน่งตอนลากเสร็จ, ลากออกนอกจอไม่ได้และดึงกลับเข้าจอเมื่อจอเปลี่ยนขนาด,
> ปุ่ม **Reset Pinned Items Position** อยู่ที่แท็บ Status

### [x] Combat
- ต่อยกับมอนใน Farmzone แล้วอยู่ๆ ก็ออกนอกฟาร์มโซนหน้าตาเฉย
- บางทีก็กระโดดหนีเข้า Deadzone

> แก้แล้ว: ทางถอยตอนเลือดต่ำ (`GetRetreatPosition`) ไม่เช็ค Deadzone และทางหนีสำรอง (raw away)
> ไม่เช็คทั้ง Farmzone และ Deadzone แต่ยังกระโดดตามไป ตอนนี้เช็คทั้งคู่แล้ว
> ส่วนการหนีออกจาก Deadzone จะเลือกจุดที่อยู่ใน Farmzone ก่อน

### [x] AutoFind
- เปิดแล้วไม่ยอมตีมอน

> แก้แล้ว: AutoFind ข้ามเส้นทาง Waypoint แต่เงื่อนไขเข้าโจมตียังรอให้เดิน Waypoint ครบก่อน
> เลยได้แค่กด Interact ไม่ยอมตี
