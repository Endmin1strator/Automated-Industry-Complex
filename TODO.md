# TODO

สถานะ: `[ ]` ยังไม่ได้ทำ · `[x]` ทำ/แก้แล้ว (ยังไม่ได้ทดสอบในเกมจริง)

## To Do

### [x] Party System
- Leader set จาก player ในเซิร์ฟ
- Condition: ต้องเช็คว่ามีคนที่ไม่ได้อยู่ใน whitelist เข้ามาในเซิร์ฟแล้ว หรือ Leader Party ไม่ได้อยู่ใน server
- ถ้าเข้าเงื่อนไข ให้ reset character แล้วยืนนิ่งๆ จากนั้น chat `Tp friend (leaderPartName)`
- ถ้ายังไม่ teleport ไปหา Leader ให้ลอง 3 attempts จนกว่าจะแน่ใจ

> ทำแล้ว (แท็บ Party): เปิด **Party System** แล้วเลือก Leader จาก dropdown **Set Leader** (บันทึกในโปรไฟล์)
> - มีคนนอก whitelist เข้ามา แต่ Leader ยังอยู่ → reset แล้วยืนนิ่ง รอ Leader ย้ายเซิร์ฟก่อนค่อยตาม
> - Leader ไม่อยู่ในเซิร์ฟ → reset, ยืนนิ่ง แล้ว chat `Tp friend <username>` ลอง 3 ครั้ง ครั้งละ 15 วินาที
>   สำเร็จเมื่อ Leader อยู่เซิร์ฟเดียวกัน ถ้าไม่สำเร็จจะพัก 60 วินาทีแล้วค่อยลองใหม่
> - ถ้าตั้ง Leader ไว้ Party จะจัดการคนแปลกหน้าแทน Auto Block (Auto Block ทำงานเฉพาะช่วงพักหลัง Tp ไม่สำเร็จ)

### [x] Target Priority
- สามารถเพิ่ม Player เข้า Target Priority ได้ ยกเว้นตัวเอง
- เช็คว่าเป็นผู้เล่นและยังอยู่ใน server เท่านั้น

> ทำแล้ว: ผู้เล่นในเซิร์ฟ (ยกเว้นตัวเอง) ขึ้นใน dropdown **Add Target** เป็น `@ชื่อ` เพิ่มได้เฉพาะคนที่ยังอยู่ในเซิร์ฟ
> ถ้าออกจากเซิร์ฟจะเลิกล็อกเป้าทันที ใช้กฎเดียวกับมอน (ต้องอยู่ใน Farmzone, ไม่อยู่ใน Deadzone)

### [x] Waypoints Looped & Paired Farmzone/Waypoint/Targets

> ทำแล้ว: เปิด **Waypoint Loop** ในส่วน Waypoints (Profile Settings)
> - จับคู่ Waypoint กับ Farmzone ด้วย dropdown **Pair Waypoint** + **Paired Farm Zone** (ในรายการจะขึ้น `> Z#`)
> - เป้าหมายของแต่ละ Farmzone: เลือกโซนใน **Edit Farm Zone** แล้วเพิ่มจาก **Add Zone Target** (ว่าง = ใช้ Enemy Priority)
> - เดินเส้นทางครบแล้ว ถ้าโซนที่คู่กับ Waypoint นั้นมีเป้าจะสู้ในโซนนั้นโซนเดียว ไม่มีก็เดินถอย N > N-1 > ... > 1
>   ไปหาโซนที่มีเป้า ถ้าไม่เจอเลยจะยืนรอ พอมีเป้าเกิดในโซนไหนก็เดินตาม Waypoint ไปโซนนั้น
> - ระหว่างสู้ในโซนที่คู่ไว้ Return To Farm Zone / Patrol / การเลือกเป้าใช้เฉพาะโซนนั้น
> - ข้อจำกัด: เห็นเป้าได้เฉพาะมอนที่เกมโหลดมาถึงเรา (streaming) โซนที่ไกลมากอาจต้องเดินไปใกล้ก่อนถึงจะเห็น
- พอไปถึง Waypoint สุดท้ายแล้ว ถ้า Farmzone ที่ Paired ไว้กับ Waypoint นั้นไม่เจอ Paired Targets ให้เดินถอยกลับ
  - ตัวอย่าง: Waypoint มีทั้งหมด 10 ตำแหน่ง พอไปถึง 10 แล้วไม่เจอ Paired Targets จะเดินกลับ 10 > 9 > 8 > 7 ... จนถึง 1
- ระหว่างทางให้หา Paired Targets ใน Paired Farmzone ที่ Paired ไว้กับ Waypoint นั้น เช่น Paired Waypoint#1 ไว้กับ Farmzone#1
- หากไม่เจอ Paired Targets ใน Paired Farmzone ทั้งหมด ให้ยืนรอจนกว่า Target จะเกิด
- หาก Target ถูกเพิ่มเข้ามาใน Paired Farmzone#2 แต่ตัวละครอยู่ Paired Farmzone# อื่น ให้เดินกลับไป Paired Farmzone# นั้นตาม Waypoint ที่ตั้งไว้แบบ Dynamic

### [x] Waypoints Priority Wait
- ตอนวิ่งไปถึง Waypoint แล้ว สามารถตั้งใน Priority ให้รอ x วินาที ก่อนไป Waypoint ถัดไป
- Default คือ 0
- Edit ได้จาก UI (ต้องแก้ Utils UI ให้รองรับ)

> ทำแล้ว: รายการ All Waypoints มีช่องตัวเลข "Wait (s)" ทุกแถว (0–600 วินาที) เก็บใน `PLACE_CONFIG.WAYPOINT_WAITS`
> ในโปรไฟล์ ย้าย/ลบ waypoint แล้วค่ารอตามไปด้วย ตอนรอจะยืนนิ่งและไม่เข้าสู้ (เหมือนตอนเดินเส้นทาง)
> ตายหรือเปลี่ยนโปรไฟล์แล้วยกเลิกการรอ Utils: `AddPriority(name, values, { Values = true, ... })`

### [x] UI Priority Draggable
- ลาก Priority ขึ้นลงได้ โดยไม่ต้องกด up/down

> ทำแล้ว: ลากที่ชื่อแถวได้ทุกรายการ Priority (Enemy, Waypoints, Farm Zones, Deadzones, Whitelist) มีเส้นบอกตำแหน่งวาง
> ปุ่ม ▲▼ ยังใช้ได้เหมือนเดิม

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

### [x] เดินออกนอกฟาร์มโซนแล้วยืนนิ่งๆ

> แก้แล้ว:
> - ล็อกเป้าที่อยู่ไกลเกิน 50 studs (`COMBAT_ENGAGE_MAX_DISTANCE`) แล้วโค้ดส่วนสู้สั่ง `Move(0)` ทับคำสั่งเดินเข้าหาเป้าทุกเฟรม เลยยืนนิ่ง ตอนนี้เดินเข้าหาต่อได้
> - ถอยตอนเลือดต่ำแล้วไม่มีมอนใกล้ (30 studs) จะยืนรอฮีลตรงนั้นเลย ถ้าอยู่นอกฟาร์มโซนก็ยืนนอกโซนจนเลือดขึ้น ตอนนี้กลับเข้าโซนก่อนแล้วค่อยยืนฮีลในโซน (เฉพาะตอนเดิน Waypoint ครบแล้ว และเปิด Return To Farm Zone)
